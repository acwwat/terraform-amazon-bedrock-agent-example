variable "kb_id" {
  description = "The ID of the Bedrock knowledge base to associate with the log delivery"
  type        = string
}

variable "enable_kb_log_delivery_cloudwatch_logs" {
  description = "Whether to deliver logs to CloudWatch Logs"
  type        = bool
  default     = true
}

variable "enable_kb_log_delivery_s3" {
  description = "Whether to deliver logs to S3"
  type        = bool
  default     = false
}

variable "enable_kb_log_delivery_data_firehose" {
  description = "Whether to deliver logs to Data Firehose"
  type        = bool
  default     = false
}
