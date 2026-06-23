# Centralized IG build/preview/publish pipeline

The build → preview → gated-publish pipeline now lives **once** as a reusable workflow here in
`publications` (`.github/workflows/build-review-publish.yml`, `on: workflow_call`). Each IG repo
(`au-fhir-base`, `au-fhir-ps`, `au-fhir-core`) keeps only a **thin caller stub** that forwards its
own push/PR/tag/dispatch events to it. This replaces the per-repo copies that had begun to drift.

> See also: [publication-process.md](./publication-process.md) (end-to-end build→preview→publish flow,
> environments/domains, the production-gate process) and [decisions.md](./decisions.md) (why each choice).

## Why centralize

The two per-repo copies (`au-fhir-base`, `au-fhir-ps` on `build-pipeline-redesign`) were ~95%
identical but had already diverged:

- **Preview backend:** au-base → S3; au-ps → GitHub Pages.
- **Preview fidelity:** the "seed history-template assets" + "seed `/fhir/assets`" fixes existed in
  au-base only, so au-ps previews 404'd their history CSS/JS.
- **`package-registry.json`:** au-ps carried + published it; au-base dropped it (web-root file outside
  its `/fhir` sync), so the lean au-base publish never updated the realm registry.

The only *legitimate* per-IG difference is **subtree ownership**, captured by one input.

## The `subtree` parameter

| `subtree` | IG | owns | prod sync |
|-----------|----|------|-----------|
| `""` (default) | au-fhir-base | the `/fhir` **root** (its `package-list.json`, `history.html`, `index.html`) | `out/<mode>/fhir → s3://hl7au-fhir-ig/fhir` (feeds included) |
| `ps` | au-fhir-ps | only `/fhir/ps` | `out/<mode>/fhir/ps → …/fhir/ps` + individual `/fhir` feeds + `/package-registry.json` |
| `core` | au-fhir-core | only `/fhir/core` | same shape as `ps` |

All prod uploads are **additive (never `--delete`)**, and the lean `-web` mirror is seeded from the
**live** prod feeds/registry so each independent publish preserves the sibling IGs' entries.
`package-registry.json` (web-root) is now uploaded by **every** IG (consistency fix vs the old
au-base behavior).

## Caller stubs (add to each IG repo after this merges)

Goes on the **existing `build-pipeline-redesign` branch** of each IG repo, replacing that repo's
`build-review-publish.yml`. Pin `@master` during rollout; pin to a tag once stable.

### `au-fhir-base/.github/workflows/build-review-publish.yml`

```yaml
name: AU Base — build / preview / gated publish
on:
  push: { branches: [master], tags: ['v*'] }
  pull_request: { branches: [master] }
  workflow_dispatch:
    inputs:
      ref: { description: "Tag/branch of au-fhir-base to build", default: master }
      publish_milestone: { description: "Promote MILESTONE to prod (gated)", type: boolean, default: false }
      publish_working:   { description: "Publish WORKING to prod (gated)",   type: boolean, default: false }
permissions: { id-token: write, contents: read }
jobs:
  pipeline:
    uses: hl7au/publications/.github/workflows/build-review-publish.yml@master
    with:
      subtree: ""                                       # owns the /fhir root
      ref: ${{ inputs.ref || '' }}
      publish_milestone: ${{ inputs.publish_milestone || false }}
      publish_working: ${{ inputs.publish_working || false }}
    secrets: inherit
```

### `au-fhir-ps` / `au-fhir-core`

Identical, except `name:`, the `ref` input description, and **`subtree: "ps"`** (or `"core"`).

## Per-repo setup (one-time, manual — cannot be centralized) — ✅ DONE 2026-06-23

GitHub environments are repo-scoped, so the production gate is configured in **each** IG repo. Now
created + verified on all three (reviewers `KyleOps` + `brettesler-ext` + `dt-r`; policies
`branch:master` + `tag:v*`). Full process + the idempotent `gh api` recreate snippet:
[publication-process.md](./publication-process.md#the-production-environment-gate--setup--process).

1. **`production` environment** in `au-fhir-base`, `au-fhir-ps`, `au-fhir-core`. ✅
2. **Required reviewers:** `KyleOps`, `brettesler-ext` (the admin Brett account), `dt-r`. ✅
3. **Deployment branches and tags:** `master` + tag pattern `v*`. ⚠️ The `v*` rule is required —
   a tag-triggered milestone publish is otherwise *rejected*. ✅
4. **OIDC:** the `ghactions_publications_oidc` role trusts `repo:hl7au/*` — no per-repo IAM change. ✅

## Deploy-target state (current — updated 2026-06-23)

| target | CI can write? | notes |
|--------|---------------|-------|
| previews bucket (`hl7au-fhir-ig-previews`) | ✅ | per-branch previews |
| **`previews.hl7.org.au`** | ✅ live | CloudFront `E2V1L6CJ5AQEMV`; `enable_cdn=true` applied |
| **`preprod.hl7.org.au`** | admin-manual | CloudFront `E1U9JOMOLLTC27`; prod mirror + dynamic-publish-box; not a CI target |
| prod (`hl7au-fhir-ig` / `hl7.org.au`) | ✅ gated | `production` env configured — publish jobs now pause for approval (were dormant) |

## Rollout order

1. ✅ Merge the reusable workflow to `publications@master` (PR #4).
2. ✅ Configure the `production` environment in each IG repo (done 2026-06-23).
3. ✅ Caller stub on `build-pipeline-redesign` for au-base + au-ps (au-core: branch pending).
4. ✅ PR-preview confirmed posting S3 URLs; previews live on `previews.hl7.org.au`; no publish runs ungated.
5. ⬜ Once stable, pin the stubs from `@master` to a release tag of this workflow.
6. ⬜ Merge each IG repo's `build-pipeline-redesign` → `master` (au-base PR #1074 pending Brett review).
