variable "environment" {
  type = string
}

# ---------------------------------------------------------------------------
# The topics/queues below need nothing but `environment` — they're self-contained.
# The variables below are only consumed by the EventBridge Scheduler/Pipes resources
# at the bottom of main.tf, which turn queue messages and a cron tick into ECS
# RunTask/Lambda invocations and therefore need modules/ecs, modules/lambda and
# modules/iam's outputs. Terraform still sequences this correctly even though it's one
# module: those resources depend on module.ecs/module.lambda/module.iam, which in turn
# depend on THIS module's topic/queue outputs — two distinct resources within the same
# module, not a whole-module cycle.
# ---------------------------------------------------------------------------

variable "ecs_cluster_arn" {
  type = string
}

variable "credit_scoring_job_task_definition_arn" {
  type = string
}

variable "fraud_forensics_job_task_definition_arn" {
  type = string
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "ecs_worker_security_group_id" {
  type = string
}

variable "pipes_run_task_role_arn" {
  type = string
}

variable "scheduler_run_task_role_arn" {
  type = string
}

variable "daily_stale_report_lambda_arn" {
  type = string
}
