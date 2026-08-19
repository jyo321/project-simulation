# Daily Stale-Application Report (brief §2.3.2, time-based trigger) — previously an
# ECS RunTask fired by EventBridge Scheduler. A once-a-day, short-lived, low-resource
# job doesn't need a standing Fargate task definition; Lambda bills only for the
# seconds it actually runs and needs no cluster/service to manage. Packaged as a
# container image (workers/DailyStaleReportJob/Dockerfile) rather than a zip so it
# reuses the same ECR-push CI flow as every other service in this stack.
#
# Deployed inside the private app subnets so it can reach RDS directly, same as the
# ECS workers did — this is why it shares their security group (sg-ecs-worker), which
# is already allowed into Postgres, and why the S3 gateway endpoint on that subnet's
# route table (modules/network) is enough for the S3 report upload with no NAT/internet
# egress needed. The EventBridge Scheduler invokes it via modules/iam's
# scheduler_run_task role — the same customer-managed-role invocation model it already
# used for ecs:RunTask, so no Lambda resource-based permission is required.
#
# IMPORTANT — unlike every ECS task definition in this stack, Lambda validates at
# CreateFunction time that image_uri already exists in ECR; an empty repo (the normal
# state on a brand-new environment's first apply) makes this resource fail immediately.
# Before the first `terraform apply` in a new workspace, create just the ECR repos and
# seed this one with a real image — see README's "Deploying to AWS" for the full command
# sequence (terraform apply -target=module.ecr, docker build/push, then the normal
# terraform apply).
resource "aws_cloudwatch_log_group" "daily_stale_report" {
  name              = "/northbridge/${var.environment}/daily-stale-report-job"
  retention_in_days = 30
}

resource "aws_lambda_function" "daily_stale_report" {
  function_name = "northbridge-daily-stale-report-${var.environment}"
  role          = aws_iam_role.daily_stale_report_lambda.arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:${var.container_image_tag}"
  timeout       = 300
  memory_size   = 512

  vpc_config {
    subnet_ids         = var.private_app_subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      DbSecretArn         = var.db_credentials_secret_arn
      Job__StaleAfterDays = tostring(var.stale_after_days)
      Job__ReportsBucket  = var.reports_bucket_name
      AWS__Region         = var.aws_region
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.daily_stale_report.name
  }

  # workers-ci-cd.yml deploys by calling `aws lambda update-function-code` directly —
  # out-of-band from Terraform, same reasoning as the ECS services' ignore_changes.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "daily_stale_report_lambda" {
  name               = "northbridge-daily-stale-report-lambda-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Grants the ENI create/attach/delete permissions any VPC-attached Lambda needs, plus
# baseline CloudWatch Logs write access — the Lambda equivalent of ecs_task_execution.
resource "aws_iam_role_policy_attachment" "daily_stale_report_lambda_vpc" {
  role       = aws_iam_role.daily_stale_report_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "daily_stale_report_lambda" {
  role = aws_iam_role.daily_stale_report_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = ["${var.reports_bucket_arn}/*"] },
      # ECS could inject the DB connection string via the task definition's `secrets`
      # block; Lambda has no equivalent, so the function fetches it itself at cold
      # start (see Function.cs) — hence the explicit GetSecretValue grant here.
      { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [var.db_credentials_secret_arn] },
    ]
  })
}
