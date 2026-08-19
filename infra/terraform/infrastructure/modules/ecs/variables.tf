variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "security_group_alb_id" {
  type = string
}

variable "security_group_ecs_app_id" {
  type = string
}

variable "security_group_ecs_worker_id" {
  type = string
}

variable "api_task_cpu" {
  type = number
}

variable "api_task_memory" {
  type = number
}

variable "fire_and_forget_task_cpu" {
  type = number
}

variable "fire_and_forget_task_memory" {
  type = number
}

variable "container_image_tag" {
  type = string
}

variable "ecr_repository_urls" {
  description = "Repository URL per service name (modules/ecr's output)."
  type        = map(string)
}

variable "ecs_service_images" {
  description = "Service names that run as ECS task defs/services in this module (everything except daily-stale-report-job, which runs as Lambda)."
  type        = list(string)
}

variable "notification_sender_email" {
  type = string
}

variable "origin_verify_secret" {
  description = "Shared secret CloudFront injects as X-Origin-Verify — proves a request reached the ALB via CloudFront, not directly."
  type        = string
  sensitive   = true
}

variable "db_credentials_secret_arn" {
  type = string
}

variable "application_events_topic_arn" {
  type = string
}

variable "credit_scoring_jobs_queue_url" {
  type = string
}

variable "document_validation_queue_url" {
  type = string
}

variable "fraud_analysis_jobs_queue_url" {
  type = string
}

variable "status_projector_queue_url" {
  type = string
}

variable "notifications_queue_url" {
  type = string
}

variable "raw_documents_bucket_name" {
  type = string
}

variable "generated_documents_bucket_name" {
  type = string
}

variable "ecs_task_execution_role_arn" {
  type = string
}

variable "applications_api_role_arn" {
  type = string
}

variable "documents_api_role_arn" {
  type = string
}

variable "decisioning_api_role_arn" {
  type = string
}

variable "document_validation_worker_role_arn" {
  type = string
}

variable "status_projector_worker_role_arn" {
  type = string
}

variable "credit_scoring_job_role_arn" {
  type = string
}

variable "fraud_forensics_job_role_arn" {
  type = string
}

variable "notification_worker_role_arn" {
  type = string
}
