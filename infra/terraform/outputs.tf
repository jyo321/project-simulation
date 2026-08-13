output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "applicant_portal_cloudfront_domain" {
  value = aws_cloudfront_distribution.spa["applicant_portal"].domain_name
}

output "reviewer_console_cloudfront_domain" {
  value = aws_cloudfront_distribution.spa["reviewer_console"].domain_name
}

output "ecr_repository_urls" {
  value = local.ecr_uri
}

output "raw_documents_bucket" {
  value = aws_s3_bucket.raw_documents.bucket
}

output "generated_documents_bucket" {
  value = aws_s3_bucket.generated_documents.bucket
}

output "reports_bucket" {
  value = aws_s3_bucket.reports.bucket
}

output "application_events_topic_arn" {
  value = aws_sns_topic.application_events.arn
}
