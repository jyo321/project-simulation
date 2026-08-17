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
  name               = "northbridge-ecs-task-execution-${local.environment}"
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
      Resource = [aws_secretsmanager_secret.db_credentials.arn]
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
  name               = "northbridge-applications-api-task-role-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "applications_api" {
  role = aws_iam_role.applications_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:SendMessage"], Resource = [aws_sqs_queue.credit_scoring_jobs.arn] },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = [aws_sns_topic.application_events.arn] },
    ]
  })
}

resource "aws_iam_role" "documents_api" {
  name               = "northbridge-documents-api-task-role-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "documents_api" {
  role = aws_iam_role.documents_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = ["${aws_s3_bucket.raw_documents.arn}/*"] },
      { Effect = "Allow", Action = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"], Resource = [aws_kms_key.raw_documents.arn] },
      { Effect = "Allow", Action = ["sqs:SendMessage"], Resource = [aws_sqs_queue.document_validation.arn, aws_sqs_queue.fraud_analysis_jobs.arn] },
    ]
  })
}

resource "aws_iam_role" "decisioning_api" {
  name               = "northbridge-decisioning-api-task-role-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "decisioning_api" {
  role = aws_iam_role.decisioning_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = ["${aws_s3_bucket.generated_documents.arn}/*"] },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = [aws_sns_topic.application_events.arn] },
    ]
  })
}

resource "aws_iam_role" "document_validation_worker" {
  name               = "northbridge-document-validation-worker-task-role-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "document_validation_worker" {
  role = aws_iam_role.document_validation_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = [aws_sqs_queue.document_validation.arn] },
    ]
  })
}

resource "aws_iam_role" "status_projector_worker" {
  name               = "northbridge-status-projector-worker-task-role-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "status_projector_worker" {
  role = aws_iam_role.status_projector_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = [aws_sqs_queue.status_projector.arn] },
    ]
  })
}

resource "aws_iam_role" "daily_stale_report_job" {
  name               = "northbridge-daily-stale-report-job-task-role-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "daily_stale_report_job" {
  role = aws_iam_role.daily_stale_report_job.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = ["${aws_s3_bucket.reports.arn}/*"] },
    ]
  })
}

resource "aws_iam_role" "credit_scoring_job" {
  name               = "northbridge-credit-scoring-job-task-role-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "credit_scoring_job" {
  role = aws_iam_role.credit_scoring_job.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = ["${aws_s3_bucket.generated_documents.arn}/*"] },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = [aws_sns_topic.application_events.arn] },
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = [aws_sqs_queue.credit_scoring_jobs.arn] },
    ]
  })
}

resource "aws_iam_role" "fraud_forensics_job" {
  name               = "northbridge-fraud-forensics-job-task-role-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "fraud_forensics_job" {
  role = aws_iam_role.fraud_forensics_job.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = ["${aws_s3_bucket.raw_documents.arn}/*"] },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [aws_kms_key.raw_documents.arn] },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = [aws_sns_topic.application_events.arn] },
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = [aws_sqs_queue.fraud_analysis_jobs.arn] },
    ]
  })
}

resource "aws_iam_role" "notification_worker" {
  name               = "northbridge-notification-worker-task-role-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "notification_worker" {
  role = aws_iam_role.notification_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = [aws_sqs_queue.notifications.arn] },
      { Effect = "Allow", Action = ["ses:SendEmail", "ses:SendRawEmail"], Resource = ["*"] },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = ["*"], Condition = { StringEquals = { "sns:Protocol" = "sms" } } },
    ]
  })
}

# ---------------------------------------------------------------------------
# EventBridge Scheduler role — invokes ecs:RunTask for the daily job
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
  name               = "northbridge-scheduler-run-task-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

resource "aws_iam_role_policy" "scheduler_run_task" {
  role = aws_iam_role.scheduler_run_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecs:RunTask"], Resource = ["*"] },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = [aws_iam_role.ecs_task_execution.arn, aws_iam_role.daily_stale_report_job.arn] },
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
  name               = "northbridge-pipes-run-task-${local.environment}"
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
        Resource = [aws_sqs_queue.credit_scoring_jobs.arn, aws_sqs_queue.fraud_analysis_jobs.arn]
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
