# preprod.hl7.org.au — a full clone of the prod content bucket with the dynamic-publish-box
# migration applied, served at a /fhir root and REUSING the fhir-canonical function so
# canonical/versioned redirects behave exactly like prod. This is the faithful migration-review
# environment (and a general prod-mirror going forward). The EC2 on staging.hl7.org.au is
# untouched. The bucket is DISPOSABLE — content is cloned from prod by an out-of-band S3->S3
# sync, never by Terraform — so no prevent_destroy and no versioning.

resource "aws_s3_bucket" "preprod" {
  bucket = local.preprod_bucket
}

resource "aws_s3_bucket_website_configuration" "preprod" {
  bucket = aws_s3_bucket.preprod.id
  index_document {
    suffix = "index.html"
  }
}

# Public static website (website-endpoint origin), matching the prod content bucket.
resource "aws_s3_bucket_public_access_block" "preprod" {
  bucket                  = aws_s3_bucket.preprod.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "preprod" {
  bucket = aws_s3_bucket.preprod.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_policy" "preprod" {
  bucket     = aws_s3_bucket.preprod.id
  depends_on = [aws_s3_bucket_public_access_block.preprod]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::${local.preprod_bucket}/*"
      }
    ]
  })
}

resource "aws_cloudfront_distribution" "preprod" {
  count               = var.enable_cdn ? 1 : 0
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2"
  price_class         = "PriceClass_All"
  default_root_object = "index.html"
  aliases             = [local.preprod_host]
  comment             = "preprod.hl7.org.au — prod mirror / migration review"

  origin {
    origin_id   = local.preprod_origin_id
    domain_name = local.preprod_origin_domain
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
  }

  default_cache_behavior {
    target_origin_id       = local.preprod_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["HEAD", "GET", "OPTIONS"]
    cached_methods         = ["HEAD", "GET"]
    compress               = true
    cache_policy_id        = local.cache_policy_id

    # Same published function as prod — its logic is host-relative (the terminology.hl7.org.au
    # branch simply never matches here), so redirects keep the user on preprod.hl7.org.au.
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.fhir_canonical.arn
    }
  }

  # Static assets by extension: served from the origin without the canonical function (as prod).
  dynamic "ordered_cache_behavior" {
    for_each = local.ordered_patterns
    content {
      path_pattern           = ordered_cache_behavior.value
      target_origin_id       = local.preprod_origin_id
      viewer_protocol_policy = "allow-all"
      allowed_methods        = ["HEAD", "GET"]
      cached_methods         = ["HEAD", "GET"]
      compress               = true
      cache_policy_id        = local.cache_policy_id
    }
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/404error.html"
    error_caching_min_ttl = 10
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
