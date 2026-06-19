# HL7 AU Publications

Central **publishing configuration and serving infrastructure** for the HL7 AU FHIR
Implementation Guides. This repository is **not an IG** — it contains no FHIR profiles.
Its job is to define how the per-IG renders are stitched into the combined, multi-IG,
multi-version website served at **https://hl7.org.au/fhir**, and how/where that site is hosted.

The actual IG content lives in the per-IG repos (`hl7au/au-fhir-base`, `hl7au/au-fhir-core`,
`hl7au/au-fhir-ps`, …). Those repos now **own their own build pipelines**; this repo provides the
shared `-go-publish` configuration, the page chrome, and the serving stack.

## What this repo provides

| Path | Purpose | Consumed by |
|------|---------|-------------|
| `publish-setup.json` | Master `-go-publish` config: website settings (`server: cloud`, `dynamic-publish-box`), package/publication feeds, and **layout-rules** mapping each IG's npm id + canonical to its path under `/fhir`. | IG pipelines (sparse checkout) |
| `templates/` | HTML chrome (`header`/`preamble`/`postamble`) wrapped around published pages. | IG pipelines (sparse checkout) |
| `_updatePublisher.sh` / `.bat` | Downloads the latest `publisher.jar` into `input-cache/`. | au-fhir-core legacy pipeline (transitional, see below) |
| `terraform/cloudfront/` | The stack that serves the site (CloudFront + `fhir-canonical` function, content-bucket settings, OIDC role). | `infra.yml` |
| `.github/workflows/infra.yml` | Terraform CI: plan on PRs touching `terraform/**`, apply on `master`. | — |

Layout-rules in `publish-setup.json`:

| npm id | canonical | path |
|--------|-----------|------|
| `hl7.fhir.au.base` | `http://hl7.org.au/fhir`      | `/fhir`      |
| `hl7.fhir.au.core` | `http://hl7.org.au/fhir/core` | `/fhir/core` |
| `hl7.fhir.au.ps`   | `http://hl7.org.au/fhir/ps`   | `/fhir/ps`   |
| `hl7.fhir.au.ereq` | `http://hl7.org.au/fhir/ereq` | `/fhir/ereq` |

## How publishing works (current model)

Publishing is driven **from each IG repo**, not from here. The redesigned pipeline
(`build-review-publish.yml`, in `au-fhir-base` and `au-fhir-ps`) does a **lean build**:

1. Renders the IG **once** in publication mode.
2. Runs `-go-publish` **twice off that single render** (`-reuse-build`) to produce both a
   **working** preview (new version as a non-current snapshot) and a **milestone** preview (the
   same version promoted to current). `dynamic-publish-box` means old versions are never rewritten,
   so no full version-tree sync is needed.
3. Deploys both previews side-by-side to GitHub Pages for review (zero prod writes).
4. Gated by the `production` environment, does an **additive** S3 sync to `s3://hl7au-fhir-ig`
   (never `--delete`): milestone publish on a `v*` tag, working publish on explicit dispatch.

That pipeline consumes this repo via a **sparse checkout of `publish-setup.json` + `templates/`** —
nothing else. History (`HL7/fhir-ig-history-template`) and registry (`hl7au/ig-registry`) are
checked out directly by the pipeline.

> **Transitional state.** While the supporting changes are unmerged, the IG pipelines point at a
> temporary fork/branch and a combined custom publisher jar:
> - `PUBLICATIONS_REPO=KyleOps/publications`, `PUBLICATIONS_REF=au-pipeline-config` — revert to
>   `hl7au/publications` (default branch) once this repo's config is merged.
> - combined jar from `KyleOps/fhir-ig-publisher@au-pipeline-combined` — revert to
>   `_updatePublisher.sh -f -y` once the opt-in publisher features ship in a release.
>
> **`au-fhir-core` is not yet migrated.** It still publishes via its own `profile_tag_trigger_publication.yml`,
> which checks out *this whole repo* and uses `_updatePublisher.sh` + `templates/` directly. Keep
> `_updatePublisher.*` until core moves to the new pipeline.

## Serving infrastructure (`terraform/cloudfront/`)

Terraform manages the stack that serves the site (see `terraform/cloudfront/README.md`):
the CloudFront distribution + the `fhir-canonical` routing function, the `hl7au-fhir-ig` content
bucket's **settings** (not its objects), and the `ghactions_publications_oidc` OIDC role. State is
in `s3://hl7au-publications-tfstate-ap-southeast-2`.

## Build scratch (generated, git-ignored)

A local or CI publish run clones/generates these — none are committed:
`input-cache/` (`publisher.jar`) · `hl7au/` (checked-out IGs) · `ig-registry/` ·
`ig-history/` / `fhir-history/` · `webroot/` (assembled site) · `temp/`.

> Per-IG local builds are run from **inside each IG repo** using that repo's own
> `_genonce.sh` / `_gencontinuous.sh`. The old root-level `go-publish.sh` / `_genonce.*` /
> `_gencontinuous.*` orchestration scripts were removed — they were superseded by the
> in-repo `build-review-publish.yml` pipelines and were not used by any CI.
