# GitHub Actions OIDC role used by the publications repos to publish IG content and
# (via this Terraform) manage the serving infrastructure. Shared/broadly-trusted
# (repo:hl7au/*), so it carries prevent_destroy. The OIDC provider is referenced by ARN
# (not via a data source, so the pipeline does not need iam:ListOpenIDConnectProviders).
resource "aws_iam_role" "ghactions_publications_oidc" {
  name        = "ghactions_publications_oidc"
  description = "A github actions oidc role for the publications repo to allow publishing of IG profiles to s3 buckets."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = local.oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
          StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:hl7au/*" }
        }
      }
    ]
  })

  tags = {
    manual = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Read-only access to its OWN role so Terraform can refresh/plan the IAM resources.
# Deliberately NO write actions (PutRolePolicy/UpdateRole/...): the CI role cannot rewrite
# its own permissions, so a merged change can't silently escalate it. IAM *changes* therefore
# need a privileged manual `terraform apply`; steady-state plan/apply works with read-only.
resource "aws_iam_role_policy" "publications_infra_iam" {
  name = "publications-infra-iam-read"
  role = aws_iam_role.ghactions_publications_oidc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOwnRoleForTerraform"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:ListRoleTags",
        ]
        Resource = local.oidc_role_arn
      }
    ]
  })
}

# S3 access scoped to the content bucket + the Terraform state bucket only.
resource "aws_iam_role_policy" "publications_s3_scoped" {
  name = "publications-s3-scoped"
  role = aws_iam_role.ghactions_publications_oidc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ContentAndStateBuckets"
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::${local.content_bucket}",
          "arn:aws:s3:::${local.content_bucket}/*",
          "arn:aws:s3:::hl7au-publications-tfstate-ap-southeast-2",
          "arn:aws:s3:::hl7au-publications-tfstate-ap-southeast-2/*",
        ]
      }
    ]
  })
}

# CloudFront management for the infra pipeline (least-privilege actions).
resource "aws_iam_role_policy" "publications_infra_cloudfront" {
  name = "publications-infra-cloudfront"
  role = aws_iam_role.ghactions_publications_oidc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PublicationsInfraCloudFront"
        Effect = "Allow"
        Action = [
          "cloudfront:GetDistribution",
          "cloudfront:GetDistributionConfig",
          "cloudfront:UpdateDistribution",
          "cloudfront:ListTagsForResource",
          "cloudfront:TagResource",
          "cloudfront:UntagResource",
          "cloudfront:GetFunction",
          "cloudfront:DescribeFunction",
          "cloudfront:UpdateFunction",
          "cloudfront:PublishFunction",
          "cloudfront:CreateInvalidation",
        ]
        Resource = "*"
      }
    ]
  })
}
