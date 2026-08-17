# Fan-out backbone (brief §5, docs/architecture.md §4/§6/§7): one SNS topic every API
# publishes domain events to; SQS queues subscribed per-consumer; dedicated job queues for
# the two fire-and-forget workloads; EventBridge for the daily cron and for turning queued
# fire-and-forget jobs into one-shot ECS tasks.

resource "aws_sns_topic" "application_events" {
  name = "northbridge-application-events-${local.environment}"
}

resource "aws_sns_topic" "ops_alerts" {
  name = "northbridge-ops-alerts-${local.environment}"
}

resource "aws_sns_topic_subscription" "ops_alerts_email" {
  topic_arn = aws_sns_topic.ops_alerts.arn
  protocol  = "email"
  endpoint  = "platform-oncall@northbridgelending.com"
}

# ---------------------------------------------------------------------------
# Document Validation Worker queue (service-triggered, brief §2.3.1)
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "document_validation_dlq" {
  name = "document-validation-dlq-${local.environment}"
}

resource "aws_sqs_queue" "document_validation" {
  name                       = "document-validation-${local.environment}"
  visibility_timeout_seconds = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.document_validation_dlq.arn
    maxReceiveCount     = 5
  })
}

# ---------------------------------------------------------------------------
# Application Status Projector queue (service-triggered, subscribed to application-events)
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "status_projector_dlq" {
  name = "status-projector-dlq-${local.environment}"
}

resource "aws_sqs_queue" "status_projector" {
  name                       = "status-projector-${local.environment}"
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.status_projector_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue_policy" "status_projector" {
  queue_url = aws_sqs_queue.status_projector.id
  policy    = data.aws_iam_policy_document.sns_to_sqs["status_projector"].json
}

resource "aws_sns_topic_subscription" "status_projector" {
  topic_arn            = aws_sns_topic.application_events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.status_projector.arn
  raw_message_delivery = true
}

# ---------------------------------------------------------------------------
# Notification queue (the Notification Service from brief §2.6) + DLQ + alarm
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "notifications_dlq" {
  name = "notifications-dlq-${local.environment}"
}

resource "aws_sqs_queue" "notifications" {
  name                       = "notifications-${local.environment}"
  visibility_timeout_seconds = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notifications_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue_policy" "notifications" {
  queue_url = aws_sqs_queue.notifications.id
  policy    = data.aws_iam_policy_document.sns_to_sqs["notifications"].json
}

resource "aws_sns_topic_subscription" "notifications" {
  topic_arn            = aws_sns_topic.application_events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.notifications.arn
  raw_message_delivery = true
}

data "aws_iam_policy_document" "sns_to_sqs" {
  for_each = {
    status_projector = aws_sqs_queue.status_projector.arn
    notifications    = aws_sqs_queue.notifications.arn
  }

  statement {
    sid     = "AllowSnsPublish"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    resources = [each.value]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.application_events.arn]
    }
  }
}

# Failure alerting (brief §5.4 / docs/architecture.md §7): DLQ depth >= 1 pages ops.
resource "aws_cloudwatch_metric_alarm" "notifications_dlq_depth" {
  alarm_name          = "northbridge-notifications-dlq-depth-${local.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Notification(s) exhausted all retries and landed in the DLQ — needs manual investigation and replay."
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.notifications_dlq.name
  }
}

# ---------------------------------------------------------------------------
# Fire-and-forget job queues (brief §2.3.3 / §6): CreditScoringJob, FraudForensicsJob
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "credit_scoring_jobs_dlq" {
  name = "credit-scoring-jobs-dlq-${local.environment}"
}

resource "aws_sqs_queue" "credit_scoring_jobs" {
  name = "credit-scoring-jobs-${local.environment}"
  # Long visibility timeout: the EventBridge Pipe removes the message as soon as it hands
  # off to ecs:RunTask, so this only needs to cover the pipe's own processing window, not
  # the job's full >20 minute runtime.
  visibility_timeout_seconds = 120

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.credit_scoring_jobs_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "fraud_analysis_jobs_dlq" {
  name = "fraud-analysis-jobs-dlq-${local.environment}"
}

resource "aws_sqs_queue" "fraud_analysis_jobs" {
  name                       = "fraud-analysis-jobs-${local.environment}"
  visibility_timeout_seconds = 120

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.fraud_analysis_jobs_dlq.arn
    maxReceiveCount     = 3
  })
}

# ---------------------------------------------------------------------------
# EventBridge Scheduler — daily time-based trigger (brief §2.3.2)
# ---------------------------------------------------------------------------

resource "aws_scheduler_schedule" "daily_stale_report" {
  name                         = "northbridge-daily-stale-report-${local.environment}"
  schedule_expression          = "cron(0 2 * * ? *)"
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.scheduler_run_task.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.daily_stale_report_job.arn
      launch_type         = "FARGATE"
      task_count          = 1

      network_configuration {
        subnets          = [for s in aws_subnet.private_app : s.id]
        security_groups  = [aws_security_group.ecs_worker.id]
        assign_public_ip = false
      }
    }

    retry_policy {
      maximum_retry_attempts = 0 # the job's own Postgres advisory lock makes retries redundant / risky
    }
  }
}

# ---------------------------------------------------------------------------
# EventBridge Pipes — SQS -> ecs:RunTask for the two fire-and-forget job types
# ---------------------------------------------------------------------------

resource "aws_pipes_pipe" "credit_scoring" {
  name     = "northbridge-credit-scoring-pipe-${local.environment}"
  role_arn = aws_iam_role.pipes_run_task.arn
  source   = aws_sqs_queue.credit_scoring_jobs.arn
  target   = aws_ecs_cluster.main.arn

  target_parameters {
    ecs_task_parameters {
      task_definition_arn = aws_ecs_task_definition.credit_scoring_job.arn
      launch_type         = "FARGATE"

      network_configuration {
        aws_vpc_configuration {
          subnets          = [for s in aws_subnet.private_app : s.id]
          security_groups  = [aws_security_group.ecs_worker.id]
          assign_public_ip = "DISABLED"
        }
      }

      overrides {
        container_override {
          name = "credit-scoring-job"

          environment {
            name  = "JOB_ID"
            value = "$.body.jobId"
          }
          environment {
            name  = "LOAN_APPLICATION_ID"
            value = "$.body.loanApplicationId"
          }
        }
      }
    }
  }
}

resource "aws_pipes_pipe" "fraud_forensics" {
  name     = "northbridge-fraud-forensics-pipe-${local.environment}"
  role_arn = aws_iam_role.pipes_run_task.arn
  source   = aws_sqs_queue.fraud_analysis_jobs.arn
  target   = aws_ecs_cluster.main.arn

  target_parameters {
    ecs_task_parameters {
      task_definition_arn = aws_ecs_task_definition.fraud_forensics_job.arn
      launch_type         = "FARGATE"

      network_configuration {
        aws_vpc_configuration {
          subnets          = [for s in aws_subnet.private_app : s.id]
          security_groups  = [aws_security_group.ecs_worker.id]
          assign_public_ip = "DISABLED"
        }
      }

      overrides {
        container_override {
          name = "fraud-forensics-job"

          environment {
            name  = "JOB_ID"
            value = "$.body.jobId"
          }
          environment {
            name  = "LOAN_APPLICATION_ID"
            value = "$.body.loanApplicationId"
          }
        }
      }
    }
  }
}
