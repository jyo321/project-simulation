variable "environment" {
  type = string
}

variable "db_credentials_secret_arn" {
  type = string
}

variable "application_events_topic_arn" {
  type = string
}

variable "credit_scoring_jobs_queue_arn" {
  type = string
}

variable "document_validation_queue_arn" {
  type = string
}

variable "fraud_analysis_jobs_queue_arn" {
  type = string
}

variable "status_projector_queue_arn" {
  type = string
}

variable "notifications_queue_arn" {
  type = string
}

variable "raw_documents_bucket_arn" {
  type = string
}

variable "raw_documents_kms_key_arn" {
  type = string
}

variable "generated_documents_bucket_arn" {
  type = string
}

variable "daily_stale_report_lambda_arn" {
  type = string
}
