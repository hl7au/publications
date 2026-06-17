terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Remote state in a dedicated, private, versioned bucket. Native S3 locking
  # (use_lockfile) — no DynamoDB table required.
  backend "s3" {
    bucket       = "hl7au-publications-tfstate-ap-southeast-2"
    key          = "cloudfront/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
