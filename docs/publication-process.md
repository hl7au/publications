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
| push to `master` | build + reviewable .zip only (CI validation; no deploy) |
| **GitHub release** (published) | build + **deploy to preprod** (ungated; mode auto-detected from `status`) |
| `workflow_dispatch` | build; optional **deploy to preprod** (`deploy_preprod: true`) for on-demand branch staging |

Publication/release branches are **never merged to master** (master = CI build). A release targets the
release branch and carries that release's `publication-request.json`, IG versions/labels, and change
logs. **Prod is not published from the IG repos** — promotion to prod is a separate manual step run
from the **publications** repo (see [Promoting to prod](#promoting-to-prod-manual-hl7-au-only)), so HL7
AU controls who can release.

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

## Quality gate (automated, every build)

The last build step reads the publisher's structured QA summary (`output/qa.json`) and writes an
**errors / warnings / hints** table to the run summary on **every** trigger (PR, push, release). When
the caller stub sets a threshold it also **fails the build**, so a change that introduces new problems
is caught without anyone opening `qa.html`:

- `qa_max_errors` — fail if validation **errors** exceed this. Set it to the IG's *current* error count
  so the gate blocks **regressions** (a new error) while today's known issues don't wall off every PR;
  ratchet it **down** as errors are fixed. Current baselines: **au-fhir-core = 4**, **au-fhir-ps = 8**,
  **au-fhir-base = advisory** (`-1`, set the number after the first CI build reports it).
- `qa_max_warnings` — same, for **warnings**. Advisory (`-1`) by default (AU IGs carry many warnings).
- `-1` on either = **advisory**: report the counts, never fail.

Because the gate fails the whole `build` job, a regressed **release** never reaches preprod
(`deploy-preprod` needs `build`). The gate runs *after* the artifact upload, so `qa.html` is still in
the `site-*` artifact to diagnose a failure. If a new error is intentional, raise the stub threshold.

## Environments & domains

| host | CloudFront | bucket | purpose | who writes |
|------|-----------|--------|---------|-----------|
| **build.fhir.org** | — (HL7 International) | — | per-branch developer preview, rendered by HL7's auto-builder | HL7 CI (external) |
| **preprod.hl7.org.au** | `E1U9JOMOLLTC27` | `hl7au-fhir-ig-mirror` | prod mirror + dynamic-publish-box; staging validation before a prod release; reuses the `fhir-canonical` function | **CI on a GitHub release** (or `deploy_preprod` dispatch) |
| **hl7.org.au** (prod) | `E2U6NB1JDLY5NT` | `hl7au-fhir-ig` | production | **manual promote-prod.yml in publications** (aws s3 sync preprod→prod), gated by the publications `production` env |
| previews.hl7.org.au | `E2V1L6CJ5AQEMV` | `hl7au-fhir-ig-previews` | our own per-branch preview, **off by default** (`enable_s3_preview: true`); CachingDisabled; 30-day expiry | CI (opt-in) |

Infra is Terraform in `terraform/cloudfront` (HL7 AWS account `966489602583`, profile `hl7-mgmt`),
the public-domain layer gated by `-var enable_cdn=true`.

## Developer preview (every push / PR)

No deploy from us — the build job posts a link to HL7 International's CI build
(`https://build.fhir.org/ig/<org>/<repo>/branches/<branch>/`) plus the downloadable `site-<slug>`
artifact (the working + milestone renders as one tar.gz). To validate our **own** pipeline/publisher
output (dynamic publish-box, combined jar, canonical behaviour), re-enable the S3 preview with
`enable_s3_preview: true` — it deploys to `https://previews.hl7.org.au/<slug>/{working,milestone}/…`.

## Preprod (on a GitHub release)

The `deploy-preprod` job runs when the IG publishes a **GitHub release** (ungated) and syncs the
detected build to the mirror bucket additively, then invalidates the preprod CloudFront. A release
targets the **publication/release branch** (never merged to master); publishing the release is the
staging act. It also runs on a `deploy_preprod: true` dispatch for on-demand branch staging before the
release is cut. **Milestone vs working is auto-detected from `status` in `publication-request.json`**
(the FHIR-standard signal, see decisions D13): `release`/`trial-use`/`normative`/`normative+trial-use`
→ **milestone** (preprod shows the candidate "current"); `draft`/`ballot`/`preview`/`update`/`ci-build`
→ **working** (a non-current versioned snapshot). preprod mirrors prod, so seeding the lean `-web` from
live prod is correct here. The report warns if the release **tag** does not match the
`publication-request.json` version (a guard against releasing the wrong commit). Validate at
`https://preprod.hl7.org.au/<owned>/<version>/index.html`, then promote to prod.

## Promoting to prod (manual, HL7 AU only)

Prod is **not** published from the IG repos. Promotion is a manual workflow in **this** repo,
`.github/workflows/promote-prod.yml` (Actions → **"Promote preprod → prod"**), so HL7 AU controls who
can release: it is gated by a per-IG `production-<ig>` environment (required reviewers) and only
runnable by someone with access to publications. An IG-repo contributor cannot reach prod.

It **does not rebuild** — it `aws s3 sync`s the already-reviewed preprod content to prod, **scoped to
the released IG**, additive (never `--delete`), the classic "sync approved staging to production" model.
Inputs: `ig` (au-fhir-base / au-fhir-core / au-fhir-ps) and `version`. Steps, in order:

1. **Approval** — a `production` reviewer approves the waiting job.
2. **Guard** — fail unless the `version` is actually staged on preprod (`s3://…-mirror/<owned>/<version>/`).
3. **Scoped sync** preprod → prod:
   - **au-base** (root owner): `aws s3 sync …-mirror/fhir …-ig/fhir` **excluding** the `core/*` and
     `ps/*` subtrees (preprod is a full mirror, so a base promotion must not drag the siblings along).
   - **au-core / au-ps** (subtree owners): sync `/fhir/<subtree>` plus the shared `/fhir` feeds
     (`package-feed.xml`, `publication-feed.xml`) they read-modify-wrote during the staged build.
   - every IG: promote the web-root `package-registry.json`.
4. **CloudFront invalidation** (`/*` on the prod distribution).
5. **Post-publish verify** — fail the run unless the new version page and the owned-path current landing
   return 200 on `hl7.org.au` (retried).

> ⚠️ **Adding a new subtree IG:** add its `--exclude` to the au-base branch of the sync (so a base
> promotion doesn't touch it) and a `case` entry in the IG → owned-path map.

> ℹ️ **IAM prerequisite:** the `ghactions_publications_oidc` role must be allowed to read the preprod
> bucket and write the prod bucket. If a promote run fails with `AccessDenied`, grant the prod-bucket
> `PutObject` + preprod-bucket `Get`/`List` on that role.

### Cut a production release (checklist)
1. On the **release branch** (not master), set `publication-request.json` `version` = `X.Y.Z` and
   `status` = `trial-use` (or `release`/`normative` for a milestone; `draft`/`ballot`/`preview` for a
   working snapshot); update `desc`/`sequence` and the change log.
2. **Create a GitHub release** of the IG targeting the release branch. This builds + deploys to
   **preprod** with the auto-detected mode — validate `https://preprod.hl7.org.au/<owned>/<version>/`.
3. In **publications** → Actions → **"Promote preprod → prod"**, run with `ig` = the IG and `version` =
   `X.Y.Z`.
4. Approve the **`production-<ig>`** environment prompt on that run.
5. The run syncs preprod → prod (scoped), invalidates, and verifies prod.

## The `production-<ig>` environment gates — setup & process

Prod promotion runs from the **publications** repo, and the gate is a **per-IG** environment
(`production-au-fhir-base`, `production-au-fhir-core`, `production-au-fhir-ps`), so each IG has its own
approval gate and its own deployment-history lane — the Environments page reads correctly as
"au-fhir-ps 1.0.0 deployed Tuesday, au-fhir-base 6.1.0 deployed today". `promote-prod.yml` selects the
environment from the `ig` input (`environment: production-${{ inputs.ig }}`). Config, per environment:

- **Required reviewers:** `KyleOps`, `brettesler-ext`, `dt-r` (≥1 must approve each promotion) — HL7 AU.
- **Deployment branches:** `master` (the promote workflow is a `workflow_dispatch` on publications
  master). No tag rule is needed — promotion is not tag-triggered.
- **OIDC:** the `ghactions_publications_oidc` role trusts `repo:hl7au/*`; it must be able to read the
  preprod bucket and write the prod bucket (see the IAM note above).

> ⚠️ **Pre-create every `production-<ig>` environment with reviewers.** If the workflow references an
> environment that does not exist yet, GitHub creates it on the fly WITHOUT protection rules — i.e. the
> approval gate is silently skipped for that IG. Run the setup for all three before the first promotion.

**Approval at promote time:** when "Promote preprod → prod" runs, the `promote` job shows "Waiting" in
the Actions run; a reviewer approves from the run page (or the repo's Environments tab) and the job
proceeds. Preprod deploys never gate.

**Create / change reviewers** (idempotent), in publications — run once per IG:

```bash
for ig in au-fhir-base au-fhir-core au-fhir-ps; do
  gh api --method PUT "repos/hl7au/publications/environments/production-$ig" --input - <<'JSON'
{ "reviewers": [ {"type":"User","id":10165817}, {"type":"User","id":6062644}, {"type":"User","id":116611317} ],
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true } }
JSON
  gh api --method POST "repos/hl7au/publications/environments/production-$ig/deployment-branch-policies" -f name='master' -f type='branch'
done
```

IDs: `KyleOps`=10165817, `brettesler-ext`=6062644, `dt-r`=116611317.

> The per-IG `production` environments in the IG repos (from the old tag-triggered flow) are now unused
> (prod is no longer published from the IG repos). They can be left in place or removed.

## Local iteration

`scripts/local-build.sh` (in each IG repo) does a fast host-JDK QA render with the same combined jar,
a clean `output/`, and warm package + terminology caches — for tight error/warning iteration without CI.
`scripts/local-publish.sh` reproduces a full go-publish in the container when you need to verify the
publish step itself.
