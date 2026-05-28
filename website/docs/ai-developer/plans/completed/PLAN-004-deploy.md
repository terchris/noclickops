# PLAN-004: `deploy` — trigger a service's CD pipeline

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-28

**Goal**: One command to kick off (and optionally watch) the CD pipeline that ships a service. Replace the "click around the ADO Pipelines tab, find the pipeline, click Run, fill in the parameter, click Run again" path.

**Last Updated**: 2026-05-28

**Investigations**:

- [INVESTIGATE-noclickops.md](../backlog/INVESTIGATE-noclickops.md) → "Outline of v1 PLANs" → PLAN-004

**Depends on**: PLAN-001, PLAN-002, PLAN-003 (`lib/azdo.sh` reuse).

**Priority**: High — second most-used command after `create-pr` + `merge-pr`.

---

## Problem

Today (in the FRT repo) deploying involves `az pipelines run --name "JKL900X016-NerdMeet-<service>-CD" --branch refs/heads/main --parameters "targetEnvironment=test"`. Long, error-prone, and embeds `JKL900X016-NerdMeet` — useless from any other repo. The pipeline naming convention `<AZDO_REPO>-<service>-CD` is mechanical; noclickops can derive it.

---

## What it delivers

### `bin/deploy.{sh,ps1}`

```text
noclickops deploy <service> [test|prod] [--watch]
```

Behaviour:

- Resolves the target repo from `pwd` (`TARGET_REPO` from `lib/paths.sh`).
- **Validates that `<TARGET_REPO>/services/<service>` exists** before any `az` call — catches typos cheaply and prints the available service list on miss.
- Derives `AZDO_REPO` from the target's git remote (via `lib/azdo.sh`); composes the pipeline name as `<AZDO_REPO>-<service>-CD`.
- Triggers the pipeline against `refs/heads/main` with `targetEnvironment=<env>` parameter.
- Prints the run id + ADO build-results URL.
- With `--watch`: polls `az pipelines runs show --query status` every 20s up to ~30 minutes; on `completed` reports `result` (`succeeded` / `failed`); on failure exits non-zero with the URL.

### What this PLAN does NOT do

- **No `--ref` / `--tag` flag for v1**. The FRT-side pipelines always run from `refs/heads/main` regardless of target env. If/when the pipelines gain tag-based prod deploys, add it. For now `prod` ≠ `from-tag`; it just means the `targetEnvironment` parameter the pipeline reads.
- **No deploy-history viewer / log tail in this PLAN**. PLAN-008 (`info`) and PLAN-009 (`logs`) cover those.
- **The `services/<service>` directory check assumes FRT-shaped repos.** Other monorepo layouts aren't a v1 target; documented as a future portability extension.

---

## Phases

1. `bin/deploy.{sh,ps1}` — full implementation.
2. Smoke test:
   - `--help` prints metadata block.
   - Lister now shows the "Deployment" section with `deploy`.
   - Missing service arg → usage error, no `az` call.
   - Unknown arg → error, no `az` call.
   - `<service>` not in target's `services/` → friendly miss with "Available services:" listing (taken from `ls services/`).
   - End-to-end pipeline run deferred (would actually fire a real CD pipeline).

---

## Validation criteria

- `bin/deploy.sh` rejects bad service names before invoking `az`.
- Pipeline name is composed dynamically: `$AZDO_REPO-$service-CD` — no `JKL900X016` anywhere in the code.
- `deploy --help` prints uniform metadata block.
- Lister groups it under "Deployment".
- All input-validation errors fire pre-`az` (testable without auth).

---

## Completion notes (2026-05-28)

Single-phase ship on `feature/ai-developer-bootstrap`.

**Smoke test results**:

| # | Test | Result |
| --- | --- | --- |
| 1 | Lister shows new "Deployment" section with `deploy` | ✅ |
| 2 | `deploy --help` prints metadata-driven block | ✅ |
| 3 | No-arg call → usage error before any other work | ✅ |
| 4 | Unknown flag (`--foo`) → error pre-`az` | ✅ |
| 5 | Unknown service → friendly miss with "Available services:" listing (4 sample services enumerated correctly) | ✅ |
| 6 | Target repo lacks `services/` → distinct error message ("repo has no 'services/' directory") | ✅ |
| 7 | Run from outside any git repo → "Not inside a git repository" | ✅ |
| 8 | Pipeline-name composition: `derive_azdo_context` against `https://dev.azure.com/AcmeCorp/Platform/_git/some-app` → AZDO_REPO=`some-app` → pipeline=`some-app-myservice-CD` | ✅ |
| 9 | Portability grep clean (no `ExampleOrg` / `FrontendPlatform` / `JKL900X016` in `bin/` or `lib/`) | ✅ |

**No bugs found during testing** — the metadata-parser fix from PLAN-003 paid off; `deploy.sh`'s metadata with `[test|prod]` brackets parsed cleanly first time.

**Mirroring against the FRT repo** (sanity-check only, not run):

- AZDO_REPO for FRT = `JKL900X016-NerdMeet`
- For `service = test-holderdeord` → pipeline = `JKL900X016-NerdMeet-test-holderdeord-CD`
- Matches the existing FRT pipeline naming convention. Drop-in compatible.

**End-to-end pipeline-run smoke test deferred**: would fire a real CD pipeline. The next manual `noclickops deploy test-holderdeord test --watch` in the FRT repo is the live validation.

**v1 scope notes carried forward** (already in the body above):

- Always uses `refs/heads/main` as the source ref. A `--ref`/`--tag` flag would imply prod-from-tag, which the FRT pipelines don't currently support.
- `services/<service>/` directory check assumes FRT-shaped repos. Non-monorepo layouts → future portability extension.
