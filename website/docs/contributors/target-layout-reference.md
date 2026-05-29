---
title: Target layout reference
sidebar_position: 1
---

# Target layout reference

This document describes the **observed** Red Cross Norway Azure DevOps + Azure layout that noclickops targets. It is what noclickops's commands assume when they read files, query pipelines, and call `az`. **The Azure engineer owns this layout**, not noclickops — when they change it, the description here goes stale and noclickops's commands start failing in new ways.

**As observed**: 2026-05-29. Re-verify before believing.

## Spotting drift

If a `noclickops` command starts failing in a way that doesn't match documented behaviour:

1. **Suspect the layout changed** before suspecting noclickops is broken.
2. Pick the relevant section below and run the discovery commands listed at its bottom.
3. Diff the output against what this doc says.
4. If they differ, update this doc first, then decide whether noclickops's behaviour needs to follow.

Every section here ends with the commands used to discover or verify it. Running them again is the 5-minute spot-check.

---

## Project + repo layout

The new layout spans **two Azure DevOps projects** and **two git repos per service**:

### Project 1 — `FrontendPlatform` (developer source)

```text
ExampleOrg/FrontendPlatform/_git/<repo>/   # e.g. ABC100001-myservice
  .pipelines/
    add-service.yaml                            # request creator (publishes deployment-request artifact)
  services/
    <svc>/                                      # e.g. frontend
      Dockerfile
      app/                                      # service source code (Express + minimal scaffold)
      config.test.yaml                          # per-env service config
      config.prod.yaml
      README.md
      .pipelines/
        service.yaml                            # BUILD pipeline (docker build, trivy scan)
        deploy_service.yaml                     # DEPLOY pipeline (publishes deployment-package-{env})
```

### Project 2 — `IaC` (engineer-owned; the actual deployer)

```text
ExampleOrg/IaC/_git/platform-infrastructure/
  environments/
    <TEAM>/                                     # ABC | DEF | GHI | JKL | MNO — first dash-segment of <repo>
      <repo>/
        infrastructure/
          .pipelines/
            add-service.yaml
            cd.yaml
            templates/stages/deploy_infrastructure.yaml
            variables/
              common.yaml                       # repo-level platform vars (FRT-style)
              test.yaml
              prod.yaml
          main.bicep
          params/main.{test,prod}.bicepparam
        services/
          <svc>/
            .pipelines/
              build_service.yaml                # ACR push for this svc
              test_deploy_service.yaml          # ARM deploy → test sub
              prod_deploy_service.yaml          # ARM deploy → prod sub
              templates/deploy_infrastructure.yaml
            main.bicep                          # wraps shared aca-service Bicep module
            params/main.{test,prod}.bicepparam
```

**Discovery commands**:

```bash
# Confirm both projects exist + you have read access
az devops project list --query "[?name=='FrontendPlatform' || name=='IaC'].name" -o tsv

# Confirm the IaC repo + folder shape for a given target repo
TOKEN=$(az account get-access-token --resource <ado-app-id> --query accessToken -o tsv)
REPO_ID=$(az repos show --organization https://dev.azure.com/ExampleOrg --project IaC --repository platform-infrastructure --query id -o tsv)
curl -s -u ":$TOKEN" \
  "https://dev.azure.com/ExampleOrg/IaC/_apis/git/repositories/$REPO_ID/items?scopePath=/environments/<TEAM>/<repo>&recursionLevel=full&api-version=7.0" \
  | python3 -c "import sys,json; [print(i['path']) for i in json.load(sys.stdin).get('value',[])]"
```

---

## Variable files

The FRT-style `common.yaml` + `<env>.yaml` files **exist** for new-layout repos — at a different path than v1.5.x looks. noclickops v2 reads them from `IaC/platform-infrastructure` via `lib/service-v2.sh`'s `read_iac_variables`, called by `bin/info.sh` (and later `logs`, `shell`, `deploy` as those rewrite). Reads via ADO REST — no IaC repo clone needed.

**Location**:

```text
IaC/platform-infrastructure/environments/<TEAM>/<repo>/infrastructure/.pipelines/variables/
  common.yaml
  test.yaml
  prod.yaml
```

**Schema** (observed on `ABC100001-myservice`):

```yaml
# common.yaml
APP_NAME: "abc100001"                          # lowercased repo prefix
APPLICATION_NAME: "myservice"                  # rest of repo name
CONTAINER_REGISTRY_NAME: "acrshareduw"
REPO_NAME: "ABC100001-myservice"
TEAM_NAME: "TCH"
IAC_PROJECT: "IaC"
IAC_REPO: "platform-infrastructure"
PUBLIC_DNS_SUBSCRIPTION_ID: "<id>"
PUBLIC_DNS_RESOURCE_GROUP_NAME: "rg-prod-shared-dns-euw"

# test.yaml
ENVIRONMENT: "test"
SUBSCRIPTION_ID: "<test-sub-id>"
COMMON_RESOURCE_GROUP_NAME: "rg-test-myteam-frontend-common"
CONTAINER_APPS_MANAGED_IDENTITY_NAME: "ui-test-cr-frontend"
VNET_RESOURCE_GROUP_NAME: "rg-test-network-euw"
VNET_NAME: "vnet-test-frontend-euw"
DNS_ZONE_NAME: "example.cloud"
FRONTDOOR_SUBSCRIPTION_ID: "<id>"
FRONTDOOR_RESOURCE_GROUP: "rg-dev-sharedservices-euw"
FRONTDOOR_PROFILE_NAME: "fd-dev-shared-euw"
FRONTDOOR_ENDPOINT_NAME: "test-endpoint-frontend"
KEY_VAULT_NAME: "kv-test-myteam-shared"
```

Service-level config lives in the source repo at `services/<svc>/config.<env>.yaml` with the SERVICE_* keys (`SERVICE_PORT`, `SERVICE_CPU`, `SERVICE_MEMORY`, `SERVICE_MIN_REPLICAS`, `SERVICE_MAX_REPLICAS`, `SERVICE_HEALTH_CHECK_PATH`, `SERVICE_HEALTH_PROBE_PORT`, plus `ENABLE_PUBLIC_ENDPOINT`, `PERSISTENT_STORAGE`, and app-specific values like `OKTA_ISSUER`, `APP_BASE_URL`).

**Discovery command**:

```bash
TOKEN=$(az account get-access-token --resource <ado-app-id> --query accessToken -o tsv)
REPO_ID=$(az repos show --organization https://dev.azure.com/ExampleOrg --project IaC --repository platform-infrastructure --query id -o tsv)
curl -s -u ":$TOKEN" \
  "https://dev.azure.com/ExampleOrg/IaC/_apis/git/repositories/$REPO_ID/items?path=/environments/<TEAM>/<repo>/infrastructure/.pipelines/variables/common.yaml&api-version=7.0"
```

---

## Pipeline naming conventions

Five distinct patterns per service-creation + service-deploy lifecycle, split across the two projects.

**In `FrontendPlatform`** (per repo, one set per service):

| Pattern | Purpose |
|---|---|
| `<repo>-add-service` | Request-creator pipeline. Publishes a `deployment-request` artifact; downstream IaC handles scaffolding. |
| `<repo>-<svc>-build` | Docker build + trivy scan. Publishes `deploy-package` artifact. |
| `<repo>-<svc>-deploy` | Packages config + image → publishes `deployment-package-{env}` artifact. **Does not deploy to Azure.** |

**In `IaC`** (per repo, one set per service):

| Pattern | Purpose |
|---|---|
| `<repo>-CD` | Repo-level CD orchestration |
| `<repo>-infra-add-service` | Auto-fires from FrontendPlatform's add-service. Opens PR-B in platform-infrastructure with the deploy YAML for the new service. |
| `<repo>-<svc>-infra-build` | Pushes the docker image to ACR. **Required for first-time deploys.** |
| `<repo>-<svc>-deploy-test` | ARM template deploy to the test subscription. **This is the actual Azure deploy.** |
| `<repo>-<svc>-deploy-prod` | Same for prod. |

**Discovery commands**:

```bash
# FrontendPlatform pipelines for a given source repo
az pipelines list \
  --repository <repo> --repository-type tfsgit \
  --query "[].name" -o tsv

# IaC pipelines for the same repo
az pipelines list \
  --organization https://dev.azure.com/ExampleOrg --project IaC \
  --query "[?contains(name, '<repo>')].name" -o tsv
```

---

## Resource naming conventions

Confirmed empirically by `az containerapp list` against peer NRX subscriptions (the user's account has Reader on `DEV / TEST / PROD - AZURE INTEGRATIONS`).

| Resource | Pattern | Example |
|---|---|---|
| Container app | `ca-<repo-prefix>-<svc>` | `ca-abc100001-frontend`, `ca-xyz900005-backend` |
| Resource group | `rg-<env>-nrx-<repo-prefix>` | `rg-test-myteam-abc100001` |
| Container FQDN (internal) | `<containerapp>.<env-hash>.<region>.azurecontainerapps.io` | `ca-xyz900005-frontend.examplehill-deadbeef12.westeurope.azurecontainerapps.io` |
| Public FQDN (Front Door) | `<svc>.<DNS_ZONE_NAME>` | `frontend.example.cloud` |
| Image (in ACR) | `<CONTAINER_REGISTRY_NAME>.azurecr.io/<image-name>:<tag>` | `acrshareduw.azurecr.io/test-frontend-repo:latest` |
| Common shared RG | `COMMON_RESOURCE_GROUP_NAME` from `<env>.yaml` | `rg-test-myteam-frontend-common` |

The `<repo-prefix>` is the lowercased part of the repo name before the first `-` (e.g. `ABC100001-myservice` → `abc100001`).

**Discovery command**:

```bash
# Inspect container apps in any subscription you have Reader on
az containerapp list --subscription <sub-id> \
  --query "[].{name:name, rg:resourceGroup, fqdn:properties.configuration.ingress.fqdn}" -o table
```

---

## Public-endpoint architecture

For services with `ENABLE_PUBLIC_ENDPOINT: "true"` in their `config.<env>.yaml`, traffic flows through a single Azure Front Door per environment:

```text
<svc>.<DNS_ZONE_NAME>
  → CNAME <FRONTDOOR_ENDPOINT_NAME>-<hash>.z02.azurefd.net   (Azure Front Door, one endpoint per env)
  → CNAME mr-z02.tm-azurefd.net
  → <Front Door anycast IP>
```

Front Door routes by hostname to the backend container app `ca-<repo-prefix>-<svc>`. The container app's internal `*.azurecontainerapps.io` FQDN is NOT directly reachable in most cases — Front Door fronts it for the public domain + cert.

Cert is a managed DigiCert / GeoTrust SAN cert with `CN=<svc>.<DNS_ZONE_NAME>`.

**First-time deploy timing** for a public-endpoint service:

| Phase | Time |
|---|---|
| Pipeline chain (build → deploy → infra-build → deploy-test) | ~10 min |
| ARM deploy completes | included above |
| Front Door custom-domain validation + DNS propagation | ~30–60 min |
| Managed cert issuance | ~10–30 min after DNS |
| HTTPS endpoint serves 200 | total ~60–90 min from `noclickops deploy` |

Subsequent deploys (same hostname, new image) skip the Front Door + cert steps and complete in ~3–10 min.

**Discovery commands**:

```bash
# DNS chain
dig +short <svc>.<DNS_ZONE_NAME>

# Cert details
echo | openssl s_client -connect <svc>.<DNS_ZONE_NAME>:443 -servername <svc>.<DNS_ZONE_NAME> 2>/dev/null \
  | openssl x509 -noout -subject -issuer

# Response headers (look for x-azure-ref → Front Door tracing)
curl -sI https://<svc>.<DNS_ZONE_NAME>/health
```

---

## Two-PR `add-service` flow

`noclickops add-service <svc>` (or its v1.5.x equivalent) triggers a flow that opens **two PRs**, in different repos:

| PR | Repo | Title | Source branch | Contains |
|---|---|---|---|---|
| **PR-A** | source repo (e.g. `ABC100001-myservice`) | `Add service <svc>` | `add-service-<svc>` | The new `services/<svc>/` folder with code + Dockerfile + config |
| **PR-B** | `IaC/platform-infrastructure` | `Add service <svc>` | `add-service-<svc>` | The new `environments/<TEAM>/<repo>/services/<svc>/` folder with Bicep + pipeline YAML |

**Both PRs must be merged** for subsequent `deploy` commands to succeed. v1.5.x merges only PR-A; PR-Bs accumulate unmerged (real backlog observed: PRs going back to April 2026 in `platform-infrastructure`).

Branch policies on `platform-infrastructure/main`: **empty**. Self-approval via `az repos pr set-vote --vote approve` is sufficient; squash-merge via `az repos pr update --status completed --squash` works.

Timing: PR-A appears ~1–2 min after the `add-service` pipeline succeeds. PR-B appears in the same window.

**Discovery commands**:

```bash
# List unmerged PR-Bs (the backlog)
az repos pr list \
  --organization https://dev.azure.com/ExampleOrg --project IaC \
  --repository platform-infrastructure --status active \
  --query "[].{id:pullRequestId, title:title, created:creationDate}" -o table

# Branch policies on platform-infrastructure/main (should be empty)
REPO_ID=$(az repos show --organization https://dev.azure.com/ExampleOrg --project IaC --repository platform-infrastructure --query id -o tsv)
az repos policy list \
  --organization https://dev.azure.com/ExampleOrg --project IaC \
  --repository-id $REPO_ID --branch refs/heads/main \
  --query "[].{type:type.displayName, isBlocking:isBlocking}" -o table
```

---

## Deploy: first-time vs subsequent

**First-time** for a service (no successful `<repo>-<svc>-deploy-test` runs in IaC ever):

```text
FrontendPlatform/<repo>-<svc>-build         (~1-2 min)
FrontendPlatform/<repo>-<svc>-deploy        (~30s)
IaC/<repo>-<svc>-infra-build                (~3 min)   ← required for first time only
IaC/<repo>-<svc>-deploy-test                (~6 min, ARM deploy)
```

All four must be triggered explicitly. Why: the resource trigger on a freshly-registered IaC `deploy-test` pipeline doesn't auto-wire until that pipeline has run at least once manually — a known ADO quirk.

**Subsequent deploys**:

```text
FrontendPlatform/<repo>-<svc>-deploy        (~30s)
  ↓ resource trigger fires automatically
IaC/<repo>-<svc>-deploy-test                (~3-6 min)
```

`infra-build` typically isn't re-run unless the image needs to push to ACR (image-tag change).

**Deploy mechanism**: `AzureResourceManagerTemplateDeployment@3` Azure DevOps task, with inputs from a `<svc>-infra` artifact containing `template.json` + `template.params.json` (compiled from Bicep). The Bicep wraps a shared module from an OCI registry: `acrshareduw.azurecr.io/bicep/ptn/aca/aca-service:<version>` — engineer-owned, not noclickops's concern.

**Discovery commands**:

```bash
# Check if a deploy-test has ever succeeded for this svc
az pipelines runs list \
  --organization https://dev.azure.com/ExampleOrg --project IaC \
  --pipeline-name "<repo>-<svc>-deploy-test" --top 5 \
  --query "[?result=='succeeded'].{id:id, finished:finishTime}" -o table
```

---

## Permission boundaries

Tested empirically against a peer NRX service (`ca-xyz900005-frontend` in `DEV - AZURE INTEGRATIONS`):

| Call | Permission needed | With Reader on sub | Notes |
|---|---|---|---|
| `az containerapp show` | Reader | ✓ works | Returns name, image, revision, fqdn, replicas, ingress — everything `info` needs |
| `az containerapp list` | Reader | ✓ works | |
| `az containerapp logs show` | `Microsoft.App/containerApps/getAuthToken/action` (Container Apps Logs Reader role or higher) | ✗ `AuthorizationFailed` | `logs` fails closed with clear message |
| `az containerapp exec` (shell) | Same as logs | ✗ same | `shell` fails closed |

For the service connections in `FrontendPlatform`:

| Connection | Purpose | Scope |
|---|---|---|
| `myteam-frontend-test-sp` | Test container apps | `/subscriptions/<test-sub-id>` |
| `myteam-frontend-prod-sp` | Prod container apps | `/subscriptions/<prod-sub-id>` |
| `myteam-frontend-acr-sp` | ACR access | `/subscriptions/<shared-sub-id>/.../acrshareduw` |

Pattern: `<org-prefix>-<env>-sp` for ARM service connections.

**Discovery commands**:

```bash
# Service connections in FrontendPlatform
az devops service-endpoint list \
  --query "[?type=='azurerm'].{name:name, scope:authorization.parameters.scope}" -o table

# Quick permission test on logs (against any container app you can see)
az containerapp logs show --subscription <sub> -g <rg> -n <app> --tail 1
```

---

## Known anomalies

Things that aren't bugs but trip people up:

- **PR-B backlog in `platform-infrastructure`**: PRs titled `Add service <name>` going back months are unmerged because developers historically didn't know they existed. Don't auto-clean — each represents a service someone intended to create. v2 noclickops merges new PR-Bs automatically when `add-service` is the trigger.
- **First-time `deploy-test` doesn't auto-fire**: ADO quirk — resource triggers on freshly-registered pipelines need one manual run before they activate. v2's first-time deploy path triggers the chain explicitly.
- **Deploy artifact handoff is async + invisible**: `FrontendPlatform/<repo>-<svc>-deploy` succeeds in 30s but only publishes an artifact. Nothing visible happens until the IaC pipelines fire (manually first-time, auto-triggered subsequently). A successful FrontendPlatform deploy is NOT the same as "deployed to Azure".
- **First-time public-endpoint deploys take ~60 min** even though pipelines complete in ~10 min. Front Door custom-domain validation + DNS propagation + managed cert issuance accounts for the rest. Don't assume failure if HTTPS isn't responding within the first hour.
- **Test sub Reader is rare for developers**. Most live-state queries (`az containerapp show`, etc.) work against peer NRX subs the developer might have access to, but not against the test sub specifically without a separate access grant.

---

## When this doc goes stale

The Azure engineer changes things. Here are the most likely change vectors and how to spot them:

| Likely change | Symptom in noclickops | First place to look |
|---|---|---|
| Variable file moved or renamed | `info` / `logs` / `shell` start saying "Repo-level variables missing" again | Re-run the variable-files discovery command for a specific repo |
| Pipeline naming changed | `deploy` / `add-service` say "no build definitions matching name X" | `az pipelines list` in both projects; update the naming-convention table |
| New variable added to `common.yaml` / `<env>.yaml` | noclickops silently ignores it | Read the file; decide if noclickops should surface it |
| Bicep module bumped (`aca-service:<new-version>`) | Container app naming or RG pattern might shift | Run the resource-naming discovery against a freshly-deployed service |
| New required reviewer added to `platform-infrastructure/main` | v2's `add-service` PR-B auto-merge starts failing | Run the branch-policies discovery command |
| Container Apps env hash changes | Internal FQDNs change | Already encoded in `az containerapp show` output |
| ACR moved | Image pulls fail in the build pipeline | `CONTAINER_REGISTRY_NAME` in `common.yaml` |

If you find drift, update **this doc** first (so the next person doesn't repeat the discovery), then decide what noclickops changes need to follow.
