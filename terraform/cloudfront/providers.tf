# CloudFront is a global service, so the provider region is immaterial for these
# resources. The prod viewer ACM certificate lives in us-east-1 and is referenced by ARN.
provider "aws" {
  region = "ap-southeast-2"
}

# CloudFront viewer certificates MUST live in us-east-1. This aliased provider is used
# only to create/validate the ACM cert for the preprod + previews hosts (see acm.tf).
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
