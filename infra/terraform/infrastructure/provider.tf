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
