variable "start_kb_ingestion_jobs_config_json" {
  description = "The configuration JSON for the start-kb-ingestion-jobs Lambda function."
  type        = any
  default     = []
}

variable "start_kb_ingestion_jobs_schedule" {
  description = "The schedule expression for the start-kb-ingestion-jobs CloudWatch Event Rule."
  type        = string
  default     = "cron(0 0 * * ? *)"
}

variable "check_kb_ingestion_job_statuses_schedule" {
  description = "The schedule expression for the check-kb-ingestion-job-statuses CloudWatch Event Rule."
  type        = string
  default     = "cron(*/5 * * * ? *)"
}
