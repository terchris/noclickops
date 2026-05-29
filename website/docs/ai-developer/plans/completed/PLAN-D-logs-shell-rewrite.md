# PLAN-D — `logs` + `shell` rewrite for v2

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Completed

**Goal**: Rewrite `bin/logs.sh` and `bin/shell.sh` on `lib/service-v2.sh`. Both commands use the same v2 discovery primitives (`read_iac_variables` + `discover_containerapp`) — bundled in one plan because the rewrite is identical except for the final `az` invocation.

**Last Updated**: 2026-05-29

**Completed**: 2026-05-29

### Completion notes

- Both `bin/logs.sh` and `bin/shell.sh` now source `lib/service-v2.sh`. v1 `SVC_*` globals gone; `IAC_SUBSCRIPTION_ID` + `discover_containerapp` provide all context.
- Both gate on discovery failure (die loudly with the override-env-var message) — appropriate since neither can function with an unknown container app.
- `try_az_subscription` preflight dropped; `discover_containerapp`'s own die is the right surface for the "no Reader" case. Kept the `az account show` login check (skipped when `NCO_AZ_OVERRIDE` is set for tests).
- Final call uses `exec "${NCO_AZ_OVERRIDE:-az}" ...` so tests can intercept the final exec'd command — same UX as before for real users (`exec az` semantics for clean stdin/stdout + Ctrl-C).
- `tests/test-PLAN-009-logs.sh` and `tests/test-PLAN-010-shell.sh` deleted. New `tests/test-PLAN-D-logs-shell.sh` covers both (43 assertions): help / no-args / outside-repo / invalid-env / happy path for both / flag pass-through / gating on discovery failure / override path.
- Test uses a PLAN-D-specific az stub that intercepts the final exec'd `containerapp logs show` / `containerapp exec` calls (echoes them as `AZ_CALL: ...`) while delegating other queries to fixture files. The stub is auto-generated + gitignored.
- Total tests: 435 → 430 (net after the v1 test deletion + PLAN-D test addition).
- Branch stays `feat/v2-new-target-structure`. Per CLAUDE.md PR-per-investigation rule.

**Investigation**: [INVESTIGATE-new-target-structure.md](INVESTIGATE-new-target-structure.md) (see § "Per-command impact → logs / shell" and § "PLAN sequence → PLAN-D")

**Prerequisites**: [PLAN-A](../completed/PLAN-A-service-discovery.md) ships `discover_containerapp` + `read_iac_variables`.

**Branch**: same as PLAN-A/B/C — `feat/v2-new-target-structure`.

---

## Overview

`logs` and `shell` are siblings:

- `logs` exec's `az containerapp logs show` with the discovered container app.
- `shell` exec's `az containerapp exec` for an interactive session.

Both need: the live container-app `name` + `resource_group` + `subscription`. v1 derived these from `.pipelines/variables/` + a hardcoded `rg-<env>-nrx-<APP_NAME>` pattern. v2 reads `IAC_SUBSCRIPTION_ID` from the IaC variables and asks Azure for the actual deployed name + RG via `discover_containerapp`.

Both are **gating** (unlike `info`, which degrades): if discovery comes up empty, the command dies with a clear "set `SVC_APP_NAME_OVERRIDE=<name>` and `SVC_RG_OVERRIDE=<rg>` to override" message. No degraded mode — you can't stream logs from "(unavailable)".

The lib-level functions already do everything needed; this plan is two thin bin/ rewrites plus tests.

---

## What changes per command

### `bin/logs.sh`

| Aspect | v1 | v2 |
|---|---|---|
| Lib source | `lib/service.sh` | `lib/service-v2.sh` |
| Context resolution | `resolve_service_context` (SVC_*) | `read_iac_variables` (IAC_*) |
| App lookup | `az containerapp list` in derived RG, name-contains-SVC_NAME | `discover_containerapp` (override → common RG → sub-wide) |
| Final exec | `az containerapp logs show --name <app> --resource-group <rg> --subscription <sub> --tail N [--follow] [--type system]` | Same shape, but `<app>` / `<rg>` / `<sub>` come from `discover_containerapp` / `IAC_*` |
| Flag set | `--follow`/`-f`, `--tail N`, `--system` | Unchanged (no UX churn within v2 itself) |

### `bin/shell.sh`

| Aspect | v1 | v2 |
|---|---|---|
| Lib source | `lib/service.sh` | `lib/service-v2.sh` |
| Context resolution | `resolve_service_context` | `read_iac_variables` |
| App lookup | `az containerapp list` + name-contains | `discover_containerapp` |
| Final exec | `az containerapp exec --name <app> --resource-group <rg> --subscription <sub> --command <cmd> [--container N] [--revision N]` | Same shape; `<app>` / `<rg>` / `<sub>` from discovery |
| Flag set | `--command`, `--container`, `--revision` | Unchanged |
| Default `cmd` | `/bin/sh` (matches nginx:alpine base) | `/bin/sh` (still a reasonable default for the new sample shape) |

Both commands continue to use `exec az ...` as the final call so stdin/stdout wire straight to az — required for interactive shell + Ctrl-C in `--follow` mode.

---

## Phase 1: Rewrite `bin/logs.sh` — DONE

### Tasks

- [x] 1.1 Replace `. "$_dir/../lib/service.sh"` → `. "$_dir/../lib/service-v2.sh"`. Update the docstring at the top to describe v2's data sources.
- [x] 1.2 Keep the existing argument parsing (positional `<service> [test|prod]` + `--follow`/`-f` / `--tail N` / `--system`). No flag changes.
- [x] 1.3 Replace `resolve_service_context` with `read_iac_variables "$env"`. No need for `read_service_config` — logs doesn't print service config; it just needs sub/RG context.
- [x] 1.4 Replace the `az containerapp list` + name-match block with a `discover_containerapp "$service"` call. Parse the `name=` / `resource_group=` lines. (FQDN ignored — logs doesn't need it.) If `discover_containerapp` dies, the script dies with its message — no extra handling needed.
- [x] 1.5 Replace `try_az_subscription` preflight — `discover_containerapp` will naturally fail if the user lacks sub Reader. Keep the `az account show` login check (cheap, gives a clearer error than discovery's "not found").
- [x] 1.6 Build the final `az containerapp logs show` invocation using `$ca_name` / `$ca_rg` / `$IAC_SUBSCRIPTION_ID`. `exec` it as before.
- [x] 1.7 Update `SCRIPT_AUTH` + `SCRIPT_DETAILS` to mention v2's data sources (IaC variables via ADO REST, container app discovered via `az containerapp list`, override env vars).

### Validation

```bash
bash bin/logs.sh --help                 # static check
bash tests/run-all.sh                   # no regression
```

User confirms phase is complete.

---

## Phase 2: Rewrite `bin/shell.sh` — DONE

Same as Phase 1 but for `shell`. Verbatim repeat of the discovery flow — just the final `exec` line differs.

### Tasks

- [x] 2.1 Swap `lib/service.sh` → `lib/service-v2.sh` source line.
- [x] 2.2 Keep argument parsing intact (`<service> [test|prod] [--command CMD] [--container NAME] [--revision NAME]`).
- [x] 2.3 Replace `resolve_service_context` with `read_iac_variables "$env"`.
- [x] 2.4 Replace the `az containerapp list` block with `discover_containerapp "$service"`.
- [x] 2.5 Drop `try_az_subscription` preflight; keep `az account show` login check.
- [x] 2.6 Build the `az containerapp exec --name $ca_name --resource-group $ca_rg --subscription $IAC_SUBSCRIPTION_ID --command $cmd [--container ...] [--revision ...]` invocation. `exec` it.
- [x] 2.7 Update `SCRIPT_AUTH` + `SCRIPT_DETAILS` for v2.

### Validation

```bash
bash bin/shell.sh --help
bash tests/run-all.sh
```

User confirms phase is complete.

---

## Phase 3: Tests + delete v1 — DONE

### Tasks

- [x] 3.1 Delete `tests/test-PLAN-009-logs.sh` and `tests/test-PLAN-010-shell.sh` (v1 tests). The v1 lib (`lib/service.sh`) still has its own test in `tests/test-PLAN-008-info.sh` — those lib assertions remain (they cover `yaml_var` + `resolve_service_context` until PLAN-F's cleanup).
- [x] 3.2 Create `tests/test-PLAN-D-logs-shell.sh`. Single file covers both commands since they share the same flow. Cover:
  - `--help` renders v2 metadata for both commands.
  - No args → exit 1 + usage (each command).
  - Outside a git repo → clear error (each command).
  - Invalid env → exit 1 + "Invalid environment" (each command).
  - **Logs happy path**: with v2 fixtures + stubs that have a containerapp hit, the script exec's `az containerapp logs show` with the right `--name` / `--resource-group` / `--subscription` / `--tail`. Use `NCO_AZ_OVERRIDE` + a stub that prints the args it received (so we can assert what az was called with). NOTE: bin/logs.sh uses `exec az ...` which replaces the process — the stub IS the final az call.
  - **Shell happy path**: same idea, asserting `az containerapp exec --command /bin/sh` (the default).
  - **Gating on discovery failure**: stub returns empty containerapp list for both RG + sub-wide; both commands die with non-zero exit + the "set SVC_APP_NAME_OVERRIDE" message.
  - **Override path**: `SVC_APP_NAME_OVERRIDE` + `SVC_RG_OVERRIDE` set → no containerapp list call needed (discover_containerapp short-circuits to the override); final az invocation uses the overrides.
  - Flag pass-through for logs: `--follow` + `--tail 50` + `--system` → asserted in the captured az invocation.
  - Flag pass-through for shell: `--command "/bin/bash"` + `--container web` → asserted.
- [x] 3.3 Verify `tests/test-portability.sh` stays green (no new tenant strings leaked).

### Validation

```bash
bash tests/run-all.sh
```

Total passing count rises by however many the new test file adds. Zero failures.

User confirms phase is complete.

---

## Phase 4: Docs sync — DONE

### Tasks

- [x] 4.1 Update `website/docs/getting-started.md`:
  - In the compatibility matrix, `logs` and `shell` flip from "Still v1 — fails fast with Repo-level variables missing. v2 fix in PLAN-D." to "**v2** — discovers container app via `az containerapp list` against the IaC-declared subscription/RG; override with `SVC_APP_NAME_OVERRIDE` + `SVC_RG_OVERRIDE`."
  - Update example output if there's one.
- [x] 4.2 Update `website/docs/contributors/lib-service-v2.md`: in the "Related" section (or wherever, fit naturally), mention that `bin/logs.sh` + `bin/shell.sh` are v2 consumers of `discover_containerapp`.

### Validation

```bash
cd website && npm run build
```

Build clean.

User confirms phase is complete.

---

## Acceptance Criteria

- [ ] `bin/logs.sh` sources `lib/service-v2.sh`
- [ ] `bin/shell.sh` sources `lib/service-v2.sh`
- [ ] No reference to v1's `SVC_*` globals in either bin file
- [ ] No hardcoded `rg-<env>-nrx-...` pattern anywhere new
- [ ] Both commands die loudly when `discover_containerapp` can't find the app (no degraded mode)
- [ ] Both commands respect `SVC_APP_NAME_OVERRIDE` + `SVC_RG_OVERRIDE` overrides
- [ ] `tests/test-PLAN-D-logs-shell.sh` exists and passes
- [ ] `tests/test-PLAN-009-logs.sh` + `tests/test-PLAN-010-shell.sh` deleted
- [ ] `tests/run-all.sh` green
- [ ] Docs reflect v2-ready status for both commands

---

## Files to Modify

- `bin/logs.sh` (rewrite)
- `bin/shell.sh` (rewrite)
- `tests/test-PLAN-009-logs.sh` (delete)
- `tests/test-PLAN-010-shell.sh` (delete)
- `tests/test-PLAN-D-logs-shell.sh` (new)
- `website/docs/getting-started.md`
- `website/docs/contributors/lib-service-v2.md` (small Related update)

---

## Implementation Notes

### Why one plan for two commands

`logs` and `shell` are mechanically identical at the v2 lib layer. Both:
1. `read_iac_variables`
2. `discover_containerapp`
3. Build an `az containerapp <verb> ...` command
4. `exec az`

The only difference is the verb (`logs show` vs `exec`) and the flag set. Splitting into two plans would duplicate ~80% of the scaffolding without adding any decision points. One plan, two trivial bin rewrites.

### Why gating not degrading

`info` degrades on discovery failure (prints "unavailable" and exits 0) because its job is to *show what we know*. `logs` and `shell` can't function without an actual container app — there's nothing to stream from "(unavailable)". Failing closed with a clear "set the overrides to fix" message is the right UX.

`discover_containerapp`'s default `die` behavior is exactly right for this; no extra wrapping needed (unlike `info`'s `output=$(... 2>&1) || output=""` pattern).

### Why the final `exec az` matters

Both v1 commands use `exec az ...` instead of `az ...; exit $?` so the az process REPLACES the bash process. Two reasons:
- **Interactive shell**: `shell`'s stdin/stdout need to wire directly to az exec without bash buffering.
- **Ctrl-C in `--follow`**: when the user hits Ctrl-C, the signal goes straight to az, which cleans up the streaming connection. With a non-exec `az ...`, bash would catch the signal first and the cleanup is messier.

v2 keeps the `exec az` pattern. Don't change to `az ...; exit $?`.

### `--app-name` / `--resource-group` as CLI flags?

The investigation says info/logs/shell "require `--subscription` + `--resource-group` + `--app-name` overrides if discovery fails." That implies CLI flags. v2 chose env vars (`SVC_APP_NAME_OVERRIDE` + `SVC_RG_OVERRIDE`) instead because they compose better with `--watch` / `--follow` / `--tail`-style flags users already remember, and they're stickier across multiple commands in the same shell session.

If real users want CLI flags, add them later — they're a thin wrapper around the env vars. Out of scope for PLAN-D.

### Out of scope for PLAN-D

- `--app-name` / `--resource-group` / `--subscription` CLI flags (use env vars; flags later if asked for).
- Multi-revision / multi-replica selection beyond what `--revision` already does.
- Log filtering (grep'ing in noclickops itself — let users pipe to `grep`).
- `logs --since DURATION` (azure-cli does support `--since` for log filtering — could add as a v2.x flag pass-through if useful).
- `shell --user UID` (not supported by `az containerapp exec`; users can `su` once inside).
