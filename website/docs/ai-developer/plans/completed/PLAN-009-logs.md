# PLAN-009: `logs` — stream a service's container-app logs

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-28

**Goal**: One command to read or stream logs from the live container app of a service+env, without clicking through the Azure portal to find the right container app and click "Log stream".

**Last Updated**: 2026-05-28

**Investigations**:

- [INVESTIGATE-noclickops.md](../backlog/INVESTIGATE-noclickops.md) → "Outline of v1 PLANs" → PLAN-009

**Depends on**: PLAN-008 (`lib/service.sh::resolve_service_context` + `try_az_subscription`). This is the second `lib/service.sh` consumer.

**Priority**: High — the most-requested observability command after "is it running" (info).

---

## Problem

When a service misbehaves in test or prod, the developer wants two things fast:

1. The last N lines of console logs (default 100 — more useful than `az`'s default 20).
2. Optionally, a live tail (`--follow`).

`az containerapp logs show` does both, but needs the container-app name, resource group, and subscription. PLAN-008's `lib/service.sh` already resolves all three. PLAN-009 is the wrapper.

---

## What it delivers

### `bin/logs.{sh,ps1}`

```text
noclickops logs <service> [test|prod] [--follow|-f] [--tail N] [--system]
```

Behaviour:

- Defaults: env=`test`, tail=`100`, console logs (not system).
- `--follow` / `-f`: stream live (passes through to `az --follow`).
- `--tail N`: override the tail size; numeric validation pre-`az`.
- `--system`: show system logs (container start/restart events) instead of console logs.
- Resolves service+env via `resolve_service_context`; finds the container app in `<SVC_RESOURCE_GROUP>` via `contains(name, SVC_NAME)`.
- Fails CLOSED — unlike `info`, `logs` exits non-zero on any access/lookup failure. The user wants logs; partial output is worse than a clear error.
- `exec`s into `az` so Ctrl-C in `--follow` mode terminates cleanly without bash trapping it.

### Fail-closed paths

| Cause | Action |
| --- | --- |
| `az` not on PATH | exit 1 (`require_cmd`) |
| Not logged in | exit 1 (`require_az`) |
| `SUBSCRIPTION_ID` empty in env yaml | exit 1 with `try_az_subscription`'s "set Reader role" message |
| Subscription access denied | exit 1 with same message |
| No container app found in the resource group | exit 1 with "Has it been deployed yet?" hint pointing at `deploy` |

All five fire before `az containerapp logs show` runs.

### What this PLAN does NOT do

- **No log filtering / grep**. The user can pipe to grep. `noclickops logs my-svc | grep error` works fine because `--follow` writes to stdout.
- **No multi-revision logs**. `az` supports `--revision <name>` but the typical ask is "logs from current". A future enhancement; the current revision is what shows by default.
- **No replica selection**. Same reason; aggregated logs are the default.

---

## Phases

1. `bin/logs.{sh,ps1}` — argument parser + the `az containerapp logs show` invocation.
2. `tests/test-PLAN-009-logs.sh` — validation coverage; the `az` call itself is deferred.

---

## Validation criteria

- `logs --help` prints the metadata block.
- Lister shows `logs` under "Inspect / observe" alongside `info` + `status`.
- `logs` with no args → usage error.
- `logs <svc> staging` → "Invalid environment" via `resolve_service_context`.
- `logs <svc> test --tail foo` → "--tail must be numeric".
- `logs <svc> test --tail` (no value) → distinct error.
- `logs <svc> test --bogus` → "Unknown argument".
- `logs` outside any git repo → "Not inside a git repository".
- `logs` against a fake target with empty `SUBSCRIPTION_ID` (the FRT prod yaml's current state) → fails closed with the Reader-role message.
- Portability grep stays clean.
- `tests/run-all.sh` aggregate grows by the new test file's tests.

---

## Completion notes (2026-05-28)

Two-phase ship on `feature/ai-developer-bootstrap`.

**Tests** — `tests/test-PLAN-009-logs.sh`, 23 tests:

| # | Test | Result |
| --- | --- | --- |
| 1 | Lister shows `logs` under "Inspect / observe" | ✅ |
| 2–6 | `--help` shows category, usage, and each of `--follow` / `--tail` / `--system` | ✅ |
| 7–8 | No args → usage | ✅ |
| 9–10 | Outside repo → "Not inside a git repository" | ✅ |
| 11–12 | Unknown service → `Service '<name>' not found` | ✅ |
| 13–14 | Invalid env (typo like `staging`) → "Invalid environment" | ✅ |
| 15–16 | Unknown flag → "Unknown argument" | ✅ |
| 17–18 | `--tail` without value → "--tail requires a number" | ✅ |
| 19–20 | `--tail foo` → "--tail must be numeric" | ✅ |
| 21 | `--tail=N` inline form parses cleanly | ✅ |
| 22–23 | Empty `SUBSCRIPTION_ID` (prod fixture) → fail-closed with empty-id warning, exit 1 | ✅ |

**Aggregate**: `tests/run-all.sh` is now **241 tests, 0 failed, 0 skipped** (was 218 after PLAN-008).

**UX wart caught and fixed mid-test**: the first arg parser treated any non-flag second positional as belonging to the `while` loop, so `logs myapp staging` errored with `Unknown argument: staging (expected --follow / -f / --tail N / --system)`. Reworded the env-parser branch to **catch a bare second positional that isn't `test|prod`** and error with `Invalid environment '<x>' (expected: test | prod)`. The test that caught it stays in the suite; the wart can't come back.

**Related cleanup left for later**: `deploy.sh` and `add-service.sh` have the same arg-parser shape and would produce the same "Unknown argument" wart on `deploy myservice staging` or similar. Not changed in this PLAN (no test coverage for that path on those scripts). If the wart bites in practice, the fix is one-line apiece, matching this PLAN's pattern.

**`exec az` for the real call**: when the user passes `--follow`, the process needs to stream from `az` for an indefinite period and Ctrl-C should terminate cleanly. `exec` replaces our bash with `az` so the signal goes straight there — no signal trapping needed.

**PowerShell port unverified on Mac**; the PS arg-parser uses PowerShell's native `[switch]` and `[int]$Tail` parameters, which sidestep the bash arg-parser complexity entirely.

**End-to-end against a real container app deferred** — same gate as PLAN-008.
