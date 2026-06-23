# Route 53 alias records for the two new hosts. GATED on enable_cdn — held until the
# preprod.hl7.org.au / previews.hl7.org.au subdomains are approved (Brett). Additive when
# enabled — staging.hl7.org.au (the EC2), the apex, terminology, and www are untouched.
# CloudFront's fixed hosted-zone id is Z2FDTNDATAQYW2.
locals {
  cloudfront_zone_id = "Z2FDTNDATAQYW2"
}

resource "aws_route53_record" "preprod_a" {
  count   = var.enable_cdn ? 1 : 0
  zone_id = local.hosted_zone_id
  name    = local.preprod_host
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.preprod[0].domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "preprod_aaaa" {
  count   = var.enable_cdn ? 1 : 0
  zone_id = local.hosted_zone_id
  name    = local.preprod_host
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.preprod[0].domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "previews_a" {
  count   = var.enable_cdn ? 1 : 0
  zone_id = local.hosted_zone_id
  name    = local.previews_host
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.previews[0].domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "previews_aaaa" {
  count   = var.enable_cdn ? 1 : 0
  zone_id = local.hosted_zone_id
  name    = local.previews_host
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.previews[0].domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}
