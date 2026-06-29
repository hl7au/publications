# AU IG publication process

How an AU FHIR IG (au-fhir-base / au-fhir-core / au-fhir-ps) goes from a commit to a preview and to
production. The logic lives once in the reusable workflow `.github/workflows/build-review-publish.yml`
(here in `publications`); each IG repo calls it via a thin stub. See
[pipeline-centralization.md](./pipeline-centralization.md) for the centralization design and
[decisions.md](./decisions.md) for the rationale behind each choice.

## Triggers (from the per-repo caller stub)

| event | what runs |
|-------|-----------|
| pull request → `master` | build + reviewable .zip; dev preview = HL7 CI (build.fhir.org) |
| push to `master` (merge) | build + **auto-deploy to preprod** (ungated; mode auto-detected) |
| push of a `v*` tag | build + **publish-milestone to PROD** (gated by the `production` env) |
| `workflow_dispatch` | build; optional **publish-working** / **publish-milestone** to prod (gated) |

Developer previews are HL7 International's CI build at
`https://build.fhir.org/ig/<org>/<repo>/branches/<branch>/` (rendered by HL7's own auto-builder, not
this pipeline). Our own S3 preview channel is retained but **off by default** — pass
`enable_s3_preview: true` only when validating our own pipeline/publisher output specifically.

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
| **build.fhir.org** | — (HL7 International) | — | per-branch developer preview, rendered by HL7's auto-builder | HL7 CI (external) |
| **preprod.hl7.org.au** | `E1U9JOMOLLTC27` | `hl7au-fhir-ig-mirror` | prod mirror + dynamic-publish-box; staging validation before a prod release; reuses the `fhir-canonical` function | **CI on merge to master** |
| **hl7.org.au** (prod) | `E2U6NB1JDLY5NT` | `hl7au-fhir-ig` | production | CI, **gated** by the `production` environment (v* tag) |
| previews.hl7.org.au | `E2V1L6CJ5AQEMV` | `hl7au-fhir-ig-previews` | our own per-branch preview, **off by default** (`enable_s3_preview: true`); CachingDisabled; 30-day expiry | CI (opt-in) |

Infra is Terraform in `terraform/cloudfront` (HL7 AWS account `966489602583`, profile `hl7-mgmt`),
the public-domain layer gated by `-var enable_cdn=true`.

## Developer preview (every push / PR)

No deploy from us — the build job posts a link to HL7 International's CI build
(`https://build.fhir.org/ig/<org>/<repo>/branches/<branch>/`) plus the downloadable `site-<slug>`
artifact (the working + milestone renders as one tar.gz). To validate our **own** pipeline/publisher
output (dynamic publish-box, combined jar, canonical behaviour), re-enable the S3 preview with
`enable_s3_preview: true` — it deploys to `https://previews.hl7.org.au/<slug>/{working,milestone}/…`.

## Preprod (auto, on merge to master)

The `deploy-preprod` job runs on every push to `master` (ungated) and syncs the detected build to the
mirror bucket additively, then invalidates the preprod CloudFront. **Milestone vs working is
auto-detected from `status` in `publication-request.json`** (the FHIR-standard signal, see
decisions D13): `release`/`trial-use`/`normative`/`normative+trial-use` → **milestone** (preprod shows
the candidate "current"); `draft`/`ballot`/`preview`/`update`/`ci-build` → **working** (a non-current
versioned snapshot). preprod mirrors prod, so seeding the lean `-web` from live prod is correct here.
Validate at `https://preprod.hl7.org.au/<owned>/<version>/index.html`, then cut the prod release.

## Publishing to prod (gated — the rock-solid path)

`publish-milestone` declares `environment: production`, so it **pauses for a required-reviewer
approval** before any S3 write. Triggered by a **`v*` tag** push (e.g. `git tag v6.1.0 && git push
--tags`). Steps, in order:

1. **Release guard** — fail unless the version is a clean SemVer release (`X.Y.Z`, no `-prerelease`
   suffix) **and** the status is a milestone status (`release`/`trial-use`/`normative`). This blocks
   publishing a `-ci-build`/draft/ballot/preview to prod as "current". Set `version` + `status` in
   `publication-request.json` first, then tag `v<version>`.
2. **Approval** — a `production` reviewer approves the waiting job.
3. **Publish** — `aws s3 sync out/milestone/<owned>` to prod (additive) + the shared root files +
   `package-registry.json`. With the dynamic publish-box there are **no rewritten old-version files**.
4. **CloudFront invalidation** (`/*` on the prod distribution).
5. **Post-publish verify** — fail the run if the new version page and the canonical "current" page
   aren't returning 200 on `hl7.org.au` (retried).

`publish-working` (dispatch with `publish_working=true`, gated) publishes a non-current versioned
snapshot the same way (sync + invalidate + verify), without touching the current landing or old versions.

### Cut a production release (checklist)
1. In the IG repo, set `publication-request.json` `version` = `X.Y.Z` (clean) and `status` =
   `trial-use` (or `release`/`normative`); update `desc`/`sequence`. Open a PR, merge to `master`.
2. The merge auto-deploys to **preprod** as a milestone — validate `https://preprod.hl7.org.au/<owned>/`.
3. Tag the release: `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. Approve the **production** environment prompt on the Actions run.
5. The run publishes, invalidates, and verifies prod automatically.

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
