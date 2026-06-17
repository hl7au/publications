# Viewer-request function that performs canonical-URL routing for the site.
# The function source is the single source of truth (terraform/cloudfront/fhir-canonical.js).
resource "aws_cloudfront_function" "fhir_canonical" {
  name    = "fhir-canonical"
  runtime = "cloudfront-js-2.0"
  comment = ""
  publish = true
  code    = file("${path.module}/fhir-canonical.js")
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2"
  price_class         = "PriceClass_All"
  default_root_object = "index.html"
  aliases             = local.aliases

  origin {
    origin_id   = local.origin_id
    domain_name = local.origin_domain

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only"
      origin_ssl_protocols     = ["SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
  }

  default_cache_behavior {
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["HEAD", "GET", "OPTIONS"]
    cached_methods         = ["HEAD", "GET"]
    compress               = true
    cache_policy_id        = local.cache_policy_id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.fhir_canonical.arn
    }
  }

  # Static assets by extension: served from the origin without the canonical function.
  dynamic "ordered_cache_behavior" {
    for_each = local.ordered_patterns
    content {
      path_pattern           = ordered_cache_behavior.value
      target_origin_id       = local.origin_id
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
    acm_certificate_arn      = local.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}
