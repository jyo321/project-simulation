variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_cidr" {
  description = "CIDR block for the Northbridge VPC."
  type        = string
}

variable "availability_zones" {
  description = "AZs to spread subnets across (brief calls for a multi-AZ layout)."
  type        = list(string)
}
