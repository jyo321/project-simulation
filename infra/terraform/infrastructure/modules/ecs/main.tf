resource "aws_ecs_cluster" "main" {
  name = "northbridge-cluster-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "service" {
  for_each = toset(var.ecs_service_images)

  name              = "/northbridge/${var.environment}/${each.key}"
  retention_in_days = 30
}

# ---------------------------------------------------------------------------
# Application Load Balancer — the only internet-facing compute entry point.
# CloudFront is the only intended caller (see modules/cloudfront_frontend); a
# custom-header check on the listener rules stops the ALB being hit directly, bypassing
# the CDN/WAF.
# ---------------------------------------------------------------------------

resource "aws_lb" "main" {
  name               = "northbridge-alb-${var.environment}"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.security_group_alb_id]
}

# Plain HTTP — deliberately no ACM certificate/domain required. CloudFront (see
# modules/cloudfront_frontend) terminates HTTPS for the public internet with its own free
# default certificate, then reaches this listener over HTTP inside AWS's network. Every
# listener rule below additionally requires the X-Origin-Verify header CloudFront alone
# knows, so hitting this ALB's public DNS name directly never matches a real route.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      status_code  = "404"
      content_type = "text/plain"
      message_body = "Not found"
    }
  }
}

resource "aws_lb_target_group" "applications_api" {
  # Target group names have a 32-char AWS limit — "nb-" instead of "northbridge-" buys
  # enough room for "-${var.environment}" without truncating.
  name        = "nb-apps-api-${var.environment}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    path = "/health"
  }
}

resource "aws_lb_target_group" "documents_api" {
  name        = "nb-docs-api-${var.environment}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    path = "/health"
  }
}

resource "aws_lb_target_group" "decisioning_api" {
  name        = "nb-deci-api-${var.environment}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    path = "/health"
  }
}

# Most specific rules first: Decisioning.Api owns /api/reviewer-queue and the
# decision sub-resource; everything else under /api/applications* falls through to
# Applications.Api.
resource "aws_lb_listener_rule" "decisioning_reviewer_queue" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.decisioning_api.arn
  }

  condition {
    path_pattern {
      values = ["/api/reviewer-queue*"]
    }
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_verify_secret]
    }
  }
}

resource "aws_lb_listener_rule" "decisioning_decision" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 11

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.decisioning_api.arn
  }

  condition {
    path_pattern {
      values = ["/api/applications/*/decision"]
    }
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_verify_secret]
    }
  }
}

resource "aws_lb_listener_rule" "documents_api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.documents_api.arn
  }

  condition {
    path_pattern {
      values = ["/api/documents*"]
    }
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_verify_secret]
    }
  }
}

resource "aws_lb_listener_rule" "applications_api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.applications_api.arn
  }

  condition {
    path_pattern {
      values = ["/api/applicants*", "/api/applications*"]
    }
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_verify_secret]
    }
  }
}

# ---------------------------------------------------------------------------
# Task definitions & services — the three request-serving APIs
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "applications_api" {
  family                   = "northbridge-applications-api-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.api_task_cpu
  memory                   = var.api_task_memory
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.applications_api_role_arn

  container_definitions = jsonencode([{
    name         = "applications-api"
    image        = "${var.ecr_repository_urls["applications-api"]}:${var.container_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080 }]
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${var.db_credentials_secret_arn}:connectionString::" },
    ]
    environment = [
      { name = "Messaging__ApplicationEventsTopicArn", value = var.application_events_topic_arn },
      { name = "Messaging__CreditScoringQueueUrl", value = var.credit_scoring_jobs_queue_url },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service["applications-api"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "applications_api" {
  name            = "applications-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.applications_api.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.security_group_ecs_app_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.applications_api.arn
    container_name   = "applications-api"
    container_port   = 8080
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener_rule.applications_api]

  # api-ci-cd.yml deploys by registering a new task-def revision and updating the
  # service directly (aws-actions/amazon-ecs-deploy-task-definition) — out-of-band
  # from Terraform. Without this, the next `terraform apply` would see that drift
  # and roll the service back to the revision Terraform itself created.
  lifecycle {
    ignore_changes = [task_definition]
  }
}

resource "aws_ecs_task_definition" "documents_api" {
  family                   = "northbridge-documents-api-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.api_task_cpu
  memory                   = var.api_task_memory
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.documents_api_role_arn

  container_definitions = jsonencode([{
    name         = "documents-api"
    image        = "${var.ecr_repository_urls["documents-api"]}:${var.container_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080 }]
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${var.db_credentials_secret_arn}:connectionString::" },
    ]
    environment = [
      { name = "Messaging__DocumentValidationQueueUrl", value = var.document_validation_queue_url },
      { name = "Messaging__FraudAnalysisQueueUrl", value = var.fraud_analysis_jobs_queue_url },
      { name = "Buckets__RawDocuments", value = var.raw_documents_bucket_name },
      { name = "Buckets__GeneratedDocuments", value = var.generated_documents_bucket_name },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service["documents-api"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "documents_api" {
  name            = "documents-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.documents_api.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.security_group_ecs_app_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.documents_api.arn
    container_name   = "documents-api"
    container_port   = 8080
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener_rule.documents_api]

  lifecycle {
    ignore_changes = [task_definition] # see applications_api's service for why
  }
}

resource "aws_ecs_task_definition" "decisioning_api" {
  family                   = "northbridge-decisioning-api-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.api_task_cpu
  memory                   = var.api_task_memory
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.decisioning_api_role_arn

  container_definitions = jsonencode([{
    name         = "decisioning-api"
    image        = "${var.ecr_repository_urls["decisioning-api"]}:${var.container_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080 }]
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${var.db_credentials_secret_arn}:connectionString::" },
    ]
    environment = [
      { name = "Messaging__ApplicationEventsTopicArn", value = var.application_events_topic_arn },
      { name = "Buckets__GeneratedDocuments", value = var.generated_documents_bucket_name },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service["decisioning-api"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "decisioning_api" {
  name            = "decisioning-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.decisioning_api.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.security_group_ecs_app_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.decisioning_api.arn
    container_name   = "decisioning-api"
    container_port   = 8080
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener_rule.decisioning_reviewer_queue, aws_lb_listener_rule.decisioning_decision]

  lifecycle {
    ignore_changes = [task_definition] # see applications_api's service for why
  }
}

# ---------------------------------------------------------------------------
# Standing-service background workers — service-triggered (long-poll SQS loops)
# and the Notification Worker. These run as ECS services (min 1 task), not RunTask,
# because they must always be ready to react to the next message.
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "document_validation_worker" {
  family                   = "northbridge-document-validation-worker-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.document_validation_worker_role_arn

  container_definitions = jsonencode([{
    name      = "document-validation-worker"
    image     = "${var.ecr_repository_urls["document-validation-worker"]}:${var.container_image_tag}"
    essential = true
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${var.db_credentials_secret_arn}:connectionString::" },
    ]
    environment = [
      { name = "Worker__DocumentValidationQueueUrl", value = var.document_validation_queue_url },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service["document-validation-worker"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "document_validation_worker" {
  name            = "document-validation-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.document_validation_worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.security_group_ecs_worker_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [task_definition] # see applications_api's service for why
  }
}

resource "aws_ecs_task_definition" "status_projector_worker" {
  family                   = "northbridge-status-projector-worker-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.status_projector_worker_role_arn

  container_definitions = jsonencode([{
    name      = "status-projector-worker"
    image     = "${var.ecr_repository_urls["status-projector-worker"]}:${var.container_image_tag}"
    essential = true
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${var.db_credentials_secret_arn}:connectionString::" },
    ]
    environment = [
      { name = "Worker__StatusProjectorQueueUrl", value = var.status_projector_queue_url },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service["status-projector-worker"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "status_projector_worker" {
  name            = "status-projector-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.status_projector_worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.security_group_ecs_worker_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [task_definition] # see applications_api's service for why
  }
}

resource "aws_ecs_task_definition" "notification_worker" {
  family                   = "northbridge-notification-worker-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.notification_worker_role_arn

  container_definitions = jsonencode([{
    name      = "notification-worker"
    image     = "${var.ecr_repository_urls["notification-worker"]}:${var.container_image_tag}"
    essential = true
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${var.db_credentials_secret_arn}:connectionString::" },
    ]
    environment = [
      { name = "Worker__NotificationsQueueUrl", value = var.notifications_queue_url },
      { name = "Worker__SenderEmail", value = var.notification_sender_email },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service["notification-worker"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "notification_worker" {
  name            = "notification-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.notification_worker.arn
  desired_count   = 2 # availability for the notification service, per brief
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.security_group_ecs_worker_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [task_definition] # see applications_api's service for why
  }
}

# ---------------------------------------------------------------------------
# One-shot task definitions — invoked via ecs:RunTask, never as a standing service.
# The two fire-and-forget jobs are triggered by EventBridge Pipes (modules/messaging)
# reading their SQS queue. The scheduled daily report job runs as Lambda instead
# (modules/lambda) — see the comment there for why.
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "credit_scoring_job" {
  family                   = "northbridge-credit-scoring-job-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  # Sized well above the API tier per brief §2.3 note: these jobs run >20 min and need
  # more CPU/memory than a standard API container.
  cpu                = var.fire_and_forget_task_cpu
  memory             = var.fire_and_forget_task_memory
  execution_role_arn = var.ecs_task_execution_role_arn
  task_role_arn      = var.credit_scoring_job_role_arn

  container_definitions = jsonencode([{
    name      = "credit-scoring-job"
    image     = "${var.ecr_repository_urls["credit-scoring-job"]}:${var.container_image_tag}"
    essential = true
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${var.db_credentials_secret_arn}:connectionString::" },
    ]
    environment = [
      { name = "Messaging__ApplicationEventsTopicArn", value = var.application_events_topic_arn },
      { name = "Job__GeneratedDocumentsBucket", value = var.generated_documents_bucket_name },
      # JOB_ID / LOAN_APPLICATION_ID are supplied per-invocation by the EventBridge Pipe
      # container override (modules/messaging) — not set here.
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service["credit-scoring-job"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "fraud_forensics_job" {
  family                   = "northbridge-fraud-forensics-job-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.fire_and_forget_task_cpu
  memory                   = var.fire_and_forget_task_memory
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.fraud_forensics_job_role_arn

  container_definitions = jsonencode([{
    name      = "fraud-forensics-job"
    image     = "${var.ecr_repository_urls["fraud-forensics-job"]}:${var.container_image_tag}"
    essential = true
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${var.db_credentials_secret_arn}:connectionString::" },
    ]
    environment = [
      { name = "Messaging__ApplicationEventsTopicArn", value = var.application_events_topic_arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service["fraud-forensics-job"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}
