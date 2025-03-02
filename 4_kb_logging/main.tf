# Use data sources to get common information about the environment
data "aws_caller_identity" "this" {}
data "aws_partition" "this" {}
data "aws_region" "this" {}

locals {
  account_id            = data.aws_caller_identity.this.account_id
  partition             = data.aws_partition.this.partition
  region                = data.aws_region.this.name
  region_name_tokenized = split("-", local.region)
  region_short          = "${substr(local.region_name_tokenized[0], 0, 2)}${substr(local.region_name_tokenized[1], 0, 1)}${local.region_name_tokenized[2]}"
}

resource "aws_cloudwatch_log_delivery_source" "kb_logs" {
  count        = var.enable_kb_log_delivery_cloudwatch_logs || var.enable_kb_log_delivery_s3 || var.enable_kb_log_delivery_data_firehose ? 1 : 0
  name         = "bedrock-kb-${var.kb_id}"
  log_type     = "APPLICATION_LOGS"
  resource_arn = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:knowledge-base/${var.kb_id}"
}

# Log delivery to CloudWatch Logs

resource "aws_cloudwatch_log_group" "kb_logs" {
  count = var.enable_kb_log_delivery_cloudwatch_logs ? 1 : 0
  name  = "/aws/vendedlogs/bedrock/knowledge-base/APPLICATION_LOGS/${var.kb_id}"
}

resource "aws_cloudwatch_log_resource_policy" "kb_logs" {
  count       = var.enable_kb_log_delivery_cloudwatch_logs ? 1 : 0
  policy_name = "bedrock-kb-${var.kb_id}-policy"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite20150319"
        Effect = "Allow"
        Principal = {
          Service = ["delivery.logs.amazonaws.com"]
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["${aws_cloudwatch_log_group.kb_logs[0].arn}:log-stream:*"]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = ["${local.account_id}"]
          },
          ArnLike = {
            "aws:SourceArn" = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:*"]
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_delivery_destination" "kb_logs_cloudwatch_logs" {
  count = var.enable_kb_log_delivery_cloudwatch_logs ? 1 : 0
  name  = "bedrock-kb-${var.kb_id}-cloudwatch-logs"
  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.kb_logs[0].arn
  }
  depends_on = [aws_cloudwatch_log_resource_policy.kb_logs]
}

resource "aws_cloudwatch_log_delivery" "kb_logs_cloudwatch_logs" {
  count                    = var.enable_kb_log_delivery_cloudwatch_logs ? 1 : 0
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.kb_logs_cloudwatch_logs[0].arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.kb_logs[0].name
}

# Log delivery to S3

resource "aws_s3_bucket" "kb_logs_s3" {
  count         = var.enable_kb_log_delivery_s3 ? 1 : 0
  bucket        = "bedrock-kb-logs-${lower(var.kb_id)}-${local.region_short}-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "kb_logs_s3" {
  count  = var.enable_kb_log_delivery_s3 ? 1 : 0
  bucket = aws_s3_bucket.kb_logs_s3[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "AWSLogDeliveryWrite20150319"
    "Statement" : [
      {
        Sid    = "AWSLogDeliveryWrite171157658"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.kb_logs_s3[0].arn}/AWSLogs/${local.account_id}/bedrock/knowledgebases/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = "${local.account_id}"
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
          ArnLike = {
            "aws:SourceArn" = "${aws_cloudwatch_log_delivery_source.kb_logs[0].arn}"
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_delivery_destination" "kb_logs_s3" {
  count = var.enable_kb_log_delivery_s3 ? 1 : 0
  name  = "bedrock-kb-${var.kb_id}-s3"
  delivery_destination_configuration {
    destination_resource_arn = aws_s3_bucket.kb_logs_s3[0].arn
  }
  depends_on = [aws_s3_bucket_policy.kb_logs_s3[0]]
}

resource "aws_cloudwatch_log_delivery" "kb_logs_s3" {
  count                    = var.enable_kb_log_delivery_s3 ? 1 : 0
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.kb_logs_s3[0].arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.kb_logs[0].name
  depends_on               = [aws_cloudwatch_log_delivery.kb_logs_cloudwatch_logs]
}

# Log delivery to Data Firehose

resource "aws_s3_bucket" "kb_logs_data_firehose" {
  count         = var.enable_kb_log_delivery_data_firehose ? 1 : 0
  bucket        = "bedrock-kb-logs-data-firehose-${lower(var.kb_id)}-${local.region_short}-${local.account_id}"
  force_destroy = true
}

resource "aws_iam_role" "kb_logs_data_firehose" {
  count = var.enable_kb_log_delivery_data_firehose ? 1 : 0
  name  = "S3RoleForDataFirehose-bedrock-kb-logs-${var.kb_id}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "${local.account_id}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "kb_logs_data_firehose" {
  count = var.enable_kb_log_delivery_data_firehose ? 1 : 0
  name  = "S3PolicyForDataFirehose-bedrock-kb-logs-${var.kb_id}"
  role  = aws_iam_role.kb_logs_data_firehose[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.kb_logs_data_firehose[0].arn,
          "${aws_s3_bucket.kb_logs_data_firehose[0].arn}/*"
        ]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "kb_logs" {
  count       = var.enable_kb_log_delivery_data_firehose ? 1 : 0
  name        = "bedrock-kb-logs-${var.kb_id}"
  destination = "extended_s3"
  extended_s3_configuration {
    role_arn   = aws_iam_role.kb_logs_data_firehose[0].arn
    bucket_arn = aws_s3_bucket.kb_logs_data_firehose[0].arn
  }
  tags = {
    "LogDeliveryEnabled" = "true"
  }
  depends_on = [aws_iam_role_policy.kb_logs_data_firehose]
}

resource "aws_cloudwatch_log_delivery_destination" "kb_logs_data_firehose" {
  count = var.enable_kb_log_delivery_data_firehose ? 1 : 0
  name  = "bedrock-kb-${var.kb_id}-data-firehose"
  delivery_destination_configuration {
    destination_resource_arn = aws_kinesis_firehose_delivery_stream.kb_logs[0].arn
  }
}

resource "aws_cloudwatch_log_delivery" "kb_logs_data_firehose" {
  count                    = var.enable_kb_log_delivery_data_firehose ? 1 : 0
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.kb_logs_data_firehose[0].arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.kb_logs[0].name
  depends_on               = [aws_cloudwatch_log_delivery.kb_logs_s3]
}
