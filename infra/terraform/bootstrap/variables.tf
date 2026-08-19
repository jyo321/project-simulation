variable "aws_region" {
  description = "AWS region for the state bucket. Should match ../infrastructure/backend.tf's backend region."
  type        = string
  default     = "us-east-2"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform state — e.g. \"northbridge-tfstate-123456789012\" using your account ID. Must match ../infrastructure/backend.tf's backend \"s3\" block."
  type        = string
}
