output "db_credentials_secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "db_credentials_secret_id" {
  value = aws_secretsmanager_secret.db_credentials.id
}
