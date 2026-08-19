output "function_arn" {
  value = aws_lambda_function.daily_stale_report.arn
}

output "function_name" {
  value = aws_lambda_function.daily_stale_report.function_name
}
