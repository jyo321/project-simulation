variable "aws_region" {
  description = "AWS region for the deployment."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the Northbridge VPC."
  type        = string
}

variable "availability_zones" {
  description = "AZs to spread subnets across (brief calls for a multi-AZ layout)."
  type        = list(string)
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  description = "Master password for RDS. In practice supplied via TF_VAR_db_password or a CI secret, never committed."
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  type = string
}

variable "api_task_cpu" {
  description = "CPU units for the three request-serving API tasks."
  type        = number
}

variable "api_task_memory" {
  description = "Memory (MiB) for the three request-serving API tasks."
  type        = number
}

variable "fire_and_forget_task_cpu" {
  description = "CPU units for the >20 min fire-and-forget job tasks (brief requires more than API-tier resources)."
  type        = number
}

variable "fire_and_forget_task_memory" {
  description = "Memory (MiB) for the >20 min fire-and-forget job tasks."
  type        = number
}

variable "notification_sender_email" {
  description = "SES-verified sender address for the Notification Worker."
  type        = string
}

variable "stale_after_days" {
  description = "Applications older than this many days without a decision are flagged by the daily report job."
  type        = number
}

variable "container_image_tag" {
  description = "Image tag deployed for every service — set by the CI/CD pipeline per release."
  type        = string
}
