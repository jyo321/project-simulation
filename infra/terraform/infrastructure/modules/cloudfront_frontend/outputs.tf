output "applicant_portal_bucket_name" {
  value = aws_s3_bucket.spa["applicant_portal"].bucket
}

output "applicant_portal_cloudfront_domain" {
  value = aws_cloudfront_distribution.spa["applicant_portal"].domain_name
}

output "applicant_portal_cloudfront_id" {
  value = aws_cloudfront_distribution.spa["applicant_portal"].id
}

output "reviewer_console_bucket_name" {
  value = aws_s3_bucket.spa["reviewer_console"].bucket
}

output "reviewer_console_cloudfront_domain" {
  value = aws_cloudfront_distribution.spa["reviewer_console"].domain_name
}

output "reviewer_console_cloudfront_id" {
  value = aws_cloudfront_distribution.spa["reviewer_console"].id
}
