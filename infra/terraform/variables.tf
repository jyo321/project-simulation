variable "aws_region" {
  description = "AWS region for the deployment."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the Northbridge VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets across (brief calls for a multi-AZ layout)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "db_name" {
  type    = string
  default = "northbridge"
}

variable "db_username" {
  type      = string
  default   = "northbridge_app"
  sensitive = true
}

variable "db_password" {
  description = "Master password for RDS. In practice supplied via TF_VAR_db_password or a CI secret, never committed."
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "api_task_cpu" {
  description = "CPU units for the three request-serving API tasks."
  type        = number
  default     = 512
}

variable "api_task_memory" {
  description = "Memory (MiB) for the three request-serving API tasks."
  type        = number
  default     = 1024
}

variable "fire_and_forget_task_cpu" {
  description = "CPU units for the >20 min fire-and-forget job tasks (brief requires more than API-tier resources)."
  type        = number
  default     = 4096
}

variable "fire_and_forget_task_memory" {
  description = "Memory (MiB) for the >20 min fire-and-forget job tasks."
  type        = number
  default     = 16384
}

variable "notification_sender_email" {
  description = "SES-verified sender address for the Notification Worker."
  type        = string
  default     = "notifications@northbridgelending.com"
}

variable "stale_after_days" {
  description = "Applications older than this many days without a decision are flagged by the daily report job."
  type        = number
  default     = 5
}

variable "container_image_tag" {
  description = "Image tag deployed for every service — set by the CI/CD pipeline per release."
  type        = string
  default     = "latest"
}
