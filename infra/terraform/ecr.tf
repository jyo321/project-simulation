locals {
  service_images = [
    "applications-api",
    "documents-api",
    "decisioning-api",
    "document-validation-worker",
    "status-projector-worker",
    "daily-stale-report-job",
    "credit-scoring-job",
    "fraud-forensics-job",
    "notification-worker",
  ]
}

resource "aws_ecr_repository" "service" {
  for_each = toset(local.service_images)

  name                 = "northbridge/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
