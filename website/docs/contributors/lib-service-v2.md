---
title: lib/service-v2.sh
sidebar_position: 2
---

# `lib/service-v2.sh` — v2 service discovery

The discovery module that v2 commands use to resolve per-service / per-env context against the new two-project / two-repo layout.

**Status**: ships in v2. v1 (`lib/service.sh`) stays alongside until every command rewrites to v2; a post-v2 cleanup PR then removes both `lib/service.sh` and `lib/service.ps1`.

---

## Why "discovery vs derivation vs override"

The v1 lib hardcoded `rg-<env>-nrx-<APP_NAME>` — the `nrx` literal was the customer's tenant prefix baked into open-source code. v2 deliberately avoids that pattern.

Three resolution strategies, picked per field by which one is reliable:

| Strategy | When | Examples |
|---|---|---|
| **Derivation** | The value is fully determined by other values noclickops already knows (repo name, env) — no Azure call needed | `derive_containerapp_name` → `ca-<repo-prefix-lc>-<svc>` |
| **Discovery** | The value lives in Azure and noclickops queries for it (best-effort; tolerates the user not having access) | `discover_containerapp` (queries `az containerapp list`), `discover_pipelines` (queries `az pipelines list`) |
| **Override** | The user passes a value explicitly (CLI flag → env var → function param) | `SVC_APP_NAME_OVERRIDE`, `SVC_RG_OVERRIDE`, `NOCLICKOPS_IAC_PROJECT`, `NOCLICKOPS_IAC_REPO` |

Functions that need a value typically try in this order:
1. Override (immediate return — no Azure call).
2. Discovery (one or more `az` calls; tolerates failure).
3. Fall back to next strategy or `die` with a clear "set `<env-var>` to override" message.

**No customer-tenant string (e.g. `nrx`) appears anywhere in the v2 module.** All such strings are either discovered from Azure at runtime or read from the engineer-owned IaC variable files.

---

## Public API

| Function | Purpose | Side effect / output |
|---|---|---|
| `read_service_config <svc> <env>` | Read `services/<svc>/config.<env>.yaml` from target repo | Exports `SVC_CFG_<KEY>=<value>`; sets `SVC_CFG__LOADED=1`. Dies on missing file. |
| `read_iac_variables <env>` | Read `common.yaml` + `<env>.yaml` from `IaC/platform-infrastructure/environments/<TEAM>/<repo>/infrastructure/.pipelines/variables/` via ADO REST | Exports `IAC_<KEY>=<value>`; sets `IAC__LOADED=1`. Dies on REST failure or missing file. |
| `discover_iac_project` | Pick the IaC project name | Echoes the name. Precedence: `$NOCLICKOPS_IAC_PROJECT` → `$IAC_IAC_PROJECT` (from common.yaml) → `IaC`. |
| `discover_pipelines <svc>` | Find all five pipelines (FrontendPlatform + IaC) for a service | Echoes 5 lines `<role>=<id>` — empty value when not found. |
| `derive_containerapp_name <svc>` | Pure derivation — no `az` calls | Echoes `ca-<repo-prefix-lc>-<svc>`. |
| `discover_containerapp <svc>` | Look up the live container app (override → IAC common RG → subscription-wide) | Echoes 3 lines `name=`/`resource_group=`/`fqdn=`. Dies if none of the strategies hit. |
| `public_url_for <svc> <env>` | URL when `ENABLE_PUBLIC_ENDPOINT: "true"` | Echoes `<svc>.<IAC_DNS_ZONE_NAME>` or empty when not public. Dies if prereqs not loaded. |

Requires `read_service_config` to run before `public_url_for`; requires `read_iac_variables` before `discover_containerapp` and `public_url_for`.

---

## Globals exported

After `read_service_config <svc> <env>`:
- `SVC_CFG_<KEY>` — one per key in the service config file (e.g. `SVC_CFG_SERVICE_PORT`, `SVC_CFG_ENABLE_PUBLIC_ENDPOINT`, `SVC_CFG_OKTA_ISSUER`).
- `SVC_CFG__LOADED=1`

After `read_iac_variables <env>`:
- `IAC_<KEY>` — one per key across both `common.yaml` and the per-env file. Common keys: `IAC_APP_NAME`, `IAC_APPLICATION_NAME`, `IAC_CONTAINER_REGISTRY_NAME`, `IAC_REPO_NAME`, `IAC_TEAM_NAME`, `IAC_IAC_PROJECT`, `IAC_IAC_REPO`, `IAC_ENVIRONMENT`, `IAC_SUBSCRIPTION_ID`, `IAC_COMMON_RESOURCE_GROUP_NAME`, `IAC_DNS_ZONE_NAME`, `IAC_KEY_VAULT_NAME`.
- `IAC__LOADED=1`

The `IAC_IAC_PROJECT` and `IAC_IAC_REPO` double-prefix is intentional — the YAML keys are `IAC_PROJECT` / `IAC_REPO`, and the auto-prefix adds `IAC_` on top. Functional, just ugly.

---

## Test shims

Both Azure-facing calls go through wrappers that tests override:

```bash
_nco_az ...           # wraps `az`. Set NCO_AZ_OVERRIDE=<stub-script> to redirect.
_nco_ado_rest_get URL # wraps the REST GET. Set NCO_ADO_REST_OVERRIDE=<stub-script>.
```

Test fixtures (in `tests/_fixtures.sh`):

- `make_v2_source_repo [origin]` — fake source repo with `services/` + `.pipelines/add-service.yaml`.
- `make_v2_service <repo> <svc> [public]` — adds a service folder with config + Dockerfile.
- `make_v2_iac_repo <team> <repo-name>` — fake IaC repo with the variables YAMLs.
- `v2_stub_ado_rest_path` — emits a stub script that maps `?path=` URLs to files inside `$NCO_TEST_IAC_ROOT`.
- `v2_stub_az_path` — emits a stub script that dispatches `az ...` to fixture files in `$NCO_TEST_AZ_FIXTURES` keyed by subcommand + `--project` / `--resource-group` / `--subscription`.

See `tests/test-PLAN-A-service-discovery.sh` for the canonical usage pattern.

---

## End-to-end smoke (against a real target repo)

This isn't a CI test — it requires `az login` + access to a real new-layout repo and the IaC project. Run it manually after any change that could affect live discovery.

```bash
cd /path/to/your/source/repo          # e.g. ABC100001-myservice
. /path/to/noclickops/lib/paths.sh
. /path/to/noclickops/lib/service-v2.sh

# 1. Read both config layers
read_service_config frontend test
read_iac_variables  test

# 2. Inspect the loaded state
env | grep '^SVC_CFG_' | sort
env | grep '^IAC_'     | sort

# 3. Discover pipelines (1 line per role, empty values OK for not-yet-created)
discover_pipelines frontend

# 4. Derive + (best-effort) discover the container app
derive_containerapp_name frontend
discover_containerapp     frontend    # may die if the user lacks Reader on the sub

# 5. Compute the public URL (empty if ENABLE_PUBLIC_ENDPOINT != "true")
public_url_for frontend test
```

What "good" looks like:
- All five pipeline roles return non-empty IDs (matches `az pipelines list`).
- `derive_containerapp_name` matches the actual deployed container app name (e.g. `ca-<repo-prefix>-frontend`).
- `discover_containerapp` returns the live FQDN (only works if user has Reader on the deploy sub).
- `public_url_for frontend test` returns `frontend.<dns-zone>` for public services.

---

## Related

- [Target layout reference](./target-layout-reference.md) — the empirical layout description this module targets.
- [INVESTIGATE-new-target-structure](/docs/ai-developer/plans/backlog/INVESTIGATE-new-target-structure) — the v2 redesign that motivated this module.
- PLAN-B / PLAN-C / PLAN-D / PLAN-E / PLAN-F — the command rewrites that consume this module's API.
