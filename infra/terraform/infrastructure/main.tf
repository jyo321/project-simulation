# Root module: wires together every modules/* building block for one environment
# (= one Terraform workspace, see locals.tf). Module boundaries mostly follow the
# original flat-file layout (network, s3_documents, rds, secrets, ecr, lambda, iam,
# messaging, ecs, cloudfront_frontend, github_oidc) — see each module's own main.tf
# header comment for what it owns and why.
#
# modules.ecs and modules.messaging reference each other's outputs (ECS's task
# definitions need messaging's queue/topic ARNs; messaging's EventBridge Pipes need
# ECS's task definition ARNs). That's not a cycle: Terraform's dependency graph is
# per-resource, not per-module, and the specific resources involved on each side don't
# loop back on each other. See modules/messaging/variables.tf for the detail.

# Shared secret CloudFront injects as X-Origin-Verify — generated once here (not inside
# modules/ecs or modules/cloudfront_frontend) because both of those modules need the
# same value: the ALB listener rules check it, and the CloudFront origin sends it.
resource "random_password" "origin_verify" {
  length  = 32
  special = false
}

module "network" {
  source = "./modules/network"

  environment        = local.environment
  aws_region         = var.aws_region
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "s3_documents" {
  source = "./modules/s3_documents"

  environment = local.environment
}

module "rds" {
  source = "./modules/rds"

  environment             = local.environment
  db_name                 = var.db_name
  db_username             = var.db_username
  db_password             = var.db_password
  db_instance_class       = var.db_instance_class
  db_multi_az             = var.db_multi_az
  db_deletion_protection  = var.db_deletion_protection
  private_data_subnet_ids = module.network.private_data_subnet_ids
  security_group_id       = module.network.security_group_rds_id
}

module "secrets" {
  source = "./modules/secrets"

  environment = local.environment
  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password
  db_address  = module.rds.address
}

module "ecr" {
  source = "./modules/ecr"

  environment    = local.environment
  service_images = local.service_images
}

module "lambda" {
  source = "./modules/lambda"

  environment               = local.environment
  aws_region                = var.aws_region
  ecr_repository_url        = module.ecr.repository_urls["daily-stale-report-job"]
  container_image_tag       = var.container_image_tag
  private_app_subnet_ids    = module.network.private_app_subnet_ids
  security_group_id         = module.network.security_group_ecs_worker_id
  db_credentials_secret_arn = module.secrets.db_credentials_secret_arn
  stale_after_days          = var.stale_after_days
  reports_bucket_name       = module.s3_documents.reports_bucket_name
  reports_bucket_arn        = module.s3_documents.reports_bucket_arn
}

module "iam" {
  source = "./modules/iam"

  environment                    = local.environment
  db_credentials_secret_arn      = module.secrets.db_credentials_secret_arn
  application_events_topic_arn   = module.messaging.application_events_topic_arn
  credit_scoring_jobs_queue_arn  = module.messaging.credit_scoring_jobs_queue_arn
  document_validation_queue_arn  = module.messaging.document_validation_queue_arn
  fraud_analysis_jobs_queue_arn  = module.messaging.fraud_analysis_jobs_queue_arn
  status_projector_queue_arn     = module.messaging.status_projector_queue_arn
  notifications_queue_arn        = module.messaging.notifications_queue_arn
  raw_documents_bucket_arn       = module.s3_documents.raw_documents_bucket_arn
  raw_documents_kms_key_arn      = module.s3_documents.raw_documents_kms_key_arn
  generated_documents_bucket_arn = module.s3_documents.generated_documents_bucket_arn
  daily_stale_report_lambda_arn  = module.lambda.function_arn
}

module "messaging" {
  source = "./modules/messaging"

  environment = local.environment

  # Only consumed by this module's EventBridge Scheduler/Pipes resources — see this
  # module's variables.tf for why that's not a dependency cycle with modules.ecs/iam.
  ecs_cluster_arn                         = module.ecs.cluster_arn
  credit_scoring_job_task_definition_arn  = module.ecs.credit_scoring_job_task_definition_arn
  fraud_forensics_job_task_definition_arn = module.ecs.fraud_forensics_job_task_definition_arn
  private_app_subnet_ids                  = module.network.private_app_subnet_ids
  ecs_worker_security_group_id            = module.network.security_group_ecs_worker_id
  pipes_run_task_role_arn                 = module.iam.pipes_run_task_role_arn
  scheduler_run_task_role_arn             = module.iam.scheduler_run_task_role_arn
  daily_stale_report_lambda_arn           = module.lambda.function_arn
}

module "ecs" {
  source = "./modules/ecs"

  environment                     = local.environment
  aws_region                      = var.aws_region
  vpc_id                          = module.network.vpc_id
  public_subnet_ids               = module.network.public_subnet_ids
  private_app_subnet_ids          = module.network.private_app_subnet_ids
  security_group_alb_id           = module.network.security_group_alb_id
  security_group_ecs_app_id       = module.network.security_group_ecs_app_id
  security_group_ecs_worker_id    = module.network.security_group_ecs_worker_id
  api_task_cpu                    = var.api_task_cpu
  api_task_memory                 = var.api_task_memory
  fire_and_forget_task_cpu        = var.fire_and_forget_task_cpu
  fire_and_forget_task_memory     = var.fire_and_forget_task_memory
  container_image_tag             = var.container_image_tag
  ecr_repository_urls             = module.ecr.repository_urls
  ecs_service_images              = local.ecs_service_images
  notification_sender_email       = var.notification_sender_email
  origin_verify_secret            = random_password.origin_verify.result
  db_credentials_secret_arn       = module.secrets.db_credentials_secret_arn
  application_events_topic_arn    = module.messaging.application_events_topic_arn
  credit_scoring_jobs_queue_url   = module.messaging.credit_scoring_jobs_queue_id
  document_validation_queue_url   = module.messaging.document_validation_queue_id
  fraud_analysis_jobs_queue_url   = module.messaging.fraud_analysis_jobs_queue_id
  status_projector_queue_url      = module.messaging.status_projector_queue_id
  notifications_queue_url         = module.messaging.notifications_queue_id
  raw_documents_bucket_name       = module.s3_documents.raw_documents_bucket_name
  generated_documents_bucket_name = module.s3_documents.generated_documents_bucket_name

  ecs_task_execution_role_arn         = module.iam.ecs_task_execution_role_arn
  applications_api_role_arn           = module.iam.applications_api_role_arn
  documents_api_role_arn              = module.iam.documents_api_role_arn
  decisioning_api_role_arn            = module.iam.decisioning_api_role_arn
  document_validation_worker_role_arn = module.iam.document_validation_worker_role_arn
  status_projector_worker_role_arn    = module.iam.status_projector_worker_role_arn
  credit_scoring_job_role_arn         = module.iam.credit_scoring_job_role_arn
  fraud_forensics_job_role_arn        = module.iam.fraud_forensics_job_role_arn
  notification_worker_role_arn        = module.iam.notification_worker_role_arn
}

module "cloudfront_frontend" {
  source = "./modules/cloudfront_frontend"

  environment          = local.environment
  alb_dns_name         = module.ecs.alb_dns_name
  origin_verify_secret = random_password.origin_verify.result
}

module "github_oidc" {
  source = "./modules/github_oidc"

  create_shared_resources     = var.create_shared_resources
  github_repo                 = var.github_repo
  github_oidc_provider_exists = var.github_oidc_provider_exists
}
