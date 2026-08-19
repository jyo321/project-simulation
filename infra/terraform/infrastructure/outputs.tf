output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}

output "rds_endpoint" {
  value = module.rds.address
}

output "applicant_portal_cloudfront_domain" {
  value = module.cloudfront_frontend.applicant_portal_cloudfront_domain
}

output "reviewer_console_cloudfront_domain" {
  value = module.cloudfront_frontend.reviewer_console_cloudfront_domain
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "raw_documents_bucket" {
  value = module.s3_documents.raw_documents_bucket_name
}

output "generated_documents_bucket" {
  value = module.s3_documents.generated_documents_bucket_name
}

output "reports_bucket" {
  value = module.s3_documents.reports_bucket_name
}

output "application_events_topic_arn" {
  value = module.messaging.application_events_topic_arn
}

# Named to match the GitHub secrets frontend-ci-cd.yml expects (secrets.applicant_portal_bucket,
# etc.) — after `terraform apply`, copy these values straight into repo secrets.
output "applicant_portal_bucket" {
  value = module.cloudfront_frontend.applicant_portal_bucket_name
}

output "applicant_portal_cloudfront_id" {
  value = module.cloudfront_frontend.applicant_portal_cloudfront_id
}

output "reviewer_console_bucket" {
  value = module.cloudfront_frontend.reviewer_console_bucket_name
}

output "reviewer_console_cloudfront_id" {
  value = module.cloudfront_frontend.reviewer_console_cloudfront_id
}

output "github_actions_deploy_role_arn" {
  value = module.github_oidc.github_actions_deploy_role_arn
}

output "github_actions_terraform_role_arn" {
  value = module.github_oidc.github_actions_terraform_role_arn
}
