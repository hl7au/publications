# CloudFront is a global service, so the provider region is immaterial for these
# resources. The viewer ACM certificate lives in us-east-1 and is referenced by ARN.
provider "aws" {
  region = "ap-southeast-2"
}
