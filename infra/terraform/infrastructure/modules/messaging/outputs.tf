output "application_events_topic_arn" {
  value = aws_sns_topic.application_events.arn
}

output "ops_alerts_topic_arn" {
  value = aws_sns_topic.ops_alerts.arn
}

output "document_validation_queue_id" {
  value = aws_sqs_queue.document_validation.id
}

output "document_validation_queue_arn" {
  value = aws_sqs_queue.document_validation.arn
}

output "status_projector_queue_id" {
  value = aws_sqs_queue.status_projector.id
}

output "status_projector_queue_arn" {
  value = aws_sqs_queue.status_projector.arn
}

output "notifications_queue_id" {
  value = aws_sqs_queue.notifications.id
}

output "notifications_queue_arn" {
  value = aws_sqs_queue.notifications.arn
}

output "credit_scoring_jobs_queue_id" {
  value = aws_sqs_queue.credit_scoring_jobs.id
}

output "credit_scoring_jobs_queue_arn" {
  value = aws_sqs_queue.credit_scoring_jobs.arn
}

output "fraud_analysis_jobs_queue_id" {
  value = aws_sqs_queue.fraud_analysis_jobs.id
}

output "fraud_analysis_jobs_queue_arn" {
  value = aws_sqs_queue.fraud_analysis_jobs.arn
}
