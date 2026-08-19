variable "environment" {
  type = string
}

variable "service_images" {
  description = "Every container-image-backed service in the stack — one ECR repo per entry."
  type        = list(string)
}
