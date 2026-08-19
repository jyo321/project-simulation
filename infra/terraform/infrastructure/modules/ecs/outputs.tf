output "cluster_arn" {
  value = aws_ecs_cluster.main.arn
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "alb_arn" {
  value = aws_lb.main.arn
}

output "credit_scoring_job_task_definition_arn" {
  value = aws_ecs_task_definition.credit_scoring_job.arn
}

output "fraud_forensics_job_task_definition_arn" {
  value = aws_ecs_task_definition.fraud_forensics_job.arn
}
