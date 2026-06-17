# hl7.org.au CloudFront — Terraform

Terraform configuration that adopts the existing production CloudFront distribution
`E2U6NB1JDLY5NT` (serves `hl7.org.au` / `terminology.hl7.org.au`) and its viewer-request
CloudFront Function `fhir-canonical`, which routes canonical FHIR URLs.

The distribution origin is the S3 *website* endpoint `hl7au-fhir-ig.s3-website-ap-southeast-2.amazonaws.com`.
The content bucket and the ACM certificate are **referenced, not managed** here.

## Files
| File | Purpose |
|------|---------|
| `versions.tf` | Terraform/provider versions; S3 backend (commented until the state bucket exists) |
| `providers.tf` | AWS provider |
| `locals.tf` | distribution id, origin, aliases, cert ARN, cache policy, ordered path patterns |
| `main.tf` | `aws_cloudfront_function.fhir_canonical` + `aws_cloudfront_distribution.site` |
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

## Remote state (pending / gated)
State currently lives locally. To move it to the dedicated bucket:
1. Create the bucket (versioning + SSE + public-access-block), e.g.
   `hl7au-publications-tfstate-ap-southeast-2`.
2. Uncomment the `backend "s3"` block in `versions.tf`.
3. `terraform init -migrate-state`.

## Credentials
Resources are global (CloudFront); the provider region is incidental, but the ACM cert is in
`us-east-1` (referenced by ARN). `apply` needs credentials with CloudFront update permissions for
distribution `E2U6NB1JDLY5NT` and function `fhir-canonical`.
