# hl7.org.au CloudFront — Terraform

Terraform configuration that adopts the existing production CloudFront distribution
`E2U6NB1JDLY5NT` (serves `hl7.org.au` / `terminology.hl7.org.au`) and its viewer-request
CloudFront Function `fhir-canonical`, which routes canonical FHIR URLs.

The distribution origin is the S3 *website* endpoint `hl7au-fhir-ig.s3-website-ap-southeast-2.amazonaws.com`.
The ACM certificate is **referenced, not managed** here.

The content bucket's **settings** are managed (see `bucket.tf`); its **objects are not** — published
IG content is written by the publish pipeline and the canonical-redirect backfill, never by Terraform.
Encryption is left unmanaged (S3 default AES256). The bucket carries `prevent_destroy = true`.

## Files
| File | Purpose |
|------|---------|
| `versions.tf` | Terraform/provider versions; S3 backend (commented until the state bucket exists) |
| `providers.tf` | AWS provider |
| `locals.tf` | distribution id, origin, aliases, cert ARN, cache policy, ordered path patterns |
| `main.tf` | `aws_cloudfront_function.fhir_canonical` + `aws_cloudfront_distribution.site` |
| `bucket.tf` | content-bucket settings: bucket, website config, versioning, public-access-block, ownership, policy |
| `fhir-canonical.js` | function source — **source of truth** for the routing logic |

## What the function does
- unversioned conformance canonicals (`CapabilityStatement`/`StructureDefinition`/`ValueSet`/`CodeSystem`)
  → `/<base>/<RT>-<id>.html` (current version at the canonical root)
- **versioned canonicals** `<RT>/<id>|<version>` (raw `|` or `%7C`) → `/<base>/<version>/<RT>-<id>.html`
  (and `/<base>/<version>/index.html` for `ImplementationGuide`)
- `terminology.hl7.org.au/<type>/<id>` → cross-host redirect to `hl7.org.au/fhir/...`
- everything else → directory `index.html` (static redirect stubs published by the IG publisher)

## First-time setup (already done; recorded for reproducibility)
```bash
tfenv install            # honours .terraform-version (>= 1.10)
terraform init           # local state during reconciliation
# import the existing resources (state-only, no AWS changes):
terraform import aws_cloudfront_function.fhir_canonical fhir-canonical
terraform import aws_cloudfront_distribution.site E2U6NB1JDLY5NT
terraform plan           # reconciled to zero-diff for the distribution
```

Note: importing a CloudFront function always shows a one-time `+ publish = true` on the first
plan (`publish` is a Terraform action flag, not an API-readable field). The function code/runtime
match on import — it is not infrastructure drift, and a single apply clears it.

## Making a change
1. Edit `fhir-canonical.js` (and/or `main.tf`).
2. `terraform plan` — review. A function-only change shows a single in-place update of
   `aws_cloudfront_function.fhir_canonical`.
3. `terraform apply` — publishes the new function version; CloudFront serves it from the LIVE stage
   immediately (the distribution association already points at LIVE).

## CI pipeline
`.github/workflows/infra.yml` runs Terraform on changes under `terraform/**`:
- **PR** → `fmt`/`init`/`validate`/`plan` (plan shown in the job summary) — review before merge.
- **push to `master`** → `apply`.
- **manual dispatch** → `plan` or `apply` on demand.

It authenticates via GitHub OIDC as `ghactions_publications_oidc` (same role as the publish
workflow). The pipeline **requires the remote backend** (below) to be live, or each run starts
with empty state.

## Bootstrap — remote state + IAM (one-time, gated)
State currently lives locally. Before the pipeline can work:
1. Create the dedicated state bucket (versioning + SSE + public-access-block), e.g.
   `hl7au-publications-tfstate-ap-southeast-2`.
2. Uncomment the `backend "s3"` block in `versions.tf`.
3. `terraform init -migrate-state` (moves the current local state to S3).
4. Extend the `ghactions_publications_oidc` role with the permissions below.

### Required IAM permissions (added to the reused OIDC role)
- CloudFront: `GetDistribution*`, `UpdateDistribution`, `GetFunction`, `DescribeFunction`,
  `UpdateFunction`, `PublishFunction` (and `CreateInvalidation` if ever needed).
- S3 content bucket settings (`arn:aws:s3:::hl7au-fhir-ig`): `GetBucket*`/`PutBucket*`,
  `GetBucketPolicy`/`PutBucketPolicy`, `Get/PutBucketVersioning`, `Get/PutBucketPublicAccessBlock`,
  `Get/PutBucketOwnershipControls`, `Get/PutBucketWebsite`.
- State bucket: `s3:ListBucket` on the bucket and `s3:GetObject`/`PutObject`/`DeleteObject` on
  `cloudfront/terraform.tfstate` (+ the `.tflock` lock object for native locking).

## Credentials
Resources are global (CloudFront); the provider region is incidental, but the ACM cert is in
`us-east-1` (referenced by ARN). `apply` needs the permissions above.
