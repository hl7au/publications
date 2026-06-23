# previews.hl7.org.au — per-branch / per-PR CI previews, path-based:
#   https://previews.hl7.org.au/<slug>/{working,milestone}/fhir/<version>/index.html
# Written by the au-fhir-base build-review-publish workflow (aws s3 sync). No canonical
# function (the fhir-canonical fidelity does not apply to prefixed previews; baked canonicals
# resolve to prod either way). Objects auto-expire via a lifecycle rule. Disposable bucket.

resource "aws_s3_bucket" "previews" {
  bucket = local.previews_bucket
}

resource "aws_s3_bucket_website_configuration" "previews" {
  bucket = aws_s3_bucket.previews.id
  index_document {
    suffix = "index.html"
  }
}

# Expire every preview object N days after creation so old branches' previews self-clean.
resource "aws_s3_bucket_lifecycle_configuration" "previews" {
  bucket = aws_s3_bucket.previews.id
  rule {
    id     = "expire-previews"
    status = "Enabled"
    filter {}
    expiration {
      days = local.previews_expiry_days
    }
  }
}

resource "aws_s3_bucket_public_access_block" "previews" {
  bucket                  = aws_s3_bucket.previews.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "previews" {
  bucket = aws_s3_bucket.previews.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_policy" "previews" {
  bucket     = aws_s3_bucket.previews.id
  depends_on = [aws_s3_bucket_public_access_block.previews]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::${local.previews_bucket}/*"
      }
    ]
  })
}

resource "aws_cloudfront_distribution" "previews" {
  count               = var.enable_cdn ? 1 : 0
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2"
  price_class         = "PriceClass_All"
  default_root_object = "index.html"
  aliases             = [local.previews_host]
  comment             = "previews.hl7.org.au — per-branch CI previews"

  origin {
    origin_id   = local.previews_origin_id
    domain_name = local.previews_origin_domain
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
  }

  # No canonical function. CachingDisabled so a re-pushed preview is immediately fresh.
  default_cache_behavior {
    target_origin_id       = local.previews_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["HEAD", "GET", "OPTIONS"]
    cached_methods         = ["HEAD", "GET"]
    compress               = true
    cache_policy_id        = local.cache_policy_disabled_id
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.new_hosts[0].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}
