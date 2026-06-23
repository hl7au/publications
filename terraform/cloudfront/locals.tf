locals {
  # Distribution being adopted (hl7.org.au).
  distribution_id = "E2U6NB1JDLY5NT"

  account_id        = "966489602583"
  oidc_provider_arn = "arn:aws:iam::966489602583:oidc-provider/token.actions.githubusercontent.com"
  oidc_role_arn     = "arn:aws:iam::966489602583:role/ghactions_publications_oidc"

  # Content bucket (settings managed here; objects are owned by the publish pipeline).
  content_bucket = "hl7au-fhir-ig"

  # S3 *website* endpoint used as a custom origin (not an OAC/S3 origin).
  origin_id     = "hl7au-fhir-ig.s3-website-ap-southeast-2.amazonaws.com"
  origin_domain = "hl7au-fhir-ig.s3-website-ap-southeast-2.amazonaws.com"

  aliases = ["hl7.org.au", "terminology.hl7.org.au"]

  # us-east-1 ACM cert (referenced, not managed).
  acm_certificate_arn = "arn:aws:acm:us-east-1:966489602583:certificate/f74a4c7a-f2a1-4300-a1d3-8f995f08ebb1"

  # AWS managed cache policy: CachingOptimized.
  cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  # AWS managed cache policy: CachingDisabled (TTL 0) — used by the previews dist so a
  # re-pushed branch preview is always fresh without per-build CloudFront invalidations.
  cache_policy_disabled_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

  # Route 53 public hosted zone for hl7.org.au (records + ACM DNS validation live here).
  hosted_zone_id = "Z07541111UG2ZBD9DA0ZE"

  # --- New S3+CloudFront environments (additive; prod + the staging EC2 are untouched) ---
  # preprod: a full clone of prod + the dynamic-publish-box migration applied, served at a
  # /fhir root and REUSING the fhir-canonical function so redirects behave exactly like prod.
  preprod_host          = "preprod.hl7.org.au"
  preprod_bucket        = "hl7au-fhir-ig-mirror"
  preprod_origin_domain = "hl7au-fhir-ig-mirror.s3-website-ap-southeast-2.amazonaws.com"
  preprod_origin_id     = "hl7au-fhir-ig-mirror.s3-website-ap-southeast-2.amazonaws.com"

  # previews: per-branch CI previews, path-based (/<slug>/{working,milestone}/fhir/...).
  # No canonical function; objects auto-expire via a lifecycle rule.
  previews_host          = "previews.hl7.org.au"
  previews_bucket        = "hl7au-fhir-ig-previews"
  previews_origin_domain = "hl7au-fhir-ig-previews.s3-website-ap-southeast-2.amazonaws.com"
  previews_origin_id     = "hl7au-fhir-ig-previews.s3-website-ap-southeast-2.amazonaws.com"
  previews_expiry_days   = 30

  # Static-asset extensions served straight from the origin (no canonical function).
  # All 13 ordered behaviors are identical except for the path pattern.
  ordered_patterns = [
    "/*.html", "/*.json", "/*.css", "/*.jpg", "/*.png", "/*.xml",
    "/*.svg", "/*.js", "/*.gif", "/*.tgz", "/*.zip", "/*.pdf", "/*.txt",
  ]
}
