# The active Terraform workspace IS the environment — `terraform workspace select prod`
# (or `terraform workspace new prod` the first time) is what picks it. There's no separate
# -var to keep in sync with your workspace; every environment-scoped resource name below
# derives from local.environment, so switching workspaces is the entire act of switching
# environments.
#
# Never apply real resources from the "default" workspace (the one that exists before you
# create any named one) — always create dev/staging/prod explicitly first, since
# "default" makes a confusing environment label to find in the AWS console later.
locals {
  environment = terraform.workspace

  # Every container-image-backed service in the stack — one ECR repo per entry
  # (modules/ecr). Kept here, not inside modules/ecr, so modules/ecs and modules/lambda
  # can each derive the subset of names they actually care about from the same source.
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

  # Same list minus daily-stale-report-job, which runs as Lambda (modules/lambda) rather
  # than an ECS task/service — modules/ecs only needs log groups/ECR lookups for the rest.
  ecs_service_images = [for s in local.service_images : s if s != "daily-stale-report-job"]
}
