# Content bucket for the published IG (origin for the CloudFront distribution).
# Terraform manages the bucket SETTINGS only. The objects (published IG content) are
# written by the publish pipeline and the canonical-redirect backfill, never by Terraform.
# Encryption is intentionally left unmanaged (S3 default SSE-S3/AES256).
resource "aws_s3_bucket" "content" {
  bucket = local.content_bucket

  # Precious: holds every published IG version. Never let Terraform delete it.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_website_configuration" "content" {
  bucket = aws_s3_bucket.content.id

  index_document {
    suffix = "index.html"
  }
  # No error_document today: CloudFront serves the 404 page via a custom error response.
  # Adding error_document here is a separate, deliberate change (see README).
}

resource "aws_s3_bucket_versioning" "content" {
  bucket = aws_s3_bucket.content.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Public static website: ACLs/policies are intentionally NOT blocked.
resource "aws_s3_bucket_public_access_block" "content" {
  bucket = aws_s3_bucket.content.id

  block_public_acls       = false
  block_public_policy      = false
  ignore_public_acls       = false
  restrict_public_buckets  = false
}

resource "aws_s3_bucket_ownership_controls" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_policy" "content" {
  bucket = aws_s3_bucket.content.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::${local.content_bucket}/*"
      }
    ]
  })
}
