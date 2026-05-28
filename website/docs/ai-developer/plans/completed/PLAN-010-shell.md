# PLAN-010: `shell` — interactive exec into a running container

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-28

**Goal**: Open an interactive shell inside the live container app of a service+env, without clicking through the Azure portal to find the right container app, revision, and replica, and click "Console".

**Last Updated**: 2026-05-28

**Investigations**:

- [INVESTIGATE-noclickops.md](../backlog/INVESTIGATE-noclickops.md) → "Outline of v1 PLANs" → PLAN-010

**Depends on**: PLAN-008 (`lib/service.sh`). Third and final consumer of `resolve_service_context` + `try_az_subscription`.

**Priority**: Medium-high — used when debugging a deployed service. The last v1 PLAN.

---

## Problem

When a deployed service misbehaves and the logs (PLAN-009) don't tell the whole story, the next step is poking around inside the running container. `az containerapp exec` does this but needs the app name, resource group, subscription, and a sensible default command. PLAN-008's `lib/service.sh` already resolves the first three; PLAN-010 wraps it.

---

## What it delivers

### `bin/shell.{sh,ps1}`

```text
noclickops shell <service> [test|prod] [--command CMD] [--container NAME] [--revision NAME]
```

Behaviour:

- Defaults: env=`test`, command=`/bin/sh` (works in `nginx:alpine` — our Lovable Dockerfile base; `bash` isn't installed in plain alpine).
- `--command CMD`: override the entry command (e.g. `ls -la /etc/nginx`, `cat /usr/share/nginx/html/health.json`).
- `--container NAME`: target a specific container (for multi-container apps).
- `--revision NAME`: target a specific revision instead of the active one.
- Same arg-parser shape as PLAN-009's `logs`, including the **"Invalid environment"** catch for typos in the second positional.
- Resolves service+env via `resolve_service_context`; finds the container app in `<SVC_RESOURCE_GROUP>` via `contains(name, SVC_NAME)`.
- Fails CLOSED — same five failure modes as `logs`. The user wants a shell; can't give them one means error.
- `exec`s into `az` so stdin/stdout/stderr are wired directly — interactive shell needs that, and Ctrl-D / Ctrl-C terminate cleanly.

### Same UX wart fix as PLAN-009

The "Invalid environment" check for a bare non-flag second positional is already in this PLAN's arg parser. (PLAN-009 retro-noted that `deploy.sh` and `add-service.sh` have the same wart; this PLAN doesn't change those.)

### What this PLAN does NOT do

- **No replica selection by index/name.** `az` defaults to the first replica; for v1, that's enough. If `--replica` becomes useful, add later.
- **No automatic `bash` fallback.** If the user wants `bash` and the container doesn't have it, the error is clear enough (`OCI runtime exec failed: exec failed: unable to start container process: exec: "bash": executable file not found in $PATH`). Default to `/bin/sh` and let users override.

---

## Phases

1. `bin/shell.{sh,ps1}` — argument parser + the `az containerapp exec` invocation.
2. `tests/test-PLAN-010-shell.sh` — validation coverage; the `az` call itself is deferred.

---

## Validation criteria

- `shell --help` prints the metadata block; mentions `--command`, `--container`, `--revision`.
- Lister shows `shell` under "Inspect / observe" alongside `info`, `logs`, `status`.
- No args → usage error.
- Outside any git repo → "Not inside a git repository".
- Unknown service → "Service '<name>' not found".
- Invalid env (e.g. `staging`) → "Invalid environment".
- Unknown flag → "Unknown argument".
- `--command` without a value → distinct error.
- Empty `SUBSCRIPTION_ID` (prod fixture) → fail-closed exit 1.
- Portability grep stays clean.
- `tests/run-all.sh` aggregate grows by the new test file's tests.

---

## v1 surface complete

After PLAN-010, every command listed in `INVESTIGATE-noclickops.md` → "Outline of v1 PLANs" is shipped. The complete v1 lister output:

```text
Meta                noclickops, update
Git / pull requests create-pr, merge-pr
Deployment          deploy
Service lifecycle   add-service, clean-sample, sync-lovable
Inspect / observe   info, logs, shell, status
```

Eleven commands. Two `lib/` chains (`lib/azdo.sh` for ADO identity, `lib/service.sh` for service+env context). One installer + shell function. One template (`lovable/`). One test suite.

---

## Completion notes (2026-05-28)

Two-phase ship on `feature/ai-developer-bootstrap`.

**Tests** — `tests/test-PLAN-010-shell.sh`, 25 tests:

| # | Test | Result |
| --- | --- | --- |
| 1 | Lister shows `shell` under "Inspect / observe" | ✅ |
| 2–6 | `--help` shows category, usage, and each of `--command` / `--container` / `--revision` | ✅ |
| 7–8 | No args → usage | ✅ |
| 9–10 | Outside repo → "Not inside a git repository" | ✅ |
| 11–12 | Unknown service → "Service '<name>' not found" | ✅ |
| 13–14 | Invalid env → "Invalid environment" (PLAN-009's arg-parser pattern reused) | ✅ |
| 15–16 | Unknown flag → "Unknown argument" | ✅ |
| 17–18 | `--command` without value → "--command requires a value" | ✅ |
| 19–20 | `--container` without value → distinct error | ✅ |
| 21–22 | `--revision` without value → distinct error | ✅ |
| 23 | Inline forms (`--command=ls --container=sidecar --revision=rev1`) parse cleanly | ✅ |
| 24–25 | Empty `SUBSCRIPTION_ID` (prod fixture) → fail-closed exit 1 | ✅ |

**Aggregate**: `tests/run-all.sh` is now **266 tests, 0 failed, 0 skipped** (was 241 after PLAN-009). This is the final number for v1.

**v1 surface complete** — the full investigation outline is shipped:

```text
Meta                noclickops, update
Git / pull requests create-pr, merge-pr
Deployment          deploy
Service lifecycle   add-service, clean-sample, sync-lovable
Inspect / observe   info, logs, shell, status
```

11 user-facing commands + the noclickops lister itself. Two shared libraries. One template stack (`lovable/`). One install path. One test suite (266 tests across 11 files).

**Default command `/bin/sh` chosen for `nginx:alpine` compatibility** — `bash` isn't installed in plain alpine, so defaulting to `/bin/sh` works for the Lovable Dockerfile base. Override with `--command bash` if the container has it.

**End-to-end against a real container app deferred** — needs Azure subscription Reader role. Next manual `noclickops shell test-holderdeord test` in the FRT environment is the live validation.

**No `--replica` flag in v1** — `az` defaults to the first replica which is enough for single-replica services. Add when multi-replica debugging surfaces.
