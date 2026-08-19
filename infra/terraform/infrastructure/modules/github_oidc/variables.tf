variable "create_shared_resources" {
  description = "Create the account-wide GitHub OIDC provider + deploy roles. Set true in exactly one workspace, ever — see main.tf's header comment."
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
