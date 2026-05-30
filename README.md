# noclickops

[![tests](https://github.com/terchris/noclickops/actions/workflows/tests.yml/badge.svg)](https://github.com/terchris/noclickops/actions/workflows/tests.yml)

A portable Bash CLI that wraps the operations a developer does every day on Azure DevOps + Azure Container Apps — scaffold a new service, deploy it, tail its logs, open a shell in the running container, list recent pipeline runs — into one command per task. **No clickops** means no clicking around the ADO portal or Azure portal for routine work.

Installed once per developer machine; operates on whichever git repo your shell is currently in. Every command derives the target repo's identity from `git remote get-url origin` at call time, so the same commands work in every supported repo on your machine with no per-repo config.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/terchris/noclickops/main/install.sh | bash
```

The installer clones noclickops to `~/.noclickops`, adds `~/.noclickops/bin` to your `~/.zshrc` (or `~/.bashrc`) PATH, and prints a welcome message. Restart your shell — or `source ~/.zshrc` — and `noclickops` is on your PATH and resolves in any shell context: interactive, scripts, CI, anywhere.

Re-running the installer is idempotent: it pulls the latest if already installed and never duplicates the rc-file line.

## First commands

```bash
noclickops                  # list every available command, grouped
noclickops update           # pull the latest noclickops
noclickops <cmd> --help     # show usage, example, and example output
```

## Commands

| Category | Commands |
| --- | --- |
| **Meta** | `noclickops` (lister), `update`, `version` |
| **Git / pull requests** | `create-pr`, `merge-pr` |
| **Deployment** | `deploy` |
| **Service lifecycle** | `add-service`, `clean-sample` |
| **Inspect / observe** | `info`, `logs`, `shell`, `status` |

### A typical day

```bash
# Scaffold a new service. add-service triggers the ADO add-service pipeline,
# waits for the two PRs it produces (PR-A in the source repo, PR-B in the
# IaC/platform-infrastructure repo), auto-merges both, and syncs local main.
# Total: ~1-3 min, four observable steps.
noclickops add-service my-app --public-endpoint

# Optional: replace the OIDC starter the scaffold ships with your own code.
noclickops clean-sample my-app

# First-time deploy chains four pipelines (source build → source deploy →
# IaC build → IaC provision+deploy). ~6-10 min for internal services;
# add 30-90 min for first-time public endpoints (Front Door + cert).
noclickops deploy my-app test

# Observe.
noclickops status                              # recent runs in this repo
noclickops status my-app test                  # filter to this service
noclickops info my-app test                    # config + live container-app state
noclickops logs my-app test --tail 200         # recent container logs
noclickops shell my-app test                   # open /bin/sh in the running container
```

## What it operates against

- **Target repos**: Azure DevOps repos scaffolded via `copier-add-service` (`services/<svc>/` per service, with per-service `config.<env>.yaml` and a paired `platform-infrastructure` IaC repo).
- **Pipelines**: Azure DevOps. The `add-service` flow drives a single `<repo>-add-service` pipeline; `deploy` orchestrates four pipelines split across the source repo and the IaC repo.
- **Cloud**: Azure Container Apps — `noclickops info / logs / shell` query the live container app via `az containerapp show / logs show / exec`.

Identity is derived at call time:

- **Target tenant** (`AZDO_ORG` / `AZDO_PROJECT` / `AZDO_REPO`) is parsed from the target repo's `origin` URL — supports both `https://[user@]dev.azure.com/…` and `git@ssh.dev.azure.com:v3/…`.
- **Subscription, common RG, DNS zone** for `info` / `logs` / `shell` are read live from the engineer-owned IaC repo's `variables/<env>.yaml` — noclickops never invents or caches these.
- **noclickops's own upstream** (for the version check) is derived from `~/.noclickops`'s `origin`. A fork at `alice/noclickops` checks alice's `main`, not the original maintainer's.

No tenant / repo / project identity is hardcoded anywhere in `bin/`, `lib/`, `templates/`, or `shell/` — guarded by a portability grep in `tests/test-portability.sh`.

## Auth

| Commands | Required |
| --- | --- |
| `create-pr`, `merge-pr`, `deploy`, `add-service`, `status` | `az login` to the target's ADO tenant; first run also installs the `azure-devops` extension automatically |
| `info`, `logs`, `shell` | The above, plus **Reader** (or higher) on the Azure subscription named in the IaC repo's `variables/<env>.yaml` |

When subscription access is missing, the commands fail with a structured diagnostic that names the exact subscription, action (Reader / PIM activation), and which subscriptions you currently have access to. `info` degrades gracefully (still shows static config); `logs` and `shell` exit non-zero — the user wants live data, partial output is worse than a clear error.

## Keeping up to date

```bash
noclickops update           # git pull --ff-only in ~/.noclickops
```

The lister also shows a hint when your install is behind:

```text
noclickops v1.7.5 — portable script suite for developers
...
⬆ Update available: v1.7.6 — run 'noclickops update'
```

The remote check is cached for 1 hour to keep the lister snappy. Failures (network down, no GitHub access) are silent.

## Status

**v1.7.x** — stabilization toward v2.0.0. The current surface is twelve commands, all Bash-only, validated against a live Azure DevOps + Azure Container Apps target. v2.0.0 marks the cutover when the full add-service → deploy → observe loop has been smoke-validated end-to-end against a real customer-shaped repo; PowerShell siblings are no longer shipped (Bash is the supported surface), and a Bun-based rewrite is on the longer-term roadmap.

## Forks

`noclickops` is fork-friendly:

- The version-check looks at `~/.noclickops`'s `origin` remote — your fork checks itself.
- The target-tenant derivation looks at each target repo's `origin` remote — any ADO repo with a compatible layout works.
- The portability guard (`tests/test-portability.sh`) ensures nobody re-introduces hardcoded identity.

## Development

This repo uses a structured AI-developer workflow — see [`CLAUDE.md`](CLAUDE.md) (or [`AGENTS.md`](AGENTS.md) for Codex) for the entry point.

Design rationale, completion notes, and per-PLAN smoke-test results live in [`website/docs/ai-developer/plans/`](https://github.com/terchris/noclickops/tree/main/website/docs/ai-developer/plans/).

### Running the test suite

```bash
bash tests/run-all.sh
```

433 tests across the suite. No `az` / network / auth required — every fixture is built in `mktemp -d`.

### Working on the docs site

`website/` is a Docusaurus app — `cd website && npm install && npm start`. Full instructions in [`project-noclickops.md`](website/docs/ai-developer/project-noclickops.md#working-on-the-docs-site).

## License

[MIT](LICENSE).
