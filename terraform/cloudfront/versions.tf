terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Remote state lives in a dedicated bucket. This block is intentionally left
  # commented during initial import/zero-diff reconciliation, which runs against
  # local state so the planning phase makes zero changes to AWS. Uncomment and
  # `terraform init -migrate-state` once the state bucket exists.
  #
  # backend "s3" {
  #   bucket       = "hl7au-publications-tfstate-ap-southeast-2"
  #   key          = "cloudfront/terraform.tfstate"
  #   region       = "ap-southeast-2"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}
