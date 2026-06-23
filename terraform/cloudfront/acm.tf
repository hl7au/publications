# Viewer certificate for the two new hosts (preprod + previews). MUST be in us-east-1 for
# CloudFront. DNS-validated against the hl7.org.au Route 53 zone. One cert, both hostnames.
# (The prod cert for hl7.org.au/terminology stays referenced-by-ARN in locals; not managed here.)
resource "aws_acm_certificate" "new_hosts" {
  count                     = var.enable_cdn ? 1 : 0
  provider                  = aws.us_east_1
  domain_name               = local.preprod_host
  subject_alternative_names = [local.previews_host]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# One Route 53 validation record per distinct domain on the cert. Gated with the cert.
resource "aws_route53_record" "new_hosts_validation" {
  for_each = var.enable_cdn ? {
    for dvo in aws_acm_certificate.new_hosts[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  zone_id         = local.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "new_hosts" {
  count                   = var.enable_cdn ? 1 : 0
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.new_hosts[0].arn
  validation_record_fqdns = [for r in aws_route53_record.new_hosts_validation : r.fqdn]
}
