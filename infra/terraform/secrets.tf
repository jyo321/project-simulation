# AWS Secrets Manager (brief §5.5): connection strings and API keys are injected into ECS
# tasks via the task definition's `secrets` block, never as plaintext `environment` values.

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "northbridge/${local.environment}/db-credentials"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    connectionString = "Host=${aws_db_instance.postgres.address};Port=5432;Database=${var.db_name};Username=${var.db_username};Password=${var.db_password}"
  })
}
