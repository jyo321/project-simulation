# Bootstrap: creates the S3 bucket + DynamoDB table that infra/terraform's own state lives
# in. Deliberately a SEPARATE Terraform config with its OWN local state — you can't store
# Terraform's state in a bucket that the same apply is still creating, so this one small
# piece stays local-state and gets applied once, by hand, before anything else.
#
# Usage (one time, ever, per AWS account):
#   cd infra/terraform-bootstrap
#   terraform init
#   terraform apply -var="state_bucket_name=northbridge-tfstate-<your-account-id>"
# Then put that same bucket name into infra/terraform/providers.tf's backend block.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name (S3 bucket names are unique across ALL of AWS, not just your account) — e.g. \"northbridge-tfstate-123456789012\" using your account ID."
  type        = string
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled" # lets you recover a previous state version if something corrupts it
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# State locking: without this, two people (or a person and a CI run) applying at the same
# moment can corrupt the state file. Terraform automatically acquires/releases a lock row
# here around every plan/apply.
resource "aws_dynamodb_table" "locks" {
  name         = "northbridge-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.state.bucket
}

output "lock_table_name" {
  value = aws_dynamodb_table.locks.name
}
