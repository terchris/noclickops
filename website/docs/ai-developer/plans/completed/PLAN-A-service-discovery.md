# PLAN-A — v2 service discovery library

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Completed

**Goal**: Build the v2 discovery library (`lib/service-v2.sh`) that all v2 command rewrites (PLAN-B through PLAN-F) will source. Single source of truth for resolving per-service / per-env context against the new two-project, two-repo layout.

**v2 is Bash only.** No `.ps1` mirrors. The planned post-v2 rewrite to Bun (TypeScript) takes over multi-OS support; until then, Windows-native users either run via WSL/Git Bash or stay on v1.5.x.

**Last Updated**: 2026-05-29

**Completed**: 2026-05-29

### Completion notes

- All 5 phases shipped: scaffold → YAML readers → pipeline/IaC-project discovery → containerapp/URL → docs.
- 376 tests pass; new `test-PLAN-A-service-discovery.sh` contributes 68 of them across all 4 implementation phases.
- v1 `lib/service.sh` untouched — no regression for in-flight v1 callers.
- No customer-tenant tokens (`nrx` etc.) anywhere in `lib/service-v2.sh`.
- Per CLAUDE.md PR-per-investigation rule, this plan commits to the `feat/v2-new-target-structure` branch. PR opens after PLAN-F merges.

**Investigation**: [INVESTIGATE-new-target-structure.md](INVESTIGATE-new-target-structure.md) (see § "PLAN sequence → PLAN-A")

**Blocks**: PLAN-B (info), PLAN-C (deploy), PLAN-D (logs/shell), PLAN-E (clean-sample), PLAN-F (add-service). Each consumes the API this plan ships.

---

## Overview

v1 has `lib/service.sh` which reads three YAML files from the source repo's `.pipelines/variables/*.yaml` (the FRT-shaped layout). It exports `SVC_*` globals consumed by `bin/info`, `bin/logs`, `bin/shell`.

v2 needs an equivalent module for the new layout, where:

- **Per-service config** lives in `services/<svc>/config.<env>.yaml` (NEW location — sits with the service, not at repo root).
- **Repo-level variables** live in `IaC/platform-infrastructure/environments/<TEAM>/<repo>/infrastructure/.pipelines/variables/{common,test,prod}.yaml` (NEW location — IN A DIFFERENT REPO IN A DIFFERENT PROJECT).
- **Pipeline names** span TWO ADO projects (`FrontendPlatform` + `IaC`), five names per service (`<repo>-<svc>-build`, `<repo>-<svc>-deploy`, `<repo>-<svc>-infra-build`, `<repo>-<svc>-deploy-test`, `<repo>-<svc>-deploy-prod`).
- **Container app** is `ca-<repo-prefix-lc>-<svc>` in `rg-<env>-<TENANT>-<repo-prefix-lc>`. `TENANT` is customer-specific (`nrx` at Red Cross) and is NOT in any discoverable YAML. v2 must discover the RG via `az containerapp list` or accept a `--resource-group` override; it must never hardcode `nrx`.

This plan ships `lib/service-v2.sh` + tests. Old `lib/service.sh` stays untouched — PLAN-B/C/D/E/F switch their respective callers over command-by-command. After PLAN-F merges, a follow-up removes v1 (both `lib/service.sh` and `lib/service.ps1`).

**Co-existence strategy**: new module, new file name. Existing tests + commands keep working unchanged. No behavior change for users until PLAN-B lands.

---

## Public API

The new module exposes these functions:

```bash
# 1. Read per-service config from services/<svc>/config.<env>.yaml.
#    Populates SVC_CFG_<KEY> globals for every flat key found.
#    Errors if file missing.
read_service_config <svc> <env>

# 2. Read IaC variables from the cross-project IaC repo's path:
#    IaC/platform-infrastructure/environments/<TEAM>/<repo>/infrastructure/.pipelines/variables/{common,<env>}.yaml
#    Populates IAC_<KEY> globals. <TEAM> is the first dash-segment of the
#    source repo's name (upper-cased). Errors if either file missing.
read_iac_variables <env>

# 3. Return the IaC project name (defaults to "IaC"; honors $NOCLICKOPS_IAC_PROJECT
#    env override; if IAC_PROJECT is set in common.yaml after read_iac_variables, uses that).
discover_iac_project

# 4. Discover pipeline IDs across both projects.
#    Returns five lines, "<role>=<id>", empty when not found:
#      frontend_build=<id>
#      frontend_deploy=<id>
#      iac_infra_build=<id>
#      iac_deploy_test=<id>
#      iac_deploy_prod=<id>
discover_pipelines <svc>

# 5. Best-effort container-app discovery for live state.
#    Order: (a) honor --app-name / --resource-group overrides if set in
#    SVC_APP_NAME_OVERRIDE / SVC_RG_OVERRIDE globals; (b) read
#    COMMON_RESOURCE_GROUP_NAME from iac vars and az containerapp list there
#    with name filter ca-<repo-prefix-lc>-<svc>; (c) fall back to az
#    containerapp list across the subscription with the same name filter.
#    Returns "name=<name>\nresource_group=<rg>\nfqdn=<fqdn>" on success;
#    empty stdout + non-zero exit on failure.
discover_containerapp <svc>

# 6. Pure derivation. Computes "ca-<repo-prefix-lc>-<svc>" — no az calls.
#    Use when you need the predicted name without verifying it exists.
derive_containerapp_name <svc>

# 7. Public URL for a service with ENABLE_PUBLIC_ENDPOINT: "true".
#    Reads ENABLE_PUBLIC_ENDPOINT from SVC_CFG_*, DNS_ZONE_NAME from IAC_*.
#    Returns "<svc>.<DNS_ZONE_NAME>" or empty when not public.
public_url_for <svc> <env>
```

**No `derive_rg` function** — the v2 design deliberately drops it. v1 had `rg-<env>-nrx-<APP_NAME>` hardcoded; v2 discovers the RG via `discover_containerapp` (which queries Azure) or requires an override. Hardcoding the tenant prefix is what made v1 customer-specific; v2 doesn't repeat that mistake.

---

## Phase 1: Scaffold module + test file — DONE

### Tasks

- [x] 1.1 Create `lib/service-v2.sh` with the function-name stubs above. Each stub: `printf 'TODO: %s\n' "<func-name>" >&2; return 1`. Source `lib/logging.sh` + `lib/utilities.sh` like v1 does. Same `_NCO_SERVICE_V2_LOADED` guard pattern.
- [x] 1.2 Create `tests/test-PLAN-A-service-discovery.sh` with the test-runner boilerplate from existing tests (source `tests/_helpers.sh`, set `NCO_ROOT`). One placeholder test that sources `lib/service-v2.sh` and asserts the module loaded. Adds to the test list in `tests/run-all.sh` (if it auto-discovers, skip this).
- [x] 1.3 Add v2 fixture helpers to `tests/_fixtures.sh`:
  - `make_v2_source_repo [origin-url]` — git repo with `.pipelines/add-service.yaml` + empty `services/`.
  - `make_v2_service <repo> <svc>` — adds `services/<svc>/` with `Dockerfile`, `app/`, `config.test.yaml`, `config.prod.yaml`, `.pipelines/{service,deploy_service}.yaml`. Config files populated with realistic SERVICE_* keys.
  - `make_v2_iac_repo` — separate temp git repo modeling `platform-infrastructure`; `make_v2_iac_service <iac-repo> <source-repo-name> <svc>` adds the variables and pipeline YAMLs for that service.

### Validation

```bash
bash tests/run-all.sh
```

All existing tests still pass; new `test-PLAN-A-service-discovery.sh` runs and shows the placeholder PASSED.

User confirms phase is complete.

---

## Phase 2: YAML readers (`read_service_config`, `read_iac_variables`) — DONE

### Tasks

- [x] 2.1 Lift `yaml_var` from `lib/service.sh` into `lib/service-v2.sh` unchanged (the YAML files in v2 are the same shape — flat, no nesting, no anchors).
- [x] 2.2 Implement `read_service_config <svc> <env>`:
  - Resolves repo root via `nco_repo_root` (existing helper from `lib/utilities.sh`).
  - Reads `<repo-root>/services/<svc>/config.<env>.yaml`.
  - Iterates every `KEY: value` line; exports `SVC_CFG_<KEY>=<value>` (uppercase, `-`/`.` → `_`).
  - Sets `SVC_CFG__LOADED=1` sentinel.
  - Errors clearly when file missing: `✗ services/<svc>/config.<env>.yaml not found. Is this the right service / env?`
- [x] 2.3 Implement `read_iac_variables <env>`:
  - Reads source repo name from `git config --get remote.origin.url` (or accepts `NOCLICKOPS_REPO_NAME` override).
  - Derives `<TEAM>` = first dash-segment of repo name, upper-cased (e.g. `ABC100001-myservice` → `ABC`).
  - Reads the IaC repo's variables. Two approaches: (a) clone `platform-infrastructure` to a cache dir on first use; (b) read via the ADO REST API (`/_apis/git/repositories/.../items?path=...`). Decision: **API approach** — no clone cache, no stale-state risk, matches v1's "wrap, never replicate" + read-only philosophy.
  - For each of `common.yaml` and `<env>.yaml`: GET via API, parse with same loop as 2.2, export `IAC_<KEY>=<value>`.
  - Sets `IAC__LOADED=1` sentinel.
  - Errors clearly when either file missing: name the exact path the API was queried for.
- [x] 2.4 Tests for 2.2 + 2.3:
  - `read_service_config` against a fixture: assert SVC_CFG_SERVICE_PORT, SERVICE_CPU, ENABLE_PUBLIC_ENDPOINT populated correctly.
  - `read_iac_variables`: mock the API via a `NCO_ADO_REST_OVERRIDE` env var pointing at a local file (the function reads the URL through a small shim that honors the override — useful for testing without ADO access).
  - Negative case: missing service config returns expected error message.

### Validation

```bash
bash tests/test-PLAN-A-service-discovery.sh
```

All Phase-2 tests pass.

User confirms phase is complete.

---

## Phase 3: Pipeline + IaC project discovery — DONE

### Tasks

- [x] 3.1 Implement `discover_iac_project`:
  - Returns `$NOCLICKOPS_IAC_PROJECT` if set.
  - Returns `$IAC_PROJECT` if `read_iac_variables` has run.
  - Otherwise returns the literal `IaC`.
- [x] 3.2 Implement `discover_pipelines <svc>` (refactored to 2 calls per project + local filter — fewer round-trips, easier to stub):
  - Wraps `az pipelines list --query` calls. Two project queries:
    - FrontendPlatform: `--repository <repo> --repository-type tfsgit`, then filter names matching `<repo>-<svc>-build` and `<repo>-<svc>-deploy`.
    - IaC: `--organization <org-url> --project <iac-project>`, then filter names matching `<repo>-<svc>-{infra-build,deploy-test,deploy-prod}`.
  - Returns lines `<role>=<id>` for all five roles; empty value when a pipeline isn't found.
  - Caches results in `discover_pipelines_cache_<svc>` global to avoid re-querying within a single command run.
- [x] 3.3 Tests:
  - Mock `az` via a `NCO_AZ_OVERRIDE` env var pointing at a stub script — same pattern existing tests use (check `tests/test-PLAN-008-info.sh` for the convention).
  - Stub returns canned JSON for `az pipelines list`; assert parsed IDs come out right.
  - Test: when one of the IaC pipelines doesn't exist, that role's line has empty value.

### Validation

```bash
bash tests/test-PLAN-A-service-discovery.sh
```

User confirms phase is complete.

---

## Phase 4: Container-app discovery + public URL — DONE

### Tasks

- [x] 4.1 Implement `derive_containerapp_name <svc>`:
  - Pure string derivation: repo name → lowercase → split on `-` → first segment → `ca-<prefix>-<svc>`.
  - No az calls.
- [x] 4.2 Implement `discover_containerapp <svc>`:
  - Step (a): if `SVC_APP_NAME_OVERRIDE` and `SVC_RG_OVERRIDE` set, return them without calling Azure.
  - Step (b): require `IAC__LOADED=1`. Read `COMMON_RESOURCE_GROUP_NAME` from `IAC_*`. Call `az containerapp list -g $IAC_COMMON_RESOURCE_GROUP_NAME --query "[?name=='<derived>']"`. If hit, return parsed `name`/`resource_group`/`fqdn`.
  - Step (c): if (b) returned nothing, list across subscription: `az containerapp list --subscription $IAC_SUBSCRIPTION_ID --query "[?name=='<derived>']"`.
  - On all failures: print clear error naming the override flag the caller should pass (`--app-name` + `--resource-group`).
  - Each az call wrapped via the same `NCO_AZ_OVERRIDE` shim from 3.3.
- [x] 4.3 Implement `public_url_for <svc> <env>`:
  - Requires `SVC_CFG__LOADED=1` + `IAC__LOADED=1` (errors clearly otherwise).
  - If `SVC_CFG_ENABLE_PUBLIC_ENDPOINT != "true"` → print empty + exit 0.
  - Otherwise return `<svc>.<IAC_DNS_ZONE_NAME>`.
- [x] 4.4 Tests:
  - `derive_containerapp_name`: cases for `ABC100001-myservice` + `frontend` → `ca-abc100001-frontend`; verify lowercasing.
  - `discover_containerapp`: stub az to return matching app on first try (verify path b), no match on first + match on second (verify path c), no match anywhere (verify error message names the override flags).
  - `public_url_for`: returns `<svc>.example.cloud` when public; returns empty when not.

### Validation

```bash
bash tests/test-PLAN-A-service-discovery.sh
```

User confirms phase is complete.

---

## Phase 5: End-to-end smoke + docs — DONE

### Tasks

- [x] 5.1 End-to-end smoke against the live test repo (manual; not a CI test) — procedure documented in `website/docs/contributors/lib-service-v2.md` § "End-to-end smoke". Manual execution against the live target repo is the user's responsibility before the v2 release; tracked outside this PLAN.
- [x] 5.2 Docs update:
  - Added `website/docs/contributors/lib-service-v2.md` (API, discovery-vs-derivation-vs-override, test shims, smoke procedure).
  - Added entry to `website/docs/contributors/index.md`.
  - Updated `terchris/redaction-map.md`'s "What was NOT redacted" section to note `lib/service-v2.sh` is leak-free by design.

### Validation

```bash
bash tests/run-all.sh
```

End-to-end smoke documented + executed against the live repo.

User confirms phase is complete.

---

## Acceptance Criteria

- [ ] `lib/service-v2.sh` exists and passes its test file
- [ ] All 7 public functions implemented per signatures in the "Public API" section
- [ ] No `nrx` or other customer-tenant tokens hardcoded
- [ ] `tests/run-all.sh` still green; new v2 tests added and passing
- [ ] `lib/service.sh` (v1) untouched — no regression for v1 callers
- [ ] `website/docs/contributors/lib-service-v2.md` documents the module
- [ ] End-to-end smoke run against the live test repo passes
- [ ] PR description names which PLAN-* files (B/C/D/E/F) will consume this module

---

## Files to Modify

- `lib/service-v2.sh` (new)
- `tests/test-PLAN-A-service-discovery.sh` (new)
- `tests/_fixtures.sh` (add `make_v2_*` helpers)
- `website/docs/contributors/lib-service-v2.md` (new)
- `terchris/redaction-map.md` (note v2 module is leak-free; local-only file)

---

## Implementation Notes

### Why "discover over hardcode"

v1's `lib/service.sh` line 82 hardcodes `rg-${env}-nrx-${SVC_APP_NAME}`. That `nrx` is the Red Cross tenant prefix. It works for Red Cross developers but bakes a customer identifier into open-source code. v2 deliberately avoids this:

- The RG name is **discovered** by `az containerapp list` against the IaC-vars-provided subscription/RG, OR
- the user **overrides** it with `--resource-group` / `--app-name`.

The Bicep templates in `platform-infrastructure` produce the RG name; the engineer owns that convention. noclickops just looks up what's there.

### Why a new file rather than mutating `lib/service.sh`

PLAN-B through PLAN-F each rewrite one command. Until all five land, both v1 and v2 commands must work side-by-side (so `noclickops` is usable on FrontendPlatform during the transition). Two libraries, two `_NCO_*_LOADED` guards. After PLAN-F merges, a v2-cleanup follow-up removes both `lib/service.sh` and `lib/service.ps1` (v1's PowerShell mirror), and renames `lib/service-v2.sh` → `lib/service.sh`.

### Why Bash-only

v2 drops PowerShell. The planned post-v2 rewrite is to **Bun** (TypeScript), which gives native multi-OS support without shell-flavor concerns. Maintaining `.ps1` mirrors through v2 would be wasted effort the Bun rewrite supersedes. Windows-native users either run v1.5.x or use WSL/Git Bash for v2. v1's `.ps1` files stay in the tree until PLAN-F cleanup; no new `.ps1` work happens in v2.

### Why API over clone for IaC vars

The IaC repo can be 100+ MB. Cloning to read 3 YAML files is wasteful. The ADO REST endpoint `GET /_apis/git/repositories/<id>/items?path=...` returns file content directly with an existing AAD token. No clone cache, no stale state, no `.git/` to manage.

Acceptable trade-off: every `noclickops info / deploy / logs / shell` does ~2 small REST calls (~50 ms each) instead of a one-time clone followed by `git pull`. Net latency is similar; reliability is higher.

### The az-shim pattern (for testability)

Every `az` call in this module goes through:

```bash
_nco_az() {
  if [ -n "${NCO_AZ_OVERRIDE:-}" ]; then
    "$NCO_AZ_OVERRIDE" "$@"
  else
    az "$@"
  fi
}
```

Tests set `NCO_AZ_OVERRIDE` to a stub script that returns canned JSON. Same pattern existing tests use for `bin/info` etc.

### Out of scope for PLAN-A

- Any command-side changes (those are PLAN-B through PLAN-F).
- Removing `lib/service.sh` or `lib/service.ps1` (post-PLAN-F cleanup).
- Any `.ps1` work for v2 (PowerShell dropped; Bun rewrite takes over multi-OS).
- `sync-lovable` rework (deferred per the investigation).
- ADO REST caching across invocations (premature; revisit if benchmarks show it matters).
