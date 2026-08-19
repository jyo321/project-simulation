variable "environment" {
  type = string
}

variable "alb_dns_name" {
  type = string
}

variable "origin_verify_secret" {
  description = "Shared secret injected as the ALB's required X-Origin-Verify header (modules/ecs owns the matching listener-rule conditions)."
  type        = string
  sensitive   = true
}
