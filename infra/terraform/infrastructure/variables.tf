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

variable "db_multi_az" {
  description = "Whether RDS runs Multi-AZ. Defaults true (prod-grade); dev/staging override to false to cut cost on disposable environments."
  type        = bool
  default     = true
}

variable "db_deletion_protection" {
  description = "Whether RDS blocks `terraform destroy`/console deletion. Defaults true; dev/staging override to false since the README's `terraform destroy` teardown step would otherwise fail on the RDS instance."
  type        = bool
  default     = true
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

# ---------------------------------------------------------------------------
# modules/github_oidc — account-wide, not per-environment. See that module's main.tf
# header comment for why create_shared_resources must stay false in every workspace but
# one.
# ---------------------------------------------------------------------------

variable "create_shared_resources" {
  description = "Create the account-wide GitHub OIDC provider + deploy roles. Set true in exactly one workspace, ever — see modules/github_oidc's header comment."
  type        = bool
  default     = false
}

variable "github_repo" {
  description = "GitHub repo these OIDC roles trust, as \"owner/repo\" — e.g. \"jyo321/project-simulation\"."
  type        = string
}

variable "github_oidc_provider_exists" {
  description = "Set true if your AWS account already has a GitHub Actions OIDC provider (only one can exist per account) — Terraform will reuse it instead of creating a duplicate."
  type        = bool
  default     = false
}
