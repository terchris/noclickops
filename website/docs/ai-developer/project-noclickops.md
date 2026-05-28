# Project: noclickops

`noclickops` is a **portable script suite** for developers who'd rather type a command than click through a web UI. It wraps the operations a developer does every day on their projects — open a PR, merge a PR, deploy a service, scaffold a new service, tail logs, open a shell, see what's deployed — without re-implementing the underlying systems (the pipelines, the git providers, the cloud APIs).

**Installed once per developer machine**; operates on whichever git repo the developer is currently in (`pwd`). One installer; one update command; works across every project.

The brand says it plainly: **no clickops**.

For the user-facing description, install instructions, and quickstart, read the repo-root [`README.md`](https://github.com/terchris/noclickops/blob/main/README.md) first.

---

## What this repo contains

```text
noclickops/
├── README.md                — product overview (read this first)
├── LICENSE
├── install.sh               — one-time installer (Bash; mac/Linux/WSL/Git Bash)
├── install.ps1              — same for Windows PowerShell
│
├── bin/                     — the user-facing scripts (one per command)
│   ├── noclickops.sh        — the discovery / dispatcher target
│   ├── create-pr.sh
│   ├── merge-pr.sh
│   ├── deploy.sh
│   ├── add-service.sh
│   ├── clean-sample.sh
│   ├── sync-lovable.sh
│   ├── info.sh
│   ├── logs.sh
│   ├── shell.sh
│   └── *.ps1                — PowerShell sibling for each
│
├── lib/                     — shared helpers
│   ├── _common.sh
│   └── _common.ps1
│
├── templates/               — per-stack templates copied into target repos
│   └── lovable/             — Vite/React/PWA → nginx (Dockerfile + nginx.conf)
│
└── website/docs/ai-developer/  — this folder
    ├── README.md, WORKFLOW.md, PLANS.md, GIT.md,
    ├── AZURE-DEVOPS.md, TALK.md, WORKTREE.md, DEVCONTAINER.md
    ├── project-noclickops.md   — this file
    └── plans/                  — INVESTIGATE-*.md + PLAN-*.md
        ├── backlog/
        ├── active/
        └── completed/
```

*This layout is the proposed v1 design — see [`plans/backlog/INVESTIGATE-noclickops.md`](plans/backlog/INVESTIGATE-noclickops.md). The repo currently has only `LICENSE` + this AI-developer scaffold; everything under `bin/`, `lib/`, `templates/`, and the installers is what the investigation's child PLANs deliver.*

---

## How it's used

```bash
# One-time, per developer machine:
curl -fsSL https://raw.githubusercontent.com/terchris/noclickops/main/install.sh | bash

# After install, in any git repo on the machine:
noclickops                                    # show the inventory
noclickops deploy <service> test --watch      # run the service's CD pipeline
noclickops create-pr "feat: …"                # open a PR from the current branch
noclickops update                             # pull the latest noclickops
```

The shell function from [Q60] in the investigation routes by `pwd`'s git root — same command works in every No-ClickOps-enabled repo, no per-repo config required.

---

## Devcontainer

**No devcontainer.** Ignore [`DEVCONTAINER.md`](DEVCONTAINER.md). Developers (and contributors to this repo) work directly on the host shell — exactly the audience this tool serves.

---

## Platform: GitHub

This repo is on **GitHub** (`https://github.com/terchris/noclickops`), not Azure DevOps. Ignore the Azure DevOps half of [`AZURE-DEVOPS.md`](AZURE-DEVOPS.md); use the **GitHub Operations (`gh`) section of [`GIT.md`](GIT.md)** for PR mechanics here.

(Distinct from the target platform: in v1 the **scripts here target Azure DevOps repos only** — matching the Red Cross stack `noclickops` exists to serve. The fact that `noclickops`'s *own* repo lives on GitHub is just where the tool is hosted; its operational reach is the ADO `az repos` / `az pipelines` / `az containerapp` surface. GitHub-target support is a future extension.)

---

## Key rules and contracts

### Portability — non-negotiable

**No script in this repo may hard-code any target repo's identity.** Not org names, not repo names, not project names, not platform `APP_NAME` values. All such values come from the *target* repo's git remote, its variables files, or environment-variable overrides. This is what makes noclickops work against any project a dev cd's into.

### Wrap existing automation, never replicate it

`noclickops` triggers and observes existing pipelines and APIs — it never re-implements them locally. When a target repo's pipeline owner ships a new step (Copier upgrade, Bicep change, secrets handling), every noclickops user gets it for free because they're calling the same pipeline. This rule is why `add-service` is an `az pipelines run` wrapper rather than a local Copier invocation, and why `deploy` triggers a CD pipeline rather than `az containerapp update`-ing directly.

### Multi-repo, multi-OS

Designed-for by construction:

- **Many repos**: the shell-function dispatcher calls `git rev-parse --show-toplevel` at *call time*, so the same command resolves to the right repo's context based on `pwd`.
- **macOS / Linux / Windows**: Bash function covers macOS (zsh), Linux (bash), Windows via Git Bash and WSL. A PowerShell function in `$PROFILE` covers native Windows PowerShell. Every command ships `.sh` and `.ps1` siblings.

### Always work on a branch — never commit directly to `main`

Required flow for changes to noclickops itself: **branch → commit → push → PR → merge**. This repo lives on GitHub; the PR mechanics are `gh pr create` / `gh pr merge` (see [`GIT.md`](GIT.md)).

### Commit per plan; PR per investigation

For work that follows an `INVESTIGATE-*.md` → `PLAN-*.md` chain (see [`PLANS.md`](PLANS.md)):

- **Commit when each child PLAN is complete.**
- **Open the PR only when the parent investigation is finished** (all spawned PLANs shipped). The PR carries the full investigation's deliverables as one cohesive review unit.
- Standalone PLANs / fixes outside an investigation chain: simple commit + PR per plan.

### `noclickops` v1 is the work; the AI-developer framework is the scaffolding

Everything substantive about *what* `noclickops` does lives in `plans/backlog/INVESTIGATE-noclickops.md` and the PLANs it spawns. The `WORKFLOW.md` / `PLANS.md` framework rules apply unchanged. The `bin/`, `lib/`, `templates/`, and installer files are all produced by those PLANs.

---

## Always-loaded rules

The repo root contains a [`CLAUDE.md`](../../../CLAUDE.md) that Claude Code auto-loads at session start. It points here as the authoritative project doc and surfaces the most critical rules.
