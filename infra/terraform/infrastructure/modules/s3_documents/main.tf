# Three buckets from the brief (§2.5): raw-documents (encrypted with a CMK per the "with
# encryption for one bucket" requirement), generated-documents, reports.

resource "aws_kms_key" "raw_documents" {
  description             = "CMK for the raw-documents bucket (applicant-uploaded PII/financial docs)"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "raw_documents" {
  name          = "alias/northbridge-raw-documents-${var.environment}"
  target_key_id = aws_kms_key.raw_documents.key_id
}

resource "aws_s3_bucket" "raw_documents" {
  bucket = "northbridge-raw-documents-${var.environment}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_documents" {
  bucket = aws_s3_bucket.raw_documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.raw_documents.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket" "generated_documents" {
  bucket = "northbridge-generated-documents-${var.environment}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "generated_documents" {
  bucket = aws_s3_bucket.generated_documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "reports" {
  bucket = "northbridge-reports-${var.environment}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# All three buckets are fully private — access is exclusively via pre-signed URLs issued
# by Documents.Api or via each ECS task's own IAM role.
resource "aws_s3_bucket_public_access_block" "all" {
  for_each = {
    raw_documents       = aws_s3_bucket.raw_documents.id
    generated_documents = aws_s3_bucket.generated_documents.id
    reports             = aws_s3_bucket.reports.id
  }

  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "all" {
  for_each = {
    raw_documents       = aws_s3_bucket.raw_documents.id
    generated_documents = aws_s3_bucket.generated_documents.id
    reports             = aws_s3_bucket.reports.id
  }

  bucket = each.value
  versioning_configuration {
    status = "Enabled"
  }
}
