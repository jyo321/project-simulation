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

# Named to match the GitHub secrets frontend-ci-cd.yml expects (secrets.applicant_portal_bucket,
# etc.) — after `terraform apply`, copy these values straight into repo secrets.
output "applicant_portal_bucket" {
  value = aws_s3_bucket.spa["applicant_portal"].bucket
}

output "applicant_portal_cloudfront_id" {
  value = aws_cloudfront_distribution.spa["applicant_portal"].id
}

output "reviewer_console_bucket" {
  value = aws_s3_bucket.spa["reviewer_console"].bucket
}

output "reviewer_console_cloudfront_id" {
  value = aws_cloudfront_distribution.spa["reviewer_console"].id
}
