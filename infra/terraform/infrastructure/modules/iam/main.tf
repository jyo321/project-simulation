# Least-privilege IAM per docs/architecture.md §8: every ECS task gets its own task role
# scoped to exactly what that service does — e.g. Documents.Api can write to raw-documents
# but not read the reports bucket or send to the notifications queue.

# ---------------------------------------------------------------------------
# Shared ECS task execution role (pulls images from ECR, writes to CloudWatch Logs,
# reads the DB-credentials secret referenced in task definitions' `secrets` block)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_task_execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "northbridge-ecs-task-execution-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "read-db-secret"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [var.db_credentials_secret_arn]
    }]
  })
}

# ---------------------------------------------------------------------------
# Per-service task roles
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "applications_api" {
  name               = "northbridge-applications-api-task-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "applications_api" {
  role = aws_iam_role.applications_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:SendMessage"], Resource = [var.credit_scoring_jobs_queue_arn] },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = [var.application_events_topic_arn] },
    ]
  })
}

resource "aws_iam_role" "documents_api" {
  name               = "northbridge-documents-api-task-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "documents_api" {
  role = aws_iam_role.documents_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = ["${var.raw_documents_bucket_arn}/*"] },
      { Effect = "Allow", Action = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"], Resource = [var.raw_documents_kms_key_arn] },
      { Effect = "Allow", Action = ["sqs:SendMessage"], Resource = [var.document_validation_queue_arn, var.fraud_analysis_jobs_queue_arn] },
    ]
  })
}

resource "aws_iam_role" "decisioning_api" {
  name               = "northbridge-decisioning-api-task-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "decisioning_api" {
  role = aws_iam_role.decisioning_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = ["${var.generated_documents_bucket_arn}/*"] },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = [var.application_events_topic_arn] },
    ]
  })
}

resource "aws_iam_role" "document_validation_worker" {
  name               = "northbridge-document-validation-worker-task-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "document_validation_worker" {
  role = aws_iam_role.document_validation_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = [var.document_validation_queue_arn] },
    ]
  })
}

resource "aws_iam_role" "status_projector_worker" {
  name               = "northbridge-status-projector-worker-task-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "status_projector_worker" {
  role = aws_iam_role.status_projector_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = [var.status_projector_queue_arn] },
    ]
  })
}

# The daily stale-report job's task role lives in modules/lambda now
# (daily_stale_report_lambda) — it runs as a Lambda function, not an ECS task.

resource "aws_iam_role" "credit_scoring_job" {
  name               = "northbridge-credit-scoring-job-task-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "credit_scoring_job" {
  role = aws_iam_role.credit_scoring_job.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = ["${var.generated_documents_bucket_arn}/*"] },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = [var.application_events_topic_arn] },
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = [var.credit_scoring_jobs_queue_arn] },
    ]
  })
}

resource "aws_iam_role" "fraud_forensics_job" {
  name               = "northbridge-fraud-forensics-job-task-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "fraud_forensics_job" {
  role = aws_iam_role.fraud_forensics_job.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = ["${var.raw_documents_bucket_arn}/*"] },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [var.raw_documents_kms_key_arn] },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = [var.application_events_topic_arn] },
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = [var.fraud_analysis_jobs_queue_arn] },
    ]
  })
}

resource "aws_iam_role" "notification_worker" {
  name               = "northbridge-notification-worker-task-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "notification_worker" {
  role = aws_iam_role.notification_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = [var.notifications_queue_arn] },
      { Effect = "Allow", Action = ["ses:SendEmail", "ses:SendRawEmail"], Resource = ["*"] },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = ["*"], Condition = { StringEquals = { "sns:Protocol" = "sms" } } },
    ]
  })
}

# ---------------------------------------------------------------------------
# EventBridge Scheduler role — invokes the daily stale-report Lambda
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler_run_task" {
  name               = "northbridge-scheduler-run-task-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

resource "aws_iam_role_policy" "scheduler_run_task" {
  role = aws_iam_role.scheduler_run_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = [var.daily_stale_report_lambda_arn] },
    ]
  })
}

# ---------------------------------------------------------------------------
# EventBridge Pipes role — reads the two fire-and-forget queues and starts ECS RunTask
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "pipes_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["pipes.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipes_run_task" {
  name               = "northbridge-pipes-run-task-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.pipes_assume.json
}

resource "aws_iam_role_policy" "pipes_run_task" {
  role = aws_iam_role.pipes_run_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [var.credit_scoring_jobs_queue_arn, var.fraud_analysis_jobs_queue_arn]
      },
      { Effect = "Allow", Action = ["ecs:RunTask"], Resource = ["*"] },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.ecs_task_execution.arn, aws_iam_role.credit_scoring_job.arn, aws_iam_role.fraud_forensics_job.arn]
      },
    ]
  })
}
