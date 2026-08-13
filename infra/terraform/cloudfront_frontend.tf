# Two independent S3 + CloudFront pairs (brief §2.1 / §5.1): each Angular SPA is its own
# bucket and its own distribution so one app's release can never touch the other's.

locals {
  spas = {
    applicant_portal = {
      bucket_name = "northbridge-applicant-portal-${var.environment}"
      comment     = "Northbridge Applicant Portal"
    }
    reviewer_console = {
      bucket_name = "northbridge-reviewer-console-${var.environment}"
      comment     = "Northbridge Reviewer Console"
    }
  }
}

resource "aws_s3_bucket" "spa" {
  for_each = local.spas

  bucket = each.value.bucket_name
}

resource "aws_s3_bucket_public_access_block" "spa" {
  for_each = aws_s3_bucket.spa

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "spa" {
  for_each = local.spas

  name                              = "northbridge-${each.key}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "spa" {
  for_each = local.spas

  enabled             = true
  default_root_object = "index.html"
  comment             = each.value.comment

  origin {
    domain_name              = aws_s3_bucket.spa[each.key].bucket_regional_domain_name
    origin_id                = "s3-${each.key}"
    origin_access_control_id = aws_cloudfront_origin_access_control.spa[each.key].id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-${each.key}"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  # Angular client-side routing: unknown paths fall back to index.html so deep links work.
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "spa_bucket_policy" {
  for_each = local.spas

  statement {
    sid       = "AllowCloudFrontRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.spa[each.key].arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.spa[each.key].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "spa" {
  for_each = local.spas

  bucket = aws_s3_bucket.spa[each.key].id
  policy = data.aws_iam_policy_document.spa_bucket_policy[each.key].json
}
