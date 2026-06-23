# AU IG publication process

How an AU FHIR IG (au-fhir-base / au-fhir-core / au-fhir-ps) goes from a commit to a preview and to
production. The logic lives once in the reusable workflow `.github/workflows/build-review-publish.yml`
(here in `publications`); each IG repo calls it via a thin stub. See
[pipeline-centralization.md](./pipeline-centralization.md) for the centralization design and
[decisions.md](./decisions.md) for the rationale behind each choice.

## Triggers (from the per-repo caller stub)

| event | what runs |
|-------|-----------|
| push to `master` | build + previews (no prod publish) |
| pull request → `master` | build + previews (per-PR) |
| push of a `v*` tag | build + previews + **publish-milestone** (gated) |
| `workflow_dispatch` | build + previews; optional **publish-working** or **publish-milestone** (gated) |

## The build (one job, in the `hl7fhir/ig-publisher-base` container)

1. Checkout the IG source + `publish-setup.json`/`templates` (from `publications@master`) + the HL7
   history template + the `hl7au/ig-registry`.
2. Fetch the combined IG Publisher jar (KyleOps fork) — **cached by release ETag** (see decisions D2/D4).
3. Restore caches: FHIR package cache (`.fhir-cache`) and terminology cache (`input-cache/txcache`).
4. **Render once** — `publisher.jar -ig . -publish <PUBPATH>`. This is the only full render; it includes
   cross-version comparison (per each IG's `version-comparison-master`; always on — decisions D5).
5. **go-publish twice with `-reuse-build`** (adopts the single render, ~100s each) into a **lean `-web`**
   seeded only with the owned `package-list.json` + shared root files pulled from **live prod**:
   - `mode=working` → the new version as a non-current build
   - `mode=milestone` → the same version promoted to "current"
6. Tar both into one `preview-<slug>.tar.gz` artifact.

`subtree` decides what each IG owns: `""` = au-base owns the `/fhir` root; `ps`/`core` own only
`/fhir/<subtree>`. All prod uploads are **additive (never `--delete`)**.

## Environments & domains

| host | CloudFront | bucket | purpose | who writes |
|------|-----------|--------|---------|-----------|
| **previews.hl7.org.au** | `E2V1L6CJ5AQEMV` | `hl7au-fhir-ig-previews` | per-branch working+milestone previews, path `/<slug>/{working,milestone}/fhir/…`; CachingDisabled; 30-day expiry | **CI** (every push/PR) |
| **preprod.hl7.org.au** | `E1U9JOMOLLTC27` | `hl7au-fhir-ig-mirror` | prod mirror + dynamic-publish-box; full validation / migration review; reuses the `fhir-canonical` function | admin (S3→S3 sync; not CI) |
| **hl7.org.au** (prod) | `E2U6NB1JDLY5NT` | `hl7au-fhir-ig` | production | CI, **gated** by the `production` environment |

Infra is Terraform in `terraform/cloudfront` (HL7 AWS account `966489602583`, profile `hl7-mgmt`),
the public-domain layer gated by `-var enable_cdn=true`.

## Preview flow (every push / PR)

The `preview-s3` job downloads the artifact, seeds the history-template assets + preview-only redirects,
assumes the OIDC role, and `aws s3 sync`s to `s3://hl7au-fhir-ig-previews/<slug>/`
(`max_concurrent_requests=64` → ~2.5 min; decisions D8). Reviewers open:

```
https://previews.hl7.org.au/<slug>/working/fhir/<version>/index.html
https://previews.hl7.org.au/<slug>/milestone/fhir/<version>/index.html
```

The dynamic publish-box resolves against the preview's own `package-list.json` (same-origin); baked
absolute `hl7.org.au` canonicals resolve to prod. Cross-version comparison is present in both previews.

## Publishing to prod (gated)

Both prod jobs declare `environment: production`, so they **pause for a required-reviewer approval**
before any S3 write.

- **Milestone (becomes current):** push a `v*` tag (or dispatch with `publish_milestone=true`).
  `publish-milestone` syncs `out/milestone/<owned>` to prod (additive) + the shared root files.
- **Working (versioned snapshot, NOT current):** dispatch with `publish_working=true`.
  `publish-working` syncs `out/working/<owned>` (does not touch the current landing or old versions).

With the dynamic publish-box there are **no rewritten old-version files** — a publish only adds the new
version dir + regenerates the owned-path root (history, package-list, redirects).

## The `production` environment gate — setup & process

GitHub environments are **repo-scoped**, so `production` must exist in **each** IG repo (it cannot be
centralized). Current config (created + verified on au-fhir-base, au-fhir-core, au-fhir-ps):

- **Required reviewers:** `KyleOps`, `brettesler-ext`, `dt-r` (≥1 must approve each prod publish).
- **Deployment branches and tags:** `master` **+ tag pattern `v*`**. ⚠️ The `v*` rule is required —
  a tag-triggered milestone publish is otherwise rejected (a tag ref isn't `master`).
- **OIDC:** the `ghactions_publications_oidc` role trusts `repo:hl7au/*` — no per-repo IAM change.

**Approval at publish time:** when a `v*` tag (or a `publish_*` dispatch) runs, the publish job shows
"Waiting" in the Actions run; a reviewer approves from the run page (or the repo's Environments tab) and
the job proceeds. Previews never gate.

**Re-create / change reviewers** (idempotent), per repo:

```bash
# PUT the environment with reviewers + custom branch/tag policies, then add master + v* policies.
gh api --method PUT repos/hl7au/<repo>/environments/production --input - <<'JSON'
{ "reviewers": [ {"type":"User","id":10165817}, {"type":"User","id":6062644}, {"type":"User","id":116611317} ],
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true } }
JSON
gh api --method POST repos/hl7au/<repo>/environments/production/deployment-branch-policies -f name='master' -f type='branch'
gh api --method POST repos/hl7au/<repo>/environments/production/deployment-branch-policies -f name='v*' -f type='tag'
```

IDs: `KyleOps`=10165817, `brettesler-ext`=6062644, `dt-r`=116611317.

## Local iteration

`scripts/local-build.sh` (in each IG repo) does a fast host-JDK QA render with the same combined jar,
a clean `output/`, and warm package + terminology caches — for tight error/warning iteration without CI.
`scripts/local-publish.sh` reproduces a full go-publish in the container when you need to verify the
publish step itself.
