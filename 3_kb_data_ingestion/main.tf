terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.57"
    }
  }
  required_version = "~> 1.10"
}


# Use data sources to get common information about the environment
data "aws_caller_identity" "this" {}
data "aws_partition" "this" {}
data "aws_region" "this" {}

data "aws_iam_policy" "lambda_basic_execution" {
  name = "AWSLambdaBasicExecutionRole"
}

data "archive_file" "start_kb_ingestion_jobs_zip" {
  type             = "zip"
  source_file      = "${path.module}/lambda/start_kb_ingestion_jobs/index.py"
  output_path      = "${path.module}/tmp/start_kb_ingestion_jobs.zip"
  output_file_mode = "0666"
}

data "archive_file" "check_kb_ingestion_job_statuses_zip" {
  type             = "zip"
  source_file      = "${path.module}/lambda/check_kb_ingestion_job_statuses/index.py"
  output_path      = "${path.module}/tmp/check_kb_ingestion_job_statuses.zip"
  output_file_mode = "0666"
}

locals {
  account_id            = data.aws_caller_identity.this.account_id
  partition             = data.aws_partition.this.partition
  region                = data.aws_region.this.name
  region_name_tokenized = split("-", local.region)
  region_short          = "${substr(local.region_name_tokenized[0], 0, 2)}${substr(local.region_name_tokenized[1], 0, 1)}${local.region_name_tokenized[2]}"
}

resource "aws_sqs_queue" "check_kb_ingestion_job_statuses" {
  name = "check-kb-ingestion-job-statuses"
}

resource "aws_ssm_parameter" "start_kb_ingestion_jobs_config_json" {
  name  = "/start-kb-ingestion-jobs/config-json"
  type  = "String"
  value = jsonencode(var.start_kb_ingestion_jobs_config_json)
}

resource "aws_ssm_parameter" "start_kb_ingestion_jobs_sqs_queue_url" {
  name  = "/start-kb-ingestion-jobs/sqs-queue-url"
  type  = "String"
  value = aws_sqs_queue.check_kb_ingestion_job_statuses.id
}

resource "aws_iam_role" "lambda_start_kb_ingestion_jobs" {
  name = "FunctionExecutionRoleForLambda-start-kb-ingestion-jobs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = "${local.account_id}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_start_kb_ingestion_jobs_lambda_basic_execution" {
  role       = aws_iam_role.lambda_start_kb_ingestion_jobs.name
  policy_arn = data.aws_iam_policy.lambda_basic_execution.arn
}

resource "aws_iam_role_policy" "lambda_start_kb_ingestion_jobs" {
  name = "FunctionExecutionRolePolicyForLambda-start-kb-ingestion-jobs"
  role = aws_iam_role.lambda_start_kb_ingestion_jobs.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Effect   = "Allow"
        Resource = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/*"
      },
      {
        Action   = "sqs:SendMessage"
        Effect   = "Allow"
        Resource = "arn:${local.partition}:sqs:${local.region}:${local.account_id}:*"
      },
      {
        Action = [
          "bedrock:StartIngestionJob"
        ]
        Effect   = "Allow"
        Resource = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:knowledge-base/*"
      }
    ]
  })
}

resource "aws_lambda_function" "start_kb_ingestion_jobs" {
  function_name = "start-kb-ingestion-jobs"
  role          = aws_iam_role.lambda_start_kb_ingestion_jobs.arn
  description   = "Lambda function that starts ingestion jobs for Bedrock Knowledge Bases"
  filename      = data.archive_file.start_kb_ingestion_jobs_zip.output_path
  handler       = "index.lambda_handler"
  runtime       = "python3.13"
  architectures = ["arm64"]
  timeout       = 60
  # source_code_hash is required to detect changes to Lambda code/zip
  source_code_hash = data.archive_file.start_kb_ingestion_jobs_zip.output_base64sha256
}

resource "aws_cloudwatch_event_rule" "start_kb_ingestion_jobs" {
  name                = "lambda-start-kb-ingestion-jobs"
  schedule_expression = var.start_kb_ingestion_jobs_schedule
}

resource "aws_cloudwatch_event_target" "start_kb_ingestion_jobs" {
  rule = aws_cloudwatch_event_rule.start_kb_ingestion_jobs.name
  arn  = aws_lambda_function.start_kb_ingestion_jobs.arn
}

resource "aws_lambda_permission" "start_kb_ingestion_jobs" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_kb_ingestion_jobs.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_kb_ingestion_jobs.arn
}

resource "aws_sns_topic" "check_kb_ingestion_job_statuses_success" {
  name = "check-kb-ingestion-job-statuses-success"
}

resource "aws_sns_topic" "check_kb_ingestion_job_statuses_failure" {
  name = "check-kb-ingestion-job-statuses-failure"
}

resource "aws_ssm_parameter" "check_kb_ingestion_job_statuses_sqs_queue_url" {
  name  = "/check-kb-ingestion-job-statuses/sqs-queue-url"
  type  = "String"
  value = aws_sqs_queue.check_kb_ingestion_job_statuses.id
}

resource "aws_ssm_parameter" "check_kb_ingestion_job_statuses_success" {
  name  = "/check-kb-ingestion-job-statuses/success-sns-topic-arn"
  type  = "String"
  value = aws_sns_topic.check_kb_ingestion_job_statuses_success.arn
}

resource "aws_ssm_parameter" "check_kb_ingestion_job_statuses_failure" {
  name  = "/check-kb-ingestion-job-statuses/failure-sns-topic-arn"
  type  = "String"
  value = aws_sns_topic.check_kb_ingestion_job_statuses_failure.arn
}

resource "aws_iam_role" "lambda_check_kb_ingestion_job_statuses" {
  name = "FunctionExecutionRoleForLambda-check-kb-ingestion-job-statuses"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = "${local.account_id}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_check_kb_ingestion_job_statuses_lambda_basic_execution" {
  role       = aws_iam_role.lambda_check_kb_ingestion_job_statuses.name
  policy_arn = data.aws_iam_policy.lambda_basic_execution.arn
}

resource "aws_iam_role_policy" "lambda_check_kb_ingestion_job_statuses" {
  name = "FunctionExecutionRolePolicyForLambda-check-kb-ingestion-job-statuses"
  role = aws_iam_role.lambda_check_kb_ingestion_job_statuses.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "bedrock:GetIngestionJob"
        ]
        Effect   = "Allow"
        Resource = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:knowledge-base/*"
      },
      {
        Action   = "sns:Publish"
        Effect   = "Allow"
        Resource = "arn:${local.partition}:sns:${local.region}:${local.account_id}:*"
      },
      {
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Effect   = "Allow"
        Resource = "arn:${local.partition}:sqs:${local.region}:${local.account_id}:*"
      },
      {
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Effect   = "Allow"
        Resource = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/*"
      }
    ]
  })
}

resource "aws_lambda_function" "check_kb_ingestion_job_statuses" {
  function_name = "check-kb-ingestion-job-statuses"
  role          = aws_iam_role.lambda_check_kb_ingestion_job_statuses.arn
  description   = "Lambda function that checks the status of ingestion jobs for Bedrock Knowledge Bases"
  filename      = data.archive_file.check_kb_ingestion_job_statuses_zip.output_path
  handler       = "index.lambda_handler"
  runtime       = "python3.13"
  architectures = ["arm64"]
  # source_code_hash is required to detect changes to Lambda code/zip
  source_code_hash = data.archive_file.check_kb_ingestion_job_statuses_zip.output_base64sha256
}

resource "aws_cloudwatch_event_rule" "check_kb_ingestion_job_statuses" {
  name                = "lambda-check-kb-ingestion-job-statuses"
  schedule_expression = var.check_kb_ingestion_job_statuses_schedule
}

resource "aws_cloudwatch_event_target" "check_kb_ingestion_job_statuses" {
  rule = aws_cloudwatch_event_rule.check_kb_ingestion_job_statuses.name
  arn  = aws_lambda_function.check_kb_ingestion_job_statuses.arn
}

resource "aws_lambda_permission" "check_kb_ingestion_job_statuses" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.check_kb_ingestion_job_statuses.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.check_kb_ingestion_job_statuses.arn
}
