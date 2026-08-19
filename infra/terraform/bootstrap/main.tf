# One-time, once-ever-per-AWS-account: creates the S3 bucket that ../infrastructure stores
# its Terraform state in. Deliberately its own standalone Terraform project, not a resource
# gated behind a variable inside ../infrastructure — an apply can't store its own state in a
# bucket that same apply is creating, and this way ../infrastructure's backend "s3" block never
# has to be commented out/back in to break that chicken-and-egg problem. This project's own
# state stays local (there's nothing to bootstrap it into) and is never touched again after
# the bucket exists.
#
# Run once, ever, per AWS account:
#   cd infra/terraform/bootstrap
#   terraform init
#   terraform apply -var="state_bucket_name=northbridge-tfstate-<your-account-id>"
#
# Then put that same bucket name into ../infrastructure/backend.tf's backend "s3" block
# (replacing REPLACE-WITH-YOUR-ACCOUNT-ID) and run `terraform init` there.

terraform {
  required_version = ">= 1.10.0"

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

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled" # lets you recover a previous state version if something corrupts it
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
