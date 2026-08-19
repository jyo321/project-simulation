output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "applications_api_role_arn" {
  value = aws_iam_role.applications_api.arn
}

output "documents_api_role_arn" {
  value = aws_iam_role.documents_api.arn
}

output "decisioning_api_role_arn" {
  value = aws_iam_role.decisioning_api.arn
}

output "document_validation_worker_role_arn" {
  value = aws_iam_role.document_validation_worker.arn
}

output "status_projector_worker_role_arn" {
  value = aws_iam_role.status_projector_worker.arn
}

output "credit_scoring_job_role_arn" {
  value = aws_iam_role.credit_scoring_job.arn
}

output "fraud_forensics_job_role_arn" {
  value = aws_iam_role.fraud_forensics_job.arn
}

output "notification_worker_role_arn" {
  value = aws_iam_role.notification_worker.arn
}

output "scheduler_run_task_role_arn" {
  value = aws_iam_role.scheduler_run_task.arn
}

output "pipes_run_task_role_arn" {
  value = aws_iam_role.pipes_run_task.arn
}
