output "raw_documents_bucket_name" {
  value = aws_s3_bucket.raw_documents.bucket
}

output "raw_documents_bucket_arn" {
  value = aws_s3_bucket.raw_documents.arn
}

output "raw_documents_kms_key_arn" {
  value = aws_kms_key.raw_documents.arn
}

output "generated_documents_bucket_name" {
  value = aws_s3_bucket.generated_documents.bucket
}

output "generated_documents_bucket_arn" {
  value = aws_s3_bucket.generated_documents.arn
}

output "reports_bucket_name" {
  value = aws_s3_bucket.reports.bucket
}

output "reports_bucket_arn" {
  value = aws_s3_bucket.reports.arn
}
