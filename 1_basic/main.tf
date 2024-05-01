terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.47"
    }
  }
  required_version = "~> 1.5"
}

# Use data sources to get common information about the environment
data "aws_caller_identity" "this" {}
data "aws_partition" "this" {}
data "aws_region" "this" {}

data "aws_bedrock_foundation_model" "this" {
  model_id = var.model_id
}

data "aws_iam_policy" "lambda_basic_execution" {
  name = "AWSLambdaBasicExecutionRole"
}

data "archive_file" "forex_api_zip" {
  type             = "zip"
  source_file      = "${path.module}/lambda/forex_api/index.py"
  output_path      = "${path.module}/tmp/forex_api.zip"
  output_file_mode = "0666"
}

locals {
  account_id = data.aws_caller_identity.this.account_id
  partition  = data.aws_partition.this.partition
  region     = data.aws_region.this.name
}

# Agent resource role
resource "aws_iam_role" "bedrock_agent_forex_asst" {
  name = "AmazonBedrockExecutionRoleForAgents_${var.agent_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:agent/*"
          }
        }
      }
    ]
  })
}

# Action group Lambda execution role
resource "aws_iam_role_policy" "bedrock_agent_forex_asst" {
  name = "AmazonBedrockAgentBedrockFoundationModelPolicy_${var.agent_name}"
  role = aws_iam_role.bedrock_agent_forex_asst.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "bedrock:InvokeModel"
        Effect   = "Allow"
        Resource = data.aws_bedrock_foundation_model.this.model_arn
      }
    ]
  })
}


resource "aws_iam_role" "lambda_forex_api" {
  name = "FunctionExecutionRoleForLambda_${var.action_group_name}"
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
  managed_policy_arns = [data.aws_iam_policy.lambda_basic_execution.arn]
}

# Action group Lambda function
resource "aws_lambda_function" "forex_api" {
  function_name = var.action_group_name
  role          = aws_iam_role.lambda_forex_api.arn
  description   = "A Lambda function for the action group ${var.action_group_name}"
  filename      = data.archive_file.forex_api_zip.output_path
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  # source_code_hash is required to detect changes to Lambda code/zip
  source_code_hash = data.archive_file.forex_api_zip.output_base64sha256
}


resource "aws_lambda_permission" "forex_api" {
  action         = "lambda:invokeFunction"
  function_name  = aws_lambda_function.forex_api.function_name
  principal      = "bedrock.amazonaws.com"
  source_account = local.account_id
  source_arn     = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:agent/*"
}

resource "aws_bedrockagent_agent" "forex_asst" {
  agent_name              = var.agent_name
  agent_resource_role_arn = aws_iam_role.bedrock_agent_forex_asst.arn
  description             = var.agent_desc
  foundation_model        = data.aws_bedrock_foundation_model.this.model_id
  instruction             = file("${path.module}/prompt_templates/instruction.txt")
}

resource "aws_bedrockagent_agent_action_group" "forex_api" {
  action_group_name          = var.action_group_name
  agent_id                   = aws_bedrockagent_agent.forex_asst.id
  agent_version              = "DRAFT"
  description                = var.action_group_desc
  skip_resource_in_use_check = true
  action_group_executor {
    lambda = aws_lambda_function.forex_api.arn
  }
  api_schema {
    payload = file("${path.module}/lambda/forex_api/schema.yaml")
  }
}

resource "null_resource" "forex_asst_prepare" {
  triggers = {
    forex_asst_state = sha256(jsonencode(aws_bedrockagent_agent.forex_asst))
    forex_api_state  = sha256(jsonencode(aws_bedrockagent_agent_action_group.forex_api))
  }
  provisioner "local-exec" {
    command = "aws bedrock-agent prepare-agent --agent-id ${aws_bedrockagent_agent.forex_asst.id}"
  }
  depends_on = [
    aws_bedrockagent_agent.forex_asst,
    aws_bedrockagent_agent_action_group.forex_api
  ]
}
