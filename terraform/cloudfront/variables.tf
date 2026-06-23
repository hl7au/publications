# Gate for the custom-domain CDN layer (ACM cert + CloudFront distributions + Route 53 records)
# for the preprod/previews hosts. The S3 buckets are ALWAYS created; only the public-domain
# layer is gated. Kept false until the preprod.hl7.org.au / previews.hl7.org.au subdomains are
# approved (Brett) — so a routine `terraform apply` can never create DNS records or a cert.
# Until then, preview content directly at the S3 *website* endpoints (no DNS needed).
# Flip to true (after approval): `terraform apply -var enable_cdn=true`.
variable "enable_cdn" {
  description = "Create the ACM cert, CloudFront distributions, and Route 53 records for preprod/previews."
  type        = bool
  default     = false
}
