# Investigate: noclickops v2 targets the new ADO repo layout

> **IMPLEMENTATION RULES:** Before implementing the plans that come out of this investigation, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Backlog — scope locked, ready to draft PLANs

**Goal**: Cut over `noclickops` from the FRT-shaped repo layout (v1.x) to the new layout used by `copier-add-service`-generated repos like `ABC100001-myservice`. v2 supports the new layout only. v1.x stays available for FRT users via the existing tag.

**Last Updated**: 2026-05-29

**Surveyed target**: `/Users/terje.christensen/learn/redcross/ABC100001-myservice` (ADO repo `ExampleOrg/FrontendPlatform/ABC100001-myservice`, one service `services/postgrest/`).

---

## Design principle

**The Azure engineer owns the target-repo layout.** Repo layout, per-env variable names, pipeline names, container-app naming, RG naming, subscription assignment — all of that is set by the Azure engineer (via `copier-add-service` and Azure DevOps). noclickops's job is to **discover what exists** and **trigger / call** it. We:

- Do NOT clone `copier-add-service` to read the canonical schema — the schema is whatever's deployed in the wild.
- Do NOT invent naming conventions — we query Azure DevOps to find what's actually there.
- Do NOT modify the target repo's structure — `add-service`, `deploy`, etc. trigger pipelines; we never bypass them.
- Accept overrides (`--subscription`, `--resource-group`, `--app-name`, `--pipeline-name`) for values that can't be discovered.
- Degrade gracefully — `info` prints "not discoverable; pass `--<flag>` to override" rather than guessing.

This is the existing "wrap, never replicate" rule applied to layout: we wrap whatever the upstream pipeline definitions encode; we don't replicate authority over them.

---

## The target layout (v2)

The new layout spans **two ADO projects** and **two git repos** per service. noclickops must orchestrate across all of them.

### Project 1 — `FrontendPlatform` (the developer's source repo)

```text
<repo>/                              # e.g. ABC100001-myservice
  .pipelines/
    add-service.yaml                 # ADO pipeline definition (the request creator)
  services/
    <svc>/                           # e.g. frontend
      Dockerfile
      app/                           # service source code
      config.test.yaml               # per-env config — LIVES WITH THE SERVICE
      config.prod.yaml
      README.md
      .pipelines/
        service.yaml                 # BUILD pipeline (docker build, trivy scan, publish artifact)
        deploy_service.yaml          # DEPLOY pipeline (publishes deployment-package-{env})
```

Pipelines registered in FrontendPlatform per service:

- `<repo>-add-service` — opens a PR with the service folder and triggers the IaC handoff
- `<repo>-<svc>-build` — builds the image, publishes `deploy-package`
- `<repo>-<svc>-deploy` — packages `deploy-package` + config → publishes `deployment-package-{env}` (artifact only — does NOT touch Azure)

### Project 2 — `IaC` (infrastructure / deployer; engineer-owned)

```text
platform-infrastructure/             # git repo IaC owns
  environments/
    <PREFIX>/                        # TCH / TST / HVI / FRT / CMS / etc. (from repo-name prefix)
      <repo>/                        # ABC100001-myservice
        infrastructure/              # repo-level Bicep + ARM templates
        services/
          <svc>/                     # frontend
            .pipelines/
              build_service.yaml             # ACR push for this svc
              test_deploy_service.yaml       # ARM deploy → test sub
              prod_deploy_service.yaml       # ARM deploy → prod sub
            <service-bicep + params>
```

Pipelines registered in IaC per service:

- `<repo>-infra-add-service` — auto-triggered by FrontendPlatform's `<repo>-add-service`; opens a PR in `platform-infrastructure` adding the YAML + Bicep files for the new service
- `<repo>-<svc>-infra-build` — pushes the docker image to ACR
- `<repo>-<svc>-deploy-test` — runs ARM template against the test subscription (the actual Azure deploy)
- `<repo>-<svc>-deploy-prod` — same for prod

### How a service goes from "doesn't exist" to "live"

End-to-end flow with no auto-resource-trigger wiring (first-time path):

```text
1. dev: noclickops add-service <svc>
2.  ↳ trigger FrontendPlatform: <repo>-add-service
3.  ↳ that opens PR-A in the source repo (service code; e.g. PR #4831)
4.  ↳ that triggers IaC: <repo>-infra-add-service (auto-handoff)
5.  ↳ that opens PR-B in platform-infrastructure (deploy YAML; e.g. PR #4832)
6.  → merge BOTH PRs (PR-A and PR-B)
7. dev: noclickops deploy <svc> <env>
8.  ↳ trigger FrontendPlatform: <repo>-<svc>-build → <repo>-<svc>-deploy
9.  ↳ trigger IaC: <repo>-<svc>-infra-build → <repo>-<svc>-deploy-test
10. ARM deploys container app to rg-<env>-nrx-<repo-prefix-lc>
11. Front Door custom-domain validation + DNS propagation + managed cert (~30-90 min on first deploy)
12. <svc>.example.cloud serves 200
```

For subsequent (non-first) deploys, FrontendPlatform's `-deploy` succeeding fires a resource-trigger on IaC's `deploy-test` automatically — only steps 7-10 happen, in ~3-10 min. First-time path requires explicit `-infra-build` first because the resource trigger hasn't yet activated for the brand-new pipeline definition.

Generated by `copier-add-service`. The Azure engineer owns ALL of this — both repos, both projects, all the Bicep, all the pipeline YAML. noclickops's job is to **discover what exists in each project** and **call what's already there**.

---

## Discovered facts (2026-05-29 — `az` queries against the test repo)

### Pipeline naming (confirmed)

`az pipelines list --repository <repo>` for `ABC100001-myservice` returned exactly:

| ID | Name |
|---|---|
| 1125 | `<repo>-add-service` |
| 1128 | `<repo>-<svc>-build` |
| 1129 | `<repo>-<svc>-deploy` |

Convention: every service has a `-build` + `-deploy` pair. `noclickops deploy <svc> <env>` triggers `<repo>-<svc>-deploy` (not `-build`). The deploy pipeline's `targetEnvironment` parameter selects test vs prod.

### Per-env config variables (confirmed)

Read from `services/postgrest/config.test.yaml`:

- `SERVICE_PORT`, `SERVICE_CPU`, `SERVICE_MEMORY`, `SERVICE_MIN_REPLICAS`, `SERVICE_MAX_REPLICAS`, `SERVICE_HEALTH_CHECK_PATH`, `SERVICE_HEALTH_PROBE_PORT`
- `ENABLE_PUBLIC_ENDPOINT`, `PERSISTENT_STORAGE`
- App-specific (varies per service): `OKTA_ISSUER`, `APP_BASE_URL` (postgrest-only).

`SERVICE_NAME` is set in the build pipeline YAML (`services/<svc>/.pipelines/service.yaml`), but it's identical to the folder name (`services/<svc>/` → `<svc>`) — noclickops derives it from the path, doesn't read the YAML.

### Subscription (discoverable via service connection)

ADO pipeline-level variables are empty for all three pipelines. Subscription is encoded in a service connection:

```text
$ az devops service-endpoint list --query "[?type=='azurerm'].{name:name, sub:authorization.parameters.scope}"
myteam-frontend-test-sp  /subscriptions/3aec5ff4-...-c36f2bf3ca2d
myteam-frontend-prod-sp  /subscriptions/<prod-id>
myteam-frontend-acr-sp   <ACR scope>
```

Convention: `<org-prefix>-<env>-sp`. noclickops parses `authorization.parameters.scope` to extract the subscription ID per env.

### IaC project + cross-project pipelines (the deployer)

The actual Azure deploy lives in the **IaC** project (separate from FrontendPlatform). Discovered by listing pipelines per project:

```text
az pipelines list --project IaC --query "[?contains(name, '<repo>')].name"
ABC100001-myservice-CD
ABC100001-myservice-infra-add-service
ABC100001-myservice-postgrest-infra-build
ABC100001-myservice-postgrest-deploy-test
ABC100001-myservice-postgrest-deploy-prod
ABC100001-myservice-frontend-infra-build
ABC100001-myservice-frontend-deploy-test
ABC100001-myservice-frontend-deploy-prod
```

Convention: `<repo>-<svc>-infra-build`, `<repo>-<svc>-deploy-{test|prod}` in the IaC project. The pipelines point at YAML files in the `platform-infrastructure` git repo (also in IaC).

### Resource group naming: CONFIRMED

From the failed first-deploy log (run 28537): `rg-test-myteam-abc100001`. Convention: **`rg-<env>-nrx-<repo-prefix-lc>`** (repo-prefix = the part before the first `-` in the repo name, lowercased).

### Container-app naming: still hypothesised as `<svc>`

The Front Door routes `<svc>.example.cloud` → `<svc>` backend. A half-broken peer (`v2service.example.cloud` → HTTP 504) demonstrates Front Door IS routing on `<svc>` even when the backend is unreachable, which only makes sense if the backend name matches `<svc>`. Confirming requires Reader on the test sub OR a successful end-to-end deploy that we can `az containerapp list` against — pending the frontend HTTPS-200 milestone.

### Deploy mechanism: ARM templates

From the deploy-test pipeline log: deploys via the `AzureResourceManagerTemplateDeployment@3` task. Inputs come from a `<svc>-infra` artifact (built by `<svc>-infra-build`) containing `template.json` + `template.params.json`. So Bicep is compiled into JSON ARM templates upstream and shipped as an artifact between the build and deploy pipelines.

### `add-service` is a TWO-PR flow

Observed during the empirical test:

1. FrontendPlatform's `<repo>-add-service` runs (~10-30s, just publishes a `deployment-request` artifact).
2. Downstream automation (in IaC) consumes the request → opens **PR-A** in the source repo (`<repo>`) titled "Add service `<svc>`" containing the new service folder + Dockerfile + `service.yaml`. Source branch: `add-service-<svc>`.
3. Simultaneously triggers IaC's `<repo>-infra-add-service` → opens **PR-B** in `platform-infrastructure` titled "Add service `<svc>`" containing the IaC YAML + Bicep for the new service.
4. **Both PRs must be merged.** Branch policies on `platform-infrastructure/main` are empty — self-approval works.

Real evidence of how often this trips up developers: there are open PR-B's in `platform-infrastructure` going back to April 2026 (`Add service CopierTest`, `Add service testingv3`, `Add service newprojectv2`). Each represents a service whose deploy is silently blocked because nobody merged PR-B.

### Deploy is a FOUR-pipeline orchestration (first-time)

For first-time deploys, the developer triggers and the pipelines fire in this order:

```text
FrontendPlatform/<repo>-<svc>-build         (~1-2 min, publishes deploy-package)
FrontendPlatform/<repo>-<svc>-deploy        (~30s, publishes deployment-package-test)
IaC/<repo>-<svc>-infra-build                (~3 min, pushes image to ACR)  ← required for first time only
IaC/<repo>-<svc>-deploy-test                (~6 min, ARM deploy creates container app)
```

For subsequent deploys, the FrontendPlatform `-deploy` succeeding fires a resource-trigger on IaC's `deploy-test` automatically (and `infra-build` typically isn't needed if the image tag hasn't moved). So same-day re-deploys are just 2 pipelines + auto-trigger.

The first-time gotcha: **the resource-trigger on a freshly-registered IaC `deploy-test` pipeline doesn't auto-wire until that pipeline has run at least once manually.** Combined with the missing `infra-build`, first deploys require manual triggering of both IaC pipelines.

### Branch policies + auto-merge of PR-B

`platform-infrastructure/main` has empty branch policies (verified via `az repos policy list`). Self-approval via `az repos pr set-vote --vote approve` is sufficient; merge via `az repos pr update --status completed --squash` works.

This means **noclickops can auto-merge PR-B** if it has write access on `platform-infrastructure` — same way it auto-merges PR-A in the source repo today.

### Public-endpoint architecture

All `*.example.cloud` services in `FrontendPlatform` route through a single Azure Front Door per environment:

```text
<svc>.example.cloud
  → CNAME test-endpoint-frontend-<hash>.z02.azurefd.net      (Azure Front Door, one endpoint for the env)
  → CNAME mr-z02.tm-azurefd.net
  → <Front Door IP>
```

Cert is a Front Door-managed DigiCert / GeoTrust SAN cert with `CN=<svc>.example.cloud`.

**First-time deploy timing** ("firewall registration" the engineer flagged): adding a new custom domain to the Front Door + DNS validation + managed-cert provisioning takes ~30–60 minutes. Subsequent deploys (same domain, new image) are fast — Front Door routing + cert are already in place.

Implication for noclickops:
- The public URL is always `<svc>.example.cloud` for any service with `ENABLE_PUBLIC_ENDPOINT: "true"`. Discoverable without Azure access — just read `config.<env>.yaml` and apply the convention.
- For first-time public deploys, see PLAN-watch-live-deploy for the layered polling that handles the ~60 min wait.

---

## v1.5.2 against the new layout — observed failure modes

Captured 2026-05-29 against the live `ABC100001-myservice` repo. These are the exact messages a user sees today; v2 fixes each one.

| Command | Exact output |
|---|---|
| `noclickops` | ✓ — works |
| `--help` | ✓ — works |
| `update` | ✓ — works |
| `status` | ✓ — works (listed all 4 recent runs cleanly) |
| `status <run-id>` | ✓ — works |
| `add-service <svc>` | Trigger pipeline ✓; auto-merge step finds no PR (downstream async; PR appears ~1–2 min later) |
| `info <svc> <env>` | `✗ Repo-level variables missing: <repo>/.pipelines/variables/common.yaml` |
| `logs <svc> <env>` | Same as `info` |
| `shell <svc> <env>` | Same as `info` |
| `deploy <svc> <env>` | `ERROR: There were no build definitions matching name "<repo>-<svc>-CD" in project "<project-id>".` |

Failures are **fast and explicit** — no hangs, no cryptic errors. v1.5.x against the new layout is safe to attempt; the user just gets a clear "doesn't apply here" signal.

---

## Per-command impact

| Command | v2 change |
|---|---|
| **`noclickops`** (lister) | None — layout-agnostic. |
| **`update`** | None. |
| **`status`** | None. `az pipelines runs list` is layout-agnostic. |
| **`create-pr`** | None. |
| **`merge-pr`** | None. |
| **`info`** | Reads `services/<svc>/config.<env>.yaml` (not `.pipelines/variables/<env>.yaml`). Renders the new field set. Live container-app section requires `--subscription` / `--resource-group` / `--app-name` overrides OR best-effort discovery via `az containerapp list` (which needs the user's own Reader access on the deployed subscription — the SP creds in the service connection are the pipeline's, not the human's). Degrades gracefully when access / overrides are missing. |
| **`deploy`** | Orchestrates 4 pipelines across 2 projects (FrontendPlatform + IaC) for first-time deploys; 2 pipelines + auto-trigger for subsequent. Detection: query IaC for the existence + last-run-status of `<repo>-<svc>-deploy-test`. If never run successfully → first-time path (trigger build → deploy → infra-build → deploy-test, sequentially with watch). If recently run successfully → trust resource trigger (just trigger `<repo>-<svc>-deploy` and watch both pipelines). `--watch-live` (PLAN-watch-live-deploy) then polls Front Door + DNS + cert + HTTPS for the additional 30-90 min on first-time public-endpoint services. |
| **`logs`** | Same RG/app-name gap as `info` live state. Gating (no degrade) — requires `--subscription` + `--resource-group` + `--app-name` overrides if discovery fails. |
| **`shell`** | Same as `logs`. |
| **`add-service`** | Triggers `<repo>-add-service` (unchanged). **BUT this opens TWO PRs** — PR-A in the source repo (service code) AND PR-B in `IaC/_git/platform-infrastructure` (deploy YAML). v2 polls for PR-A by source branch (`add-service-<svc>`) AND for PR-B by title (`Add service <svc>`), then self-approves + merges both. Without PR-B merged, no subsequent deploy can succeed. v1.5.x didn't know PR-B exists; that's why the test repos accumulated unmerged PR-Bs going back months. |
| **`clean-sample`** | New sample shape (Express + minimal `app/`, no Next.js). Rewrite to detect+strip the new sample. |
| **`sync-lovable`** | Probably doesn't apply — the new layout's services have an `app/` folder with Express, not a Vite/React PWA root. Defer until there's a concrete Lovable-into-new-layout use case. |

---

## PLAN sequence

### PLAN-A — `lib/service.sh` rewrite for the new layout

Centralises discovery for the new layout. Single source of truth used by every downstream command.

- `read_service_config <svc> <env>` → reads `services/<svc>/config.<env>.yaml` into `parsed_*` globals.
- `discover_subscription <env>` → lists ARM service connections in FrontendPlatform, filters by `<prefix>-<env>-sp` pattern, parses scope.
- `discover_iac_project` → typically `IaC` — first checks if a project name matching `IaC` / `Infrastructure` / `Platform` exists; accepts `NOCLICKOPS_IAC_PROJECT` env override.
- `discover_pipelines <svc>` → returns a struct with: `frontend_build`, `frontend_deploy`, `iac_infra_build`, `iac_deploy_test`, `iac_deploy_prod` pipeline ids. Empty fields when not found.
- `discover_containerapp <svc>` → best-effort `az containerapp list -n <svc>`; accepts `--app-name` override.
- `discover_rg <env> <repo>` → returns `rg-<env>-nrx-<repo-prefix-lc>` (no Azure call needed; pure derivation).
- `public_url_for <svc> <env>` → reads `ENABLE_PUBLIC_ENDPOINT` from `config.<env>.yaml`; returns `<svc>.example.cloud` or empty.

### PLAN-B — `info` rewrite

Static section from `read_service_config`. Live container-app state via `discover_containerapp` + `discover_rg`; degrades with a clear "pass `--app-name <name>` to specify backend" message if best-effort discovery comes up empty.

### PLAN-C — `deploy` rewrite (multi-pipeline orchestration)

The big one. Two paths:

- **Subsequent deploys** (IaC's `deploy-test` has succeeded before for this svc/env): just trigger FrontendPlatform's `<repo>-<svc>-deploy`. The resource trigger fires IaC's `deploy-test` automatically. With `--watch`, watches both pipelines.
- **First-time deploys** (no successful `deploy-test` run yet): explicitly run in sequence — `<repo>-<svc>-build` → `<repo>-<svc>-deploy` → `<repo>-<svc>-infra-build` → `<repo>-<svc>-deploy-test`. With `--watch-live`, additionally polls Front Door / DNS / cert / HTTPS for the additional 30-90 min on first-time public-endpoint services (per [PLAN-watch-live-deploy.md](PLAN-watch-live-deploy.md)).

Detection: query IaC for `<repo>-<svc>-deploy-test` runs; if none succeeded → first-time.

### PLAN-D — `logs` / `shell` rewrite

Same `discover_containerapp` + `discover_rg` as info's live section. Gating: fail with `--app-name` / `--resource-group` override message if discovery comes up empty.

### PLAN-E — `clean-sample` for the new sample shape

Detect Express + `app/` shape and strip it. v1's Next.js-sample logic is dropped along with FRT support.

### PLAN-F — `add-service` two-PR flow

v1.5.x merges only PR-A (source repo). v2 waits for **both** PRs:

- Poll `az repos pr list --source-branch add-service-<svc>` in the source repo until PR-A appears (~1-2 min); self-approve + squash-merge.
- Poll `az repos pr list --project IaC --repository platform-infrastructure --status active` for a PR titled `Add service <svc>`; self-approve + squash-merge.
- Print a summary: "Source PR #X merged; infrastructure PR #Y merged. Run `noclickops deploy <svc> test` to ship the first deploy."

`--no-merge` stays as the escape hatch (skips both PR merges; user is responsible).

### Version bump

v1.5.x → **v2.0.0** when PLAN-A through PLAN-F land. Semver major (target-repo contract change). v1 stays available via the `v1.5.x` tag for anyone still on FRT.

The `--watch-live` flag for first-time public-endpoint deploys is filed separately as [PLAN-watch-live-deploy.md](PLAN-watch-live-deploy.md) — ships as part of v2's PLAN-C `--watch-live` flag.

---

## Risks

1. **Container-app naming convention unconfirmed.** `discover_containerapp` will pattern-match by `<svc>`, but the downstream may use `<svc>-<env>` or `<repo>-<svc>`. Always offer `--app-name` override; document it loudly. (Pending confirmation when the frontend test deploy reaches HTTPS 200 and we can `az containerapp list`.)

2. **Subscription access mismatch.** The pipeline's identity (the service connection SP, e.g. `myteam-frontend-test-sp`) has Contributor on the deployed sub; the human developer may have nothing. `info` live section, `logs`, `shell` need the human's own access — failing closed with a clear message is the right behaviour. Don't try to use SP credentials from the service connection — that's a layer violation.

3. **Cross-project orchestration auth surface.** v2 commands need read access on FrontendPlatform AND read/write on IaC (specifically platform-infrastructure for PR-B merging). Some developers may have one but not the other. Each `az pipelines run` and `az repos pr update` in IaC could fail with 403. v2 must produce clear error messages naming the missing project + permission.

4. **Branch policies on `platform-infrastructure` could harden later.** Today policies are empty — self-approval works. If the Azure engineer adds a required-reviewer policy, v2's auto-merge of PR-B breaks. Mitigation: try auto-merge; on policy-block, fall back to printing the PR URL and instructions ("PR-B needs review at <url>; merge it, then re-run `noclickops deploy <svc> test`").

5. **First-deploy resource-trigger quirk.** A freshly-registered IaC `deploy-test` pipeline doesn't auto-fire from FrontendPlatform's `-deploy` until it has run once manually. v2's first-time path triggers it explicitly; subsequent deploys rely on the trigger. If the trigger ever breaks (e.g. Azure engineer changes the YAML), `deploy` should detect "FrontendPlatform deploy succeeded but no IaC deploy fired within 60s" and fall back to manual triggering.

6. **Unmerged PR-B accumulation across the org.** We observed PR-Bs in `platform-infrastructure` going back to April with no merges. Today developers don't even know PR-B exists. Once v2 auto-merges them, expect cleanup pressure on those old PRs (manual decision per PR). Not noclickops's job to clean those up.

7. **`copier-add-service` will evolve.** Each evolution may add / rename variables, change pipeline naming, restructure either repo's folder layout. Build noclickops around discovery + overrides + graceful degrade — not hardcoded names. The Bicep templates inside `platform-infrastructure` aren't noclickops's concern; only the pipeline names and the PR titles are.

---

## Out of scope

- **FRT layout support.** Dropped in v2. v1 users pin to `v1.5.x`.
- **GitHub-target support.** Future extension; not v2.
- **`sync-lovable` for the new layout.** Defer until a real use case exists.
- **Discovering the downstream deploy system.** Not noclickops's concern — overrides handle the gap.

---

## Next steps

- [ ] Draft PLAN-A (`lib/service.sh` for the new layout).
- [ ] Draft PLAN-B (info), PLAN-C (deploy), PLAN-D (logs/shell), PLAN-E (clean-sample).
- [ ] Each PLAN ships as its own PR; v2.0.0 cut after PLAN-E merges.
- [ ] Move this INVESTIGATE to `completed/` when PLAN-E merges.
- [ ] Pin the current FRT-supporting state as `v1.5.x` tag for users who haven't migrated.
