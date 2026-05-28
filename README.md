# noclickops

A portable script suite for **"no clickops"** operations on developer projects. Wraps the common stuff a developer does every day — open PRs, merge PRs, deploy a service, scaffold a new service, tail logs, see what's deployed, open a shell in a running container — without re-implementing the underlying systems (pipelines, git providers, cloud APIs).

**Installed once per developer machine**; operates on whichever git repo the developer is currently in.

## What `noclickops` operates against

- **Target repos**: Azure DevOps (v1). GitHub-target support is a future extension.
- **Pipelines**: Azure DevOps pipelines (`az pipelines`).
- **Cloud**: Azure Container Apps (`az containerapp`), Azure Key Vault.

## Install

> Full installer ships in **PLAN-002** (one-line `curl | bash`). Until then, clone manually and run by full path:
>
> ```bash
> git clone https://github.com/terchris/noclickops.git ~/.noclickops
> ~/.noclickops/bin/noclickops.sh         # list available commands
> ~/.noclickops/bin/update.sh             # pull the latest noclickops
> ~/.noclickops/bin/update.sh --help      # see the metadata-driven help block
> ```
>
> PLAN-002 will add a shell-function snippet so `noclickops` and `noclickops <subcommand> …` are typeable from anywhere. See `website/docs/ai-developer/plans/backlog/INVESTIGATE-noclickops.md` → "How `noclickops` becomes typeable" for the snippet.

## Status

In active development. v1 design is in [`website/docs/ai-developer/plans/backlog/INVESTIGATE-noclickops.md`](website/docs/ai-developer/plans/backlog/INVESTIGATE-noclickops.md). v1 ships through PLAN-001 (foundation) through PLAN-010 (`shell`).

## Development

This repo uses an AI-developer workflow — see [`CLAUDE.md`](CLAUDE.md) (or [`AGENTS.md`](AGENTS.md) for Codex) for the entry point.
