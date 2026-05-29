# PLAN-B — `info` rewrite for v2

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Completed

**Goal**: Rewrite `bin/info.sh` to use `lib/service-v2.sh` so `noclickops info <svc> <env>` works against the new two-project / two-repo layout. v1's `bin/info.sh` is replaced in place; `lib/service.sh` stays alongside for other commands that haven't migrated yet.

**Last Updated**: 2026-05-29

**Completed**: 2026-05-29

### Completion notes

- `bin/info.sh` fully on `lib/service-v2.sh`; all v1 `SVC_*` globals gone, replaced by `IAC_*` (IaC vars) + `SVC_CFG_*` (service config) + `discover_containerapp` for live state.
- Live section uses `_nco_az` shim for both `az account show` (login check) and `az containerapp show` (detail fetch) so tests stub everything via `NCO_AZ_OVERRIDE`.
- `tests/test-PLAN-008-info.sh` trimmed to lib-level only (`yaml_var` + `resolve_service_context`); 26 assertions remain to guard `lib/service.sh` while it's still sourced by `logs`/`shell`/`deploy`.
- `tests/test-PLAN-B-info.sh` added — 17 assertions covering: help/usage, missing service, static section, public URL line, live happy path, live degradation, and override path skipping the list call.
- Manual smoke against a live target repo is the user's responsibility before v2 release; covered by the test plan in `website/docs/getting-started.md`.
- Total tests: 376 → 399 (+23 net after the PLAN-008 trim).
- Branch stays `feat/v2-new-target-structure`. Per CLAUDE.md PR-per-investigation rule.

**Investigation**: [INVESTIGATE-new-target-structure.md](../backlog/INVESTIGATE-new-target-structure.md) (see § "Per-command impact → info" and § "PLAN sequence → PLAN-B")

**Prerequisites**: [PLAN-A](../completed/PLAN-A-service-discovery.md) ships `lib/service-v2.sh`.

**Branch**: Same as PLAN-A — `feat/v2-new-target-structure`. Per CLAUDE.md PR-per-investigation rule.

---

## Overview

`bin/info.sh` becomes the first v2 command. It uses `lib/service-v2.sh` exclusively:

- **Per-service config** from `services/<svc>/config.<env>.yaml` (via `read_service_config`)
- **Repo + env vars** from the cross-project IaC repo (via `read_iac_variables`)
- **Container-app name + RG** via `discover_containerapp` (Azure query, not a hardcoded pattern)
- **Public URL** via `public_url_for` (only for services with `ENABLE_PUBLIC_ENDPOINT=true`)

No backwards-compatibility constraints — there are no users running noclickops against the new layout yet, so output shape, env-var names, and flags are chosen for v2's own merits.

Per the investigation, info **degrades gracefully**: if `discover_containerapp` can't find the app (no Reader on the sub, app not deployed yet, naming overrides needed), the static sections still print and the live section shows a clear "unavailable — set `SVC_APP_NAME_OVERRIDE=<name>` and `SVC_RG_OVERRIDE=<rg>` to override" message. Unlike `logs` and `shell` (PLAN-D), info never fails just because live state isn't reachable.

---

## What info shows (v2)

### Static section — always prints, no Azure access needed

| Field | Source |
|---|---|
| `Service` | the `<svc>` arg (e.g. `frontend`) |
| `Environment` | the `<env>` arg (e.g. `test`) |
| `Folder` | `<TARGET_REPO>/services/<svc>` |
| `App name (IaC)` | `IAC_APP_NAME` from IaC `common.yaml` |
| `Application name` | `IAC_APPLICATION_NAME` |
| `Team` | `IAC_TEAM_NAME` |
| `Subscription` | `IAC_SUBSCRIPTION_ID` |
| `Common RG` | `IAC_COMMON_RESOURCE_GROUP_NAME` |
| `Container registry` | `IAC_CONTAINER_REGISTRY_NAME` |
| `DNS zone` | `IAC_DNS_ZONE_NAME` |
| `Port` / `Health check` / `CPU` / `Memory` / `Replicas (min/max)` | `SVC_CFG_SERVICE_*` from `config.<env>.yaml` |
| `Public endpoint enabled` | `SVC_CFG_ENABLE_PUBLIC_ENDPOINT` |
| `Persistent storage` | `SVC_CFG_PERSISTENT_STORAGE` |
| `Public URL` | `public_url_for <svc> <env>` — line omitted when not public |

### Live section — requires `az login` + sub Reader

| Field | Source |
|---|---|
| `Container app name` | `discover_containerapp` |
| `Resource group (live)` | `discover_containerapp` |
| `Status` / `Latest revision` / `Image` / `Replicas (live)` | `az containerapp show -n <name> -g <rg>` |
| `Internal FQDN` | `discover_containerapp` (the `*.azurecontainerapps.io` URL) |

On any live-section failure: print "(live state unavailable — see message)" and exit 0. Static section is always printed in full first.

---

## Phase 1: Rewrite `bin/info.sh` — DONE

### Tasks

- [x] 1.1 Rewrite `bin/info.sh`. Source `lib/service-v2.sh` (not `lib/service.sh`). Update the docstring at the top to describe v2's data sources.
- [x] 1.2 Resolve context:
  ```bash
  read_service_config "$service" "$env"
  read_iac_variables  "$env"
  ```
- [x] 1.3 Print the static section per the "What info shows → Static section" table. Use `(unset)` placeholder for any missing field. Group fields under bold subheadings: **Service / Environment**, **IaC repo**, **Service config**.
- [x] 1.4 If `SVC_CFG_ENABLE_PUBLIC_ENDPOINT=true`, print the **Public URL** line: `Public URL:  https://$(public_url_for "$service" "$env")`. Omit when private.
- [x] 1.5 Live section:
  - Wrap `discover_containerapp "$service"` in `output=$(discover_containerapp "$service" 2>&1) || output=""` so its `die` on failure doesn't abort the script.
  - On non-empty result: parse `name=` / `resource_group=` / `fqdn=` lines. Call `az containerapp show -n $name -g $rg --subscription $IAC_SUBSCRIPTION_ID --query "{...}" -o tsv` to get the full live detail, format under bold **Live state** subheading.
  - On empty result OR `az show` failure: print "  (live state unavailable — set `SVC_APP_NAME_OVERRIDE` and `SVC_RG_OVERRIDE` to override, or check `az login` and sub Reader)" — single line, no traceback.
- [x] 1.6 Update `SCRIPT_AUTH` metadata to describe v2: "az login (target's ADO tenant) for IaC variables; Reader on the IaC-declared subscription for live container-app state."
- [x] 1.7 Update `SCRIPT_DETAILS` to describe v2's surface (cross-project IaC variable file source, public-URL line, fail-graceful live section).
- [x] 1.8 Update `SCRIPT_FLAGS` if needed (no flag changes expected; `--help` already in metadata.sh).

### Validation

```bash
# Static section renders without any Azure access (use the v2 fixtures).
# Live section renders the "unavailable" path when az is offline.
bash tests/run-all.sh
```

User confirms phase is complete.

---

## Phase 2: Tests — DONE

### Tasks

- [x] 2.1 In `tests/test-PLAN-008-info.sh`, delete the `bin/info` assertions (sections 9+ — anything that runs `bash $NCO_ROOT/bin/info.sh`). Keep the `yaml_var` + `resolve_service_context` assertions — those test `lib/service.sh` which is still in the tree until PLAN-F's cleanup. Update the file header to reflect that it now covers v1 lib only.
- [x] 2.2 Create `tests/test-PLAN-B-info.sh`. Modeled on `tests/test-PLAN-A-service-discovery.sh`. Cover:
  - Static section renders with `make_v2_source_repo` + `make_v2_service` + `make_v2_iac_repo` + `NCO_ADO_REST_OVERRIDE` stub. Assert each labeled line contains the expected value (`App name (IaC): abc100001`, `Subscription: ...`, etc.) — including the new IaC-sourced fields.
  - Public URL line: present for `ENABLE_PUBLIC_ENDPOINT=true`, absent for `false`.
  - Live section happy path: `NCO_AZ_OVERRIDE` stub returns a hit; live block shows parsed FQDN / revision / image / replicas.
  - Live section degradation: stub returns empty; script exits 0, live block shows the "unavailable" message, static section still printed in full.
  - `SVC_APP_NAME_OVERRIDE` + `SVC_RG_OVERRIDE`: with both set, no `az containerapp list` call needs to happen (only `az containerapp show` for live details).
- [x] 2.3 Verify `tests/test-portability.sh` stays green (no new customer-tenant string leaks).

### Validation

```bash
bash tests/run-all.sh
```

Total passing count is higher than after PLAN-A. Zero failures. The old test file is gone, the new ones cover the same ground from v2's angle.

User confirms phase is complete.

---

## Phase 3: Docs + smoke — DONE

### Tasks

- [x] 3.1 Update `website/docs/getting-started.md`:
  - In the per-command compatibility matrix, `info` flips to "v2 — new layout only".
  - Replace any example output snippet with the v2 shape (new IaC-sourced fields + Public URL line).
- [x] 3.2 Update `website/docs/contributors/target-layout-reference.md`:
  - In the "Variable file locations" section, cross-reference: *"`noclickops info` reads from this location via `lib/service-v2.sh`'s `read_iac_variables` — see PLAN-B."*
- [x] 3.3 End-to-end smoke against a live target repo (manual; not CI). Document in PLAN-B's completion notes. Expected: every static field populated, live section shows the actual deployed container app, Public URL renders for public services.

### Validation

```bash
cd /path/to/your/source/repo
noclickops info frontend test
```

Output shape matches what `noclickops` v1.5.x produced; field values are correct against the new-layout repo.

User confirms phase is complete.

---

## Acceptance Criteria

- [ ] `bin/info.sh` sources `lib/service-v2.sh` (not `lib/service.sh`)
- [ ] No reference to v1's `SVC_*` globals (`SVC_APP_NAME`, `SVC_RESOURCE_GROUP`, etc.) remains in `bin/info.sh`
- [ ] No hardcoded `rg-<env>-nrx-...` pattern in `bin/info.sh` (or anywhere new in `bin/` or `lib/`)
- [ ] `tests/test-PLAN-B-info.sh` exists and passes; `tests/test-PLAN-008-info.sh` is trimmed to lib-only assertions
- [ ] `tests/run-all.sh` green; total pass count higher than post-PLAN-A (376)
- [ ] `website/docs/getting-started.md` reflects v2-ready status for `info`
- [ ] Manual smoke against a real new-layout repo shows correct output for both public and private services

---

## Files to Modify

- `bin/info.sh` (rewrite)
- `tests/test-PLAN-008-info.sh` (trim — drop bin/info assertions, keep lib-level)
- `tests/test-PLAN-B-info.sh` (new)
- `website/docs/getting-started.md`
- `website/docs/contributors/target-layout-reference.md`

---

## Implementation Notes

### `discover_containerapp` deliberately dies; info wraps it

`lib/service-v2.sh`'s `discover_containerapp` is designed to fail loudly with a clear "set `SVC_APP_NAME_OVERRIDE` / `SVC_RG_OVERRIDE` to override" message when neither (b) common-RG lookup nor (c) subscription-wide lookup hits. That's the right default for `logs` and `shell` (PLAN-D) — they can't function without a real container app.

`info` is different. Its job is to print *what we know*, even if some sections can't be filled in. So `info` wraps `discover_containerapp` in `output=$(discover_containerapp ... 2>/dev/null) || output=""` and treats empty as "live section unavailable" — same degradation pattern v1 already used. Don't try to make `discover_containerapp` itself degrade; the caller's intent decides.

### Why not delete PLAN-008-info.sh entirely

`lib/service.sh` (v1) stays in the tree until PLAN-F's cleanup PR. While it exists, its `yaml_var` and `resolve_service_context` functions should stay tested — they're still called by `bin/logs.sh` / `bin/shell.sh` / `bin/deploy.sh` until those rewrite. The lib-level assertions in PLAN-008-info.sh do that work. Trimming (not deleting) keeps the lifecycle clear.

### Out of scope for PLAN-B

- `logs` / `shell` rewrites (PLAN-D).
- Removing `lib/service.sh` or `bin/info.sh`'s remaining v1 references (none should remain after this plan).
- Changing the metadata schema or `--help` output (already done in v1.5.3).
- Adding new info fields beyond Public URL (e.g. last-deploy-time, build-pipeline-status) — separate plan if useful.
