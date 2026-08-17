terraform {
  required_version = ">= 1.10.0" # S3-native state locking (use_lockfile) needs 1.10+

  # Remote state, shared across your machine and CI (GitHub Actions runners are ephemeral —
  # without this, every CI run would start from a blank state and try to recreate
  # everything). Bucket is created once by infra/terraform-bootstrap; workspace_key_prefix
  # means each `terraform workspace` (dev/staging/prod) gets its own state file automatically,
  # at env:/<workspace>/northbridge/terraform.tfstate — no separate config needed per environment.
  # Locking uses S3's own conditional-write support (use_lockfile) — no DynamoDB table needed.
  backend "s3" {
    bucket               = "northbridge-tfstate-REPLACE-WITH-YOUR-ACCOUNT-ID" # from terraform-bootstrap's output
    key                  = "northbridge/terraform.tfstate"
    region               = "us-east-1"
    use_lockfile         = true
    workspace_key_prefix = "env"
    encrypt              = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "northbridge-lending"
      Environment = local.environment
      ManagedBy   = "terraform"
    }
  }
}
