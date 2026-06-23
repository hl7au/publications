# AU IG pipeline — decision log

Key decisions for the AU FHIR IG build/preview/publish tooling (au-fhir-base, au-fhir-core,
au-fhir-ps), with rationale and evidence. Newest first. See also
[pipeline-centralization.md](./pipeline-centralization.md) and
[publication-process.md](./publication-process.md).

## D1 — Centralize the pipeline as one reusable workflow
The build → preview → gated-publish logic lives once in `publications/.github/workflows/build-review-publish.yml`
(`on: workflow_call`); each IG repo carries a thin caller stub. The per-repo copies had drifted (S3 vs
Pages previews, history-asset seeding present in only one, inconsistent `package-registry.json`). The only
legitimate per-IG difference is **subtree ownership**, captured by one `subtree` input. Details:
pipeline-centralization.md.

## D2 — Use a forked combined IG Publisher jar (opt-in, additive, synced)
Pipelines reference a combined jar from the `hl7au` fork of `HL7/fhir-ig-publisher`, built from four
opt-in upstream PRs, **only until each is merged or closed** upstream — then revert to the released jar.
The fork is kept continuously synced with upstream (no drift) and **all features are opt-in + additive**
(default behaviour identical to stock).
- **#1327** — cloud/static-hosting redirects (emit real HTML; wire CLOUD into go-publish)
- **#1328** — opt-in `-reuse-build` for go-publish (skip the redundant re-render)
- **#1330** — opt-in dynamic publish-box (client-side current-version + page-versions; zero-churn milestones)
- **#1331** — resolve cross-namespace canonicals (URL last segment ≠ resource id)

## D3 — Lean build: render once, reuse for both previews
Render the IG **once** (`-ig . -publish`), then run go-publish **twice** with `-reuse-build`
(mode=working, mode=milestone) into a **lean `-web`** seeded with only the owned `package-list.json` +
the shared root files (feeds, registry) pulled from **live prod**. The 2nd go-publish is ~100s, not a
re-render. Verified the lean `-web` loses nothing (see D5).

## D4 — Caching: publisher.jar (ETag) + terminology cache
- Cache the ~211 MB combined jar keyed on the release asset **ETag** (resolved after the redirect;
  falls back to a plain download if unresolved — no stale-jar trap). Was re-downloaded every run.
- Persist `input-cache/txcache` (the terminology cache the AU template sets via `path-tx-cache`) across
  runs. Terminology validation is the dominant build phase. **Measured: cold ~6 min → warm ~5 min build;
  validation ~3:17 → ~3:05.**
- The FHIR package cache (`.fhir-cache`) was already cached; kept as-is.

## D5 — Cross-version comparison: always on
Comparison renders on **every** build (not gated to milestones). **Measured cost on the current jar:
~10 s and 0 errors/0 warnings/0 broken links** — the old "slow/noisy" reputation was a stale 2.0.x jar +
a stale `comparison-v*` output dir, both eliminated. So the diff is available in both the working and
milestone previews as a review aid. **Verified the lean build's comparison is byte-identical to a full
render** (1291 files): comparison content is loaded from the prior **npm package** (not the `-web` tree),
go-publish never re-runs it, and `-reuse-build` adopts it wholesale; output lands at
`fhir/<ver>/comparison-v<prev>/` (and is promoted to `fhir/comparison-v<prev>/` for a milestone),
inside the `fhir`-scoped sync. Matches prod's `hl7.org.au/fhir/comparison-v5.0.0/`.

## D6 — `pin-canonicals = pin-multiples` in every IG
The FHIR Extensions Pack ships multiple versions of standard extensions, so bare references are
ambiguous and emit "multiple potential matches" warnings. `pin-multiples` pins **only the ambiguous**
references to the version the publisher already selects (mostly Extensions Pack `5.3.0`) — a WARN→INFO
("Pinned … from choices of …") with **no semantic change** (re-evaluated each build; source files
untouched). `pin-all` (pin everything) was rejected as too noisy. **Verified: warnings au-base 82→2,
au-ps 50→31, au-core 177→153.** The underlying dual 5.2.0/5.3.0 transitive load is upstream/transitive;
the root-fix (PR/own-build the deps) was **skipped** in favour of pinning.

## D7 — `ignoreWarnings.txt` refresh (au-base) + errors are NOT suppressible
Refreshed au-base suppressions (corrected the `au-endpoint-payload-type` URL; added RCPA SPIA
experimental ×4, au-hae, WHO ATC/ABS, MIMS/PBS expansion; `%wildcards%` where the IG version drifts;
removed the dead `WARNING 16` block superseded by D6). **Key constraint:** `ignoreWarnings.txt` filters
**non-errors only** (verified `ValidationPresenter.filterMessages`), so the remaining errors can't be
suppressed — they need real fixes: `dynamic-source-viewers` (register the code in the fork jar),
content-less MIMS/PBS example codes (accepted), and au-ps IPS profile-compliance errors (WG/author).

## D8 — Faster S3 uploads (concurrency 64)
The preview pushes two full IG sites (~10k+ small files) and was request-rate bound at the aws-cli
default concurrency of 10 (~12 min). Set `default.s3.max_concurrent_requests=64` before the preview sync
and both prod publish steps. **Measured: preview deploy 12m22s → 2m22s** (now faster than the old Pages
flow). s5cmd was considered and **held off** (concurrency bump alone sufficed; no new dependency).

## D9 — Two new public hosts (previews + preprod), additive
Created `previews.hl7.org.au` and `preprod.hl7.org.au` under `hl7.org.au` in the HL7 AWS account
(966489602583 / profile `hl7-mgmt`) via Terraform (`terraform/cloudfront`, gated by `enable_cdn`).
**Additive only — 11 added, 0 changed, 0 destroyed; prod distribution untouched.**
- **previews** (CF `E2V1L6CJ5AQEMV`): per-branch CI previews, CachingDisabled (instant freshness),
  no canonical function, 30-day object expiry. CI-writable.
- **preprod** (CF `E1U9JOMOLLTC27`): prod mirror + dynamic-publish-box migration applied; reuses the
  prod `fhir-canonical` function. Full-validation / migration-review env; admin-managed (not CI).

## D10 — Prod gate = a per-repo GitHub `production` environment
GitHub environments are repo-scoped, so the gate can't be centralized. Created `production` in all three
IG repos: required reviewers **KyleOps + brettesler-ext + dt-r**, deployment policies **`master` +
tag `v*`** (the `v*` rule is required or tag-triggered milestone publishes are rejected). Previews are
ungated; only prod publish pauses for a human approval. Set up idempotently via `gh api`.

## D11 — Prod migration deferred
The full 27-version prod migration (apply dynamic-publish-box to all historical versions, fixing live
page-version errors) is **deferred** — the corrected content already lives on the preprod mirror, so it's
a flip when ready. Optional backfill flagged to Brett.
