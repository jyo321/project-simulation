variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "ecr_repository_url" {
  description = "Repository URL for the daily-stale-report-job image (modules/ecr)."
  type        = string
}

variable "container_image_tag" {
  type = string
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  description = "Security group the function's ENIs run in — shares the ECS workers' sg-ecs-worker (already allowed into Postgres)."
  type        = string
}

variable "db_credentials_secret_arn" {
  type = string
}

variable "stale_after_days" {
  type = number
}

variable "reports_bucket_name" {
  type = string
}

variable "reports_bucket_arn" {
  type = string
}
