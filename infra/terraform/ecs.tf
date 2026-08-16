data "aws_caller_identity" "current" {}

resource "aws_ecs_cluster" "main" {
  name = "northbridge-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "service" {
  for_each = toset(local.service_images)

  name              = "/northbridge/${each.key}"
  retention_in_days = 30
}

locals {
  ecr_uri = { for name, repo in aws_ecr_repository.service : name => repo.repository_url }
}

# ---------------------------------------------------------------------------
# Application Load Balancer — the only internet-facing compute entry point.
# CloudFront is the only intended caller (see cloudfront_frontend.tf); a custom-header
# check on the listener rules stops the ALB being hit directly, bypassing the CDN/WAF.
# ---------------------------------------------------------------------------

resource "aws_lb" "main" {
  name               = "northbridge-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = [for s in aws_subnet.public : s.id]
  security_groups    = [aws_security_group.alb.id]
}

# Plain HTTP — deliberately no ACM certificate/domain required. CloudFront (see
# cloudfront_frontend.tf) terminates HTTPS for the public internet with its own free
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
  name        = "northbridge-applications-api"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/health"
  }
}

resource "aws_lb_target_group" "documents_api" {
  name        = "northbridge-documents-api"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/health"
  }
}

resource "aws_lb_target_group" "decisioning_api" {
  name        = "northbridge-decisioning-api"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
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
      values           = [random_password.origin_verify.result]
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
      values           = [random_password.origin_verify.result]
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
      values           = [random_password.origin_verify.result]
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
      values           = [random_password.origin_verify.result]
    }
  }
}

# ---------------------------------------------------------------------------
# Task definitions & services — the three request-serving APIs
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "applications_api" {
  family                   = "northbridge-applications-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.api_task_cpu
  memory                   = var.api_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.applications_api.arn

  container_definitions = jsonencode([{
    name         = "applications-api"
    image        = "${local.ecr_uri["applications-api"]}:${var.container_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080 }]
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:connectionString::" },
    ]
    environment = [
      { name = "Messaging__ApplicationEventsTopicArn", value = aws_sns_topic.application_events.arn },
      { name = "Messaging__CreditScoringQueueUrl", value = aws_sqs_queue.credit_scoring_jobs.id },
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
    subnets          = [for s in aws_subnet.private_app : s.id]
    security_groups  = [aws_security_group.ecs_app.id]
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
}

resource "aws_ecs_task_definition" "documents_api" {
  family                   = "northbridge-documents-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.api_task_cpu
  memory                   = var.api_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.documents_api.arn

  container_definitions = jsonencode([{
    name         = "documents-api"
    image        = "${local.ecr_uri["documents-api"]}:${var.container_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080 }]
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:connectionString::" },
    ]
    environment = [
      { name = "Messaging__DocumentValidationQueueUrl", value = aws_sqs_queue.document_validation.id },
      { name = "Messaging__FraudAnalysisQueueUrl", value = aws_sqs_queue.fraud_analysis_jobs.id },
      { name = "Buckets__RawDocuments", value = aws_s3_bucket.raw_documents.bucket },
      { name = "Buckets__GeneratedDocuments", value = aws_s3_bucket.generated_documents.bucket },
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
    subnets          = [for s in aws_subnet.private_app : s.id]
    security_groups  = [aws_security_group.ecs_app.id]
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
}

resource "aws_ecs_task_definition" "decisioning_api" {
  family                   = "northbridge-decisioning-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.api_task_cpu
  memory                   = var.api_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.decisioning_api.arn

  container_definitions = jsonencode([{
    name         = "decisioning-api"
    image        = "${local.ecr_uri["decisioning-api"]}:${var.container_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080 }]
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:connectionString::" },
    ]
    environment = [
      { name = "Messaging__ApplicationEventsTopicArn", value = aws_sns_topic.application_events.arn },
      { name = "Buckets__GeneratedDocuments", value = aws_s3_bucket.generated_documents.bucket },
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
    subnets          = [for s in aws_subnet.private_app : s.id]
    security_groups  = [aws_security_group.ecs_app.id]
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
}

# ---------------------------------------------------------------------------
# Standing-service background workers — service-triggered (long-poll SQS loops)
# and the Notification Worker. These run as ECS services (min 1 task), not RunTask,
# because they must always be ready to react to the next message.
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "document_validation_worker" {
  family                   = "northbridge-document-validation-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.document_validation_worker.arn

  container_definitions = jsonencode([{
    name      = "document-validation-worker"
    image     = "${local.ecr_uri["document-validation-worker"]}:${var.container_image_tag}"
    essential = true
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:connectionString::" },
    ]
    environment = [
      { name = "Worker__DocumentValidationQueueUrl", value = aws_sqs_queue.document_validation.id },
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
    subnets          = [for s in aws_subnet.private_app : s.id]
    security_groups  = [aws_security_group.ecs_worker.id]
    assign_public_ip = false
  }
}

resource "aws_ecs_task_definition" "status_projector_worker" {
  family                   = "northbridge-status-projector-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.status_projector_worker.arn

  container_definitions = jsonencode([{
    name      = "status-projector-worker"
    image     = "${local.ecr_uri["status-projector-worker"]}:${var.container_image_tag}"
    essential = true
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:connectionString::" },
    ]
    environment = [
      { name = "Worker__StatusProjectorQueueUrl", value = aws_sqs_queue.status_projector.id },
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
    subnets          = [for s in aws_subnet.private_app : s.id]
    security_groups  = [aws_security_group.ecs_worker.id]
    assign_public_ip = false
  }
}

resource "aws_ecs_task_definition" "notification_worker" {
  family                   = "northbridge-notification-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.notification_worker.arn

  container_definitions = jsonencode([{
    name      = "notification-worker"
    image     = "${local.ecr_uri["notification-worker"]}:${var.container_image_tag}"
    essential = true
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:connectionString::" },
    ]
    environment = [
      { name = "Worker__NotificationsQueueUrl", value = aws_sqs_queue.notifications.id },
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
    subnets          = [for s in aws_subnet.private_app : s.id]
    security_groups  = [aws_security_group.ecs_worker.id]
    assign_public_ip = false
  }
}

# ---------------------------------------------------------------------------
# One-shot task definitions — invoked via ecs:RunTask, never as a standing service.
# The scheduled job is triggered by EventBridge Scheduler (messaging.tf); the two
# fire-and-forget jobs are triggered by EventBridge Pipes reading their SQS queue.
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "daily_stale_report_job" {
  family                   = "northbridge-daily-stale-report-job"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.daily_stale_report_job.arn

  container_definitions = jsonencode([{
    name      = "daily-stale-report-job"
    image     = "${local.ecr_uri["daily-stale-report-job"]}:${var.container_image_tag}"
    essential = true
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:connectionString::" },
    ]
    environment = [
      { name = "Job__StaleAfterDays", value = tostring(var.stale_after_days) },
      { name = "Job__ReportsBucket", value = aws_s3_bucket.reports.bucket },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service["daily-stale-report-job"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "credit_scoring_job" {
  family                   = "northbridge-credit-scoring-job"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  # Sized well above the API tier per brief §2.3 note: these jobs run >20 min and need
  # more CPU/memory than a standard API container.
  cpu                = var.fire_and_forget_task_cpu
  memory             = var.fire_and_forget_task_memory
  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.credit_scoring_job.arn

  container_definitions = jsonencode([{
    name      = "credit-scoring-job"
    image     = "${local.ecr_uri["credit-scoring-job"]}:${var.container_image_tag}"
    essential = true
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:connectionString::" },
    ]
    environment = [
      { name = "Messaging__ApplicationEventsTopicArn", value = aws_sns_topic.application_events.arn },
      { name = "Job__GeneratedDocumentsBucket", value = aws_s3_bucket.generated_documents.bucket },
      # JOB_ID / LOAN_APPLICATION_ID are supplied per-invocation by the EventBridge Pipe
      # container override (see messaging.tf) — not set here.
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
  family                   = "northbridge-fraud-forensics-job"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.fire_and_forget_task_cpu
  memory                   = var.fire_and_forget_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.fraud_forensics_job.arn

  container_definitions = jsonencode([{
    name      = "fraud-forensics-job"
    image     = "${local.ecr_uri["fraud-forensics-job"]}:${var.container_image_tag}"
    essential = true
    secrets = [
      { name = "ConnectionStrings__Northbridge", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:connectionString::" },
    ]
    environment = [
      { name = "Messaging__ApplicationEventsTopicArn", value = aws_sns_topic.application_events.arn },
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
