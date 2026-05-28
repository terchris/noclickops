# PLAN-007: `add-service` — trigger the Copier add-service pipeline

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-28

**Goal**: One command to kick off the Copier-based add-service pipeline that scaffolds a new service folder, opens its PR, and creates its CD pipeline. Replace clicking through the ADO Pipelines tab to run `<repo>-add-service` and fill in parameters.

**Last Updated**: 2026-05-28

**Investigations**:

- [INVESTIGATE-noclickops.md](../backlog/INVESTIGATE-noclickops.md) → "Outline of v1 PLANs" → PLAN-007

**Depends on**: PLAN-001 (lib/), PLAN-003 (`lib/azdo.sh` reuse), PLAN-004 (the `az pipelines run` + `--watch` pattern).

**Priority**: Medium-high — used once per new service; less frequent than deploy but high-stakes (the pipeline is what makes services in the platform sense).

---

## Pipeline contract (verified against `JKL900X016-NerdMeet/.pipelines/add-service.yaml`)

The target-repo pipeline is named `<AZDO_REPO>-add-service` and accepts three parameters:

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `serviceName` | string | `NRXService` | The new service folder name. If `public_endpoint=true`, also becomes the subdomain. |
| `persistent_storage` | string `'true'`/`'false'` | `'false'` | Whether to provision Azure Files for the service. |
| `public_endpoint` | string `'true'`/`'false'` | `'true'` | Whether the service is exposed via Front Door. |

The pipeline:

1. Runs Copier against the `copier-add-service` template repo.
2. Creates branch `add-service-<serviceName>`.
3. Opens PR `Add service <serviceName>` to `main`.
4. Creates the `<AZDO_REPO>-<serviceName>-CD` pipeline (skip-first-run; default branch reconfigured to `main` post-creation).

Same `az pipelines run` mechanism as PLAN-004's `deploy`.

---

## What it delivers

### `bin/add-service.{sh,ps1}`

```text
noclickops add-service <service-name> [--persistent-storage] [--no-public-endpoint] [--watch]
```

Behaviour:

- Validates `<service-name>` shape: non-empty, no whitespace, no path separators, no leading dash (so it can't be mis-parsed as a flag), max 50 chars. (No casing or format opinions — existing FRT services span `PdfConverter`, `test-holderdeord`, `WebappPython`.)
- **Refuses to run if `services/<name>` already exists** in the target repo — catches the most common typo (re-adding an existing service) cheaply before the pipeline.
- Derives `AZDO_REPO` via `lib/azdo.sh`; composes pipeline name `<AZDO_REPO>-add-service`.
- Triggers `az pipelines run` with all three parameters (`serviceName`, `persistent_storage`, `public_endpoint`), defaults matching the pipeline's own defaults so callers only need to specify what they want different.
- Prints run id + build-results URL.
- `--watch`: polls every 20s up to ~30 min (same loop as `deploy`).
- On success (or even on "started without --watch"): prints the next-step hint — wait for the PR, review it, merge with `noclickops merge-pr <id>`, then customise the service.

### What this PLAN does NOT do

- **Doesn't open or merge the PR**. The pipeline does that itself. After noclickops add-service, the developer goes to ADO (or `noclickops merge-pr <id>` once they know the id) to merge.
- **Doesn't customise the service content** — that's `clean-sample` + `sync-lovable` (PLAN-005/006) work, on the branch the pipeline created.
- **Doesn't trigger the first CD run**. The pipeline runs `--skip-first-run` when it creates the CD pipeline; the developer triggers test deploys explicitly via `noclickops deploy <name> test` once the PR is merged.

---

## Phases

1. `bin/add-service.{sh,ps1}` — full implementation.
2. `tests/test-PLAN-007-add-service.sh` — captures the smoke tests.
3. Smoke test locally; commit; update tests/README.md if needed (auto-discovered, so no change required).

---

## Validation criteria

- `--help` prints the metadata block with the full parameter set.
- Lister now shows `add-service` alongside `clean-sample` + `sync-lovable` in the "Service lifecycle" section.
- All input-validation errors fire pre-`az`.
- `services/<name>` already exists → refusal with clear message.
- Invalid name characters (whitespace, slash) → clean rejection.
- Pipeline name composition: `<AZDO_REPO>-add-service` (independent of `<service-name>`, unlike `deploy`).
- Default parameter values match the pipeline's own defaults (`persistent_storage=false`, `public_endpoint=true`).
- Portability grep stays clean.
- `tests/run-all.sh` includes the new test file and aggregates its count.

---

## Completion notes (2026-05-28)

Three-phase ship on `feature/ai-developer-bootstrap`.

**Verified the pipeline contract** against `JKL900X016-NerdMeet/.pipelines/add-service.yaml`: parameter names `serviceName` / `persistent_storage` / `public_endpoint`, with the listed defaults. Pipeline behaviour confirmed: Copier → branch `add-service-<name>` → PR `Add service <name>` → create `<repo>-<name>-CD` pipeline (skip-first-run).

**`tests/test-PLAN-007-add-service.sh` — 21 tests, all passing**:

| # | Test | Result |
| --- | --- | --- |
| 1 | Lister shows add-service | ✅ |
| 2–4 | `--help` shows category + both flags | ✅ |
| 5–6 | No args → usage error | ✅ |
| 7–8 | Unknown flag rejected | ✅ |
| 9–10 | Extra positional argument rejected | ✅ |
| 11–12 | Leading-dash name rejected | ✅ |
| 13–14 | Path-separator name rejected | ✅ |
| 15–16 | Whitespace name rejected | ✅ |
| 17–18 | Outside git repo → "Not inside a git repository" | ✅ |
| 19–20 | Existing `services/<name>` → refusal | ✅ |
| 21 | Pipeline name composition: `<AZDO_REPO>-add-service` (independent of service name) | ✅ |

**Aggregate**: `tests/run-all.sh` total is now **155 tests, 0 failures**. The runner auto-discovered the new test file (no manual wiring).

**End-to-end pipeline run deferred** — would actually scaffold a service in FRT. The next manual `noclickops add-service test-<something>` is the live validation.

**Defaults match the pipeline's defaults**: `persistent_storage=false`, `public_endpoint=true`. Callers only specify what they want different (`--persistent-storage` or `--no-public-endpoint`).

**Listing order in "Service lifecycle"**: bash's `*` glob is lexical, so the order in the lister is `add-service`, `clean-sample`, `sync-lovable`. Reads as a natural lifecycle (create → strip sample → sync content), so we don't override the sort.
