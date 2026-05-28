# PLAN-008: `info` + the env-aware service-context library

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-28

**Goal**: One command to answer "what is deployed where, with which config?" for a service+env combo. Establishes the env-aware **`SUBSCRIPTION_ID` lookup** that PLAN-009 (`logs`) and PLAN-010 (`shell`) will reuse, plus the **fail-closed subscription-access messaging** the investigation calls for.

**Last Updated**: 2026-05-28

**Investigations**:

- [INVESTIGATE-noclickops.md](../backlog/INVESTIGATE-noclickops.md) → "Outline of v1 PLANs" → PLAN-008

**Depends on**: PLAN-001, PLAN-003 (`lib/azdo.sh`), PLAN-007a (`bin/status.sh` set the precedent for the `Inspect / observe` category and the TSV-from-az parsing style).

**Priority**: High — it's the gating PLAN for PLAN-009 / PLAN-010 because of `lib/service.sh`.

---

## Problem

Today, finding out what's deployed and how a service is configured means reading three or four YAML files and clicking through the Azure portal. The data is all there, in known locations — noclickops can pull it together. But more importantly: **PLAN-009 and PLAN-010 need the same `SUBSCRIPTION_ID` → resource-group → container-app lookup chain**, and we shouldn't write it three times.

PLAN-008 puts the chain in `lib/service.sh` once. `info` is the first user.

---

## What it delivers

### `lib/service.{sh,ps1}` — the env-aware context library

```text
resolve_service_context <service> [<env>] [<target-repo>]
```

Reads three YAML files and exports a set of `SVC_*` globals:

| Source file | Variables exported |
| --- | --- |
| `<repo>/.pipelines/variables/common.yaml` | `SVC_APP_NAME` |
| `<repo>/.pipelines/variables/<env>.yaml` | `SVC_SUBSCRIPTION_ID`, `SVC_ENVIRONMENT`, `SVC_COMMON_RG` |
| `<repo>/services/<svc>/.pipelines/variables/<env>.yaml` | `SVC_PORT`, `SVC_HEALTH_PATH`, `SVC_PUBLIC_ENDPOINT`, `SVC_CPU`, `SVC_MEMORY`, `SVC_MIN_REPLICAS`, `SVC_MAX_REPLICAS` |
| Computed | `SVC_NAME`, `SVC_DIR`, `SVC_ENV`, `SVC_RESOURCE_GROUP` = `rg-<env>-nrx-<APP_NAME>` |

Dies on missing files or invalid env. The naming follows FRT conventions verified against `JKL900X016-NerdMeet/.pipelines/cd.yaml` and `services/test-holderdeord/.pipelines/variables/test.yaml`.

Plus a small helper:

```text
try_az_subscription <subscription-id>
```

Tries `az account set --subscription <id>`; returns 0 on success, **fail-closed** with friendly diagnostics if the user lacks subscription access ("You need 'Reader' or higher on subscription X — ask your team admin"). Returns 1; the caller decides whether that's terminal or just "skip the live-state section". `info` treats it as non-terminal (still shows static config).

### `bin/info.{sh,ps1}`

```text
noclickops info <service> [test|prod]
```

Output:

```text
Service: test-holderdeord (test)
────────────────────────────────────────
  Folder:            services/test-holderdeord
  APP_NAME:          frt900x016
  ENVIRONMENT:       test
  SUBSCRIPTION_ID:   3aec5ff4-...
  Resource group:    rg-test-myteam-frt900x016
  Common RG:         rg-test-myteam-frontend-common

Service config:
  Port:              3000
  Health check:      /health
  CPU:               0.5
  Memory:            1Gi
  Replicas (min):    0
  Replicas (max):    1
  Public endpoint:   true

Container app (live):
  Name:              ca-test-frt900x016-test-holderdeord
  Status:            Running
  Latest revision:   ca-test-frt900x016-test-holderdeord--abcd123
  FQDN:              https://test-holderdeord.example.cloud
  Image:             acrshareduw.azurecr.io/frt900x016-test-holderdeord:202605281234
  Replicas (live):   min=0, max=1
```

- Two top sections always populate from YAML (no auth needed) — answers "how is this configured?" without any Azure roundtrip.
- "Container app (live)" requires Reader on the subscription. If `try_az_subscription` fails, that section prints `(live state unavailable — see warnings above)` and the script exits 0. **Info is informational, not gating.**
- Container app located by `az containerapp list --query "[?contains(name, '$SVC_NAME')] | [0]"` against the computed resource group — listing is safer than guessing the exact name.

### `bin/status.{sh,ps1}` is unchanged.

PLAN-007a's `status` covers pipeline-run lookup; `info` covers service+env state. They're complementary, both in "Inspect / observe".

---

## Phases

1. `lib/service.{sh,ps1}` — YAML var extractor + `resolve_service_context` + `try_az_subscription`.
2. `bin/info.{sh,ps1}` — composes the two sections (static + live) atop `resolve_service_context` and `try_az_subscription`.
3. Extend `tests/_fixtures.sh` with `add_pipeline_variables` and `add_service_variables` helpers (build the YAML files PLAN-009/010 will also need).
4. `tests/test-PLAN-008-info.sh` — lib + bin coverage that doesn't require `az`.

---

## Validation criteria

- `lib/service.sh::yaml_var` correctly extracts plain `key: "value"`, `key: value`, and `key: 'value'` from a YAML file; returns empty on missing key.
- `resolve_service_context` against a fake repo (with fixture YAMLs) populates all 11 `SVC_*` variables; computes `SVC_RESOURCE_GROUP` = `rg-<env>-nrx-<APP_NAME>`.
- `resolve_service_context` dies on: unknown service, unknown env, missing `common.yaml`, missing `<env>.yaml`, missing service-level `<env>.yaml`.
- `info --help` prints the metadata block.
- Lister shows `info` under "Inspect / observe" alongside `status`.
- `info` outside any repo → "Not inside a git repository".
- `info <svc> prod` against a repo where `SUBSCRIPTION_ID` is empty (the FRT prod yaml's current state) prints the static sections and the warning + skip; exits 0.
- Portability grep stays clean.
- `tests/run-all.sh` aggregate grows by the new test file's count.

---

## Completion notes (2026-05-28)

Four-phase ship on `feature/ai-developer-bootstrap`.

**Tests** — `tests/test-PLAN-008-info.sh`, 46 tests:

| Group | Count | Highlights |
| --- | --- | --- |
| `yaml_var` parser | 5 | double-quoted / single-quoted / unquoted / empty / missing key |
| `resolve_service_context` happy path | 12 | All 11 SVC_* globals populate correctly from fixture YAMLs; prod env picks prod's `SERVICE_MIN_REPLICAS=1`, `SERVICE_MAX_REPLICAS=3` (different from test); prod's empty `SUBSCRIPTION_ID` stays empty |
| `resolve_service_context` errors | 6 | unknown service / invalid env / missing common.yaml — each with a distinct error message |
| `bin/info.sh` integration | 22 | lister + `--help` / no-args / outside-repo / unknown service / invalid env / static-section content / live-section fail-closed branch |
| Portability | 1 | grep guard re-asserted |

**Aggregate**: `tests/run-all.sh` total is now **218 tests, 0 failed, 0 skipped** (was 172 after PLAN-007a).

**Bug caught and fixed mid-test**: the portability grep flagged a `JKL900X016-NerdMeet` reference in my `lib/service.sh` docstring header — same kind of tenant leak the PLAN-003 commit fixed. Reworded to "the reference FRT-shaped repo" — no tenant name. The grep guard pays off every time.

**lib/service.sh design choices worth flagging**:

- **`yaml_var` is intentionally minimal**: flat `key: value` only, no nested keys, no anchors, no multiline strings. The FRT variables files are exactly that shape (verified). Comment in the file explicitly says don't reuse it on real YAML.
- **`try_az_subscription`** is the shared fail-closed helper PLAN-009/PLAN-010 will reuse. Returns 0/1; never aborts on its own. Caller decides — `info` treats failure as non-terminal (still shows static config); `logs` and `shell` will probably treat it as terminal.
- **Container-app lookup uses `az containerapp list` + `contains(name, …)`** rather than guessing the exact name. The actual name follows a bicep convention (`ca-<env>-<APP_NAME>-<service>` or similar) that I deliberately didn't hardcode — lookup tolerates future naming changes.
- **`resolve_service_context` takes the target repo as an arg** (defaults to `$TARGET_REPO`). Lets tests pass a fixture-built repo without polluting the test process's pwd.

**Inspect / observe section is now**:

```text
  info            Show service config and live container-app state.
  status          Show the status of an Azure DevOps pipeline run.
```

**End-to-end against a real container app deferred** — needs Azure subscription Reader role. Next manual `noclickops info test-holderdeord test` is the live validation.
