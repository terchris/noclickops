---
title: Getting started
sidebar_position: 1
---

# Getting started

This page walks you through installing noclickops and exercising every command against a real Azure DevOps repo. It doubles as a **regression checklist** — when a new version ships, run through these steps to confirm nothing broke.

The walkthrough assumes you have:

- A Mac, Linux, or Windows (Git Bash / WSL) machine.
- Git 2.25+ and Bash 3.2+ (every macOS / Linux already has both).
- A clone of an Azure DevOps repo. Repo layout matters for some commands — see below.
- An Azure account with at least Reader access on the subscription the repo deploys to.

If you only want to install and see the surface, stop at step 3. To go further, you'll need `az login`.

### Repo layouts: which commands work where

noclickops currently targets the **FRT-shaped** layout (`.pipelines/variables/{common,test,prod}.yaml` at repo root, single `<repo>-<svc>-CD` pipeline per service). A newer layout (per-service `services/<svc>/config.<env>.yaml`, split `<repo>-<svc>-build` + `<repo>-<svc>-deploy` pipelines, Azure Front Door fronting `<svc>.example.cloud`) is the direction for newly-scaffolded repos. Full v2 support for the new layout is in progress — see [INVESTIGATE-new-target-structure](/docs/ai-developer/plans/backlog/INVESTIGATE-new-target-structure).

What works on each, as of v1.5.x:

| Command | FRT layout | New layout |
|---|---|---|
| `noclickops`, `update`, `--help` | ✓ | ✓ |
| `status` | ✓ | ✓ |
| `create-pr`, `merge-pr` | ✓ | ✓ |
| `add-service` | ✓ | Trigger works; auto-merge misses the PR (downstream is async). Use `--no-merge`, then `merge-pr` when the PR appears (~1–2 min). |
| `info` | ✓ | **v2** — reads `services/<svc>/config.<env>.yaml` + IaC variables via ADO REST, discovers container app via `az containerapp list`. Public services show a `Public URL` line. |
| `logs`, `shell` | ✓ | **v2** — discovers container app via `az containerapp list` against the IaC-declared subscription/RG; gates on discovery failure (no degraded mode). Override with `SVC_APP_NAME_OVERRIDE` + `SVC_RG_OVERRIDE`. |
| `deploy` | ✓ | **v2** — multi-pipeline orchestration. Detects first-time vs subsequent automatically. First-time chains 4 pipelines (build → deploy → infra-build → deploy-test, ~10 min). Subsequent triggers `<repo>-<svc>-deploy` and exits; `--watch` follows the auto-triggered IaC deploy-test too. |
| `clean-sample` | ✓ (Next.js sample) | **v2** — replaces the Express+OIDC template with a minimal Express+`/health` stub for services that don't need OIDC. Refuses if `app/server.js` has been modified. |
| `sync-lovable` | ✓ (Lovable mirror) | Different sample shape; v2 deferred — no concrete use case yet. |

---

## 1. Install

```bash
curl -fsSL https://raw.githubusercontent.com/terchris/noclickops/main/install.sh | bash
```

**What you should see**

- A `==> Installing noclickops to ~/.noclickops` step.
- `Cloning into '/Users/.../.noclickops'...` with a small (~400 KB) receive.
- `✓ Slim layout applied (bin/ lib/ templates/ shell/ only).`
- The shell rc wiring (`Will append to ~/.zshrc` or `already wired`).
- A welcome banner.

Restart your shell, or:

```bash
source ~/.zshrc   # or ~/.bashrc
```

**Verify the slim install**

```bash
du -sh ~/.noclickops          # ~800 KB total
du -sh ~/.noclickops/.git     # ~540 KB
ls ~/.noclickops              # only bin/ lib/ templates/ shell/ + top-level files
cat ~/.noclickops/version.txt
git -C ~/.noclickops log --oneline | wc -l   # 1 (shallow clone)
```

Working tree is under 300 KB. `.git/` is shallow (a single commit). `git pull` (via `noclickops update`) maintains both the shallow boundary and the sparse set forever.

---

## 2. See the command surface

```bash
noclickops
```

**Expected**

- Header: `noclickops vX.Y.Z — portable script suite for developers`.
- Five grouped sections: **Meta**, **Git / pull requests**, **Deployment**, **Service lifecycle**, **Inspect / observe**.
- 12 commands total.
- A `Run 'noclickops <cmd> --help' for usage details` footer.

Drill into any command for full reference content (description, usage, flags, auth, depends-on, exit codes, see-also):

```bash
noclickops info --help
noclickops deploy --help
noclickops add-service --help
```

The same content lives on the website at https://noclickops.sovereignsky.no/docs/commands/.

---

## 3. cd into your repo

```bash
cd /path/to/your-ado-repo
```

Every noclickops command derives the target tenant / project / repo from `git remote get-url origin` at call time. No per-repo config needed; the same commands work in every supported repo on your machine.

---

## 4. Azure auth

```bash
az account show
```

If that errors with `Please run 'az login' to setup account`:

```bash
az login
```

A browser tab opens; pick your work account. After login, `az account show` returns a JSON blob with your subscription and tenant.

The `azure-devops` `az` extension is required for the Git / Deployment / Service-lifecycle commands. The first noclickops command that needs it offers to install it automatically. To do it ahead of time:

```bash
az extension add --name azure-devops
```

---

## 5. Read-only commands (lowest risk — start here)

Pick a service name from your repo's `services/` folder.

```bash
SERVICE=your-service-name   # e.g. postgrest, my-app, ...
```

**Static + live config for the service**

```bash
noclickops info $SERVICE test
```

**On the new layout (v2):** three static sections (IaC repo, Service config) followed by the live container-app block. Public services with `ENABLE_PUBLIC_ENDPOINT=true` get a `Public URL: https://<svc>.<dns-zone>` line.

```text
Service: frontend (test)
────────────────────────────────────────
  Folder:             /path/to/ABC100001-myservice/services/frontend

IaC repo (engineer-owned):
  App name (IaC):     abc100001
  Application name:   myservice
  Team:               ABC
  Subscription:       3aec5ff4-...
  Common RG:          rg-test-myteam-frontend-common
  Container registry: acrshareduw
  DNS zone:           example.cloud

Service config:
  Port:               3000
  Health check:       /health
  CPU:                0.5
  Memory:             1Gi
  ...
  Public endpoint:    true
  Public URL:         https://frontend.example.cloud

Live state (Azure):
  Container app:      ca-abc100001-frontend
  Resource group:     rg-test-myteam-frontend-common
  Internal FQDN:      ca-abc100001-frontend....westeurope.azurecontainerapps.io
  Status:             Running
  Latest revision:    ca-abc100001-frontend--rev42
  Image:              acrshareduw.azurecr.io/abc100001/frontend:latest
  Replicas (live):    min=1, max=3
```

If you don't have Reader on the deployed subscription (or the app isn't deployed yet), the live section degrades to `(live state unavailable — set SVC_APP_NAME_OVERRIDE and SVC_RG_OVERRIDE to override, or check 'az login' ...)`. Static sections always print first.

**Recent pipeline runs in this repo**

```bash
noclickops status
```

Lists the 20 most recent runs across all pipelines in the repo (id, name, status, result, time).

**Tail container logs**

```bash
noclickops logs $SERVICE test --tail 50
```

Streams or prints the last N log lines. With `--follow` it stays open. Gating — fails closed without Reader access on the subscription.

**Open a shell in the running container**

```bash
noclickops shell $SERVICE test
```

Drops you into `/bin/sh` inside the live container. Type `exit` when done. Use `--command CMD` for a single non-interactive command.

---

## 6. Mutating commands (do these only when you mean to)

These change state in your repo or Azure. Don't run for "testing" unless you actually want the outcome.

**Open a PR from your current branch**

You need a feature branch off main:

```bash
git checkout -b feat/my-change
# ... edit files, commit ...
noclickops create-pr "feat: short title for the change"
```

The command pushes the branch (sets upstream if needed) and opens an Azure DevOps PR. It prints the PR id and URL.

**Squash-merge a PR + sync local main**

```bash
noclickops merge-pr <pr-id>
```

Squash-completes the PR via `az`, polls until ADO confirms `completed`, then syncs local main and deletes the merged feature branch.

**Trigger a deploy (v2 multi-pipeline orchestration)**

```bash
noclickops deploy $SERVICE test
noclickops deploy $SERVICE test --watch
```

`deploy` detects whether this is a first-time or subsequent deploy for the service+env, then runs the appropriate chain:

- **Subsequent deploys** (any prior successful IaC `deploy-test`): triggers `<repo>-<svc>-deploy` in the source project and exits. The IaC `deploy-test` fires automatically via resource trigger (~3-6 min). With `--watch`, polls for that IaC run and watches it too.

- **First-time deploys** (no prior successful `deploy-test`): chains all four pipelines in sequence — build → deploy → infra-build → deploy-test (~10 min total). Always watches each step (chain requires it). Fail-fast: if step N fails, steps N+1 onwards don't trigger. On success, prints a summary with the derived container app name + Public URL (for services with `ENABLE_PUBLIC_ENDPOINT=true`).

For first-time **public** services, Front Door custom-domain validation + cert issuance takes an additional ~30-90 min after the pipelines finish. `--watch-live` (separate plan) will poll DNS / HTTPS / cert until HTTPS-200; not yet implemented.

---

## 7. Service lifecycle (creates new content — heaviest mutations)

**Scaffold a brand-new service**

```bash
noclickops add-service my-new-service
```

Triggers the Copier-based `<repo>-add-service` pipeline, watches it (~1 min), finds the scaffold PR by source branch, and squash-merges it. Use `--no-merge` for fire-and-forget if you want manual control of the PR.

Do not run this for testing — it actually creates a new service.

**Strip the Next.js sample from a fresh service**

```bash
noclickops clean-sample my-new-service
```

Removes the placeholder content keeping the platform scaffolding (Dockerfile, service.yaml, .pipelines/, bicep/). Stages the deletions in git.

**Mirror a Lovable.ai project into a service folder**

```bash
noclickops sync-lovable ~/path/to/lovable-repo my-new-service
```

rsyncs the frontend, re-renders Dockerfile + nginx.conf from templates, regenerates health.json with the source repo URL + commit SHA.

---

## 8. Keep noclickops up to date

```bash
noclickops update
```

Runs `git pull --ff-only` in `~/.noclickops`. Maintains the shallow + sparse layout. The lister also shows an `⬆ Update available` hint when you're behind upstream — the remote check is cached for 1 hour to keep the lister snappy.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `'az' not found` | Azure CLI not installed | `brew install azure-cli` (macOS) / [official install docs](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| `Please run 'az login'` | Not authenticated | `az login`, pick the right tenant |
| `azure-devops extension not installed` | Extension missing | `az extension add --name azure-devops`, or let noclickops auto-install on first use |
| `Reader access missing on subscription <id>` | No Reader role on the Azure subscription | Ask your team admin for Reader on the subscription id named in `.pipelines/variables/<env>.yaml` |
| `Service '<name>' not found at <path>/services/<name>` | Service folder doesn't exist | Check the spelling; list with `ls services/` |
| `git pull failed in ~/.noclickops` | Local changes blocking the pull | `git -C ~/.noclickops status` to inspect; reset or stash if needed |
| Help output looks stale (missing v1.5.2+ sections) | Old install | `noclickops update` or re-run the installer |

---

## Regression checklist

Use this as a quick sanity check when a new noclickops version ships.

- [ ] Fresh install via `install.sh` produces a working tree under 300 KB.
- [ ] `du -sh ~/.noclickops` total under 1 MB.
- [ ] `noclickops` shows the version header and 12 commands in 5 categories.
- [ ] `noclickops <cmd> --help` shows the rich metadata sections (Details, Auth, Depends on, Exit codes, See also).
- [ ] `noclickops info $SERVICE test` returns either full or partially-degraded output (never crashes).
- [ ] `noclickops status` lists recent pipeline runs.
- [ ] `noclickops logs $SERVICE test --tail 10` exits 0 (with Reader access).
- [ ] `noclickops update` works on the slim install without needing manual `git` ops.

If everything passes, the install is healthy.
