# noclickops

[![tests](https://github.com/terchris/noclickops/actions/workflows/tests.yml/badge.svg)](https://github.com/terchris/noclickops/actions/workflows/tests.yml)

A portable script suite that wraps the operations a developer does every day on Azure DevOps projects — open PRs, scaffold new services, deploy them, tail logs, open a shell in a running container — into one command per task. **No clickops** means no clicking around the ADO portal or Azure portal for routine work.

Installed once per developer machine; operates on whichever git repo your shell is currently in. Every command derives the target repo's identity from `git remote get-url origin` at call time, so the same commands work in every supported repo on your machine with no per-repo config.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/terchris/noclickops/main/install.sh | bash
```

The installer clones noclickops to `~/.noclickops`, adds `~/.noclickops/bin` to your `~/.zshrc` (or `~/.bashrc`) PATH, and prints a welcome message. Restart your shell — or `source ~/.zshrc` — and `noclickops` is on your PATH and resolves in any shell context: interactive, scripts, CI, anywhere.

Re-running the installer is idempotent: it pulls the latest if already installed and never duplicates the rc-file line.

> **Upgrading from v1.0.x**: existing installs use a shell-function-based dispatcher loaded from `shell/init.sh`. That still works after `noclickops update`. To switch to the v1.1.0 PATH-based mechanism (so `noclickops` resolves outside interactive shells too), re-run `install.sh` — it'll add the PATH line and tell you what to remove.

> **Windows / native PowerShell.** An `install.ps1` exists and mirrors the Bash flow, but the maintainer can't currently verify PowerShell scripts. For now we recommend running the Bash installer via **Git Bash** or **WSL**. If you want to try the native path, please file issues for anything that breaks.

## First commands

```bash
noclickops                  # list every available command, grouped
noclickops update           # pull the latest noclickops
noclickops <cmd> --help     # show usage + example for any command
```

## The v1.0.0 surface

Eleven commands, grouped:

| Category | Commands |
| --- | --- |
| **Meta** | `noclickops` (lister), `update` |
| **Git / pull requests** | `create-pr`, `merge-pr` |
| **Deployment** | `deploy` |
| **Service lifecycle** | `add-service`, `clean-sample`, `sync-lovable` |
| **Inspect / observe** | `info`, `logs`, `shell`, `status` |

### A typical day

```bash
# Scaffold a new service via the Copier pipeline (~1h):
noclickops add-service my-app
noclickops status <run-id>            # check progress; pipeline opens a PR when done
noclickops merge-pr <pr-id>

# Replace the placeholder sample with real content:
git checkout -b feature/my-app-content
noclickops clean-sample my-app                 # strips the Next.js sample (safety-guarded)
noclickops sync-lovable ~/work/my-app my-app   # mirror Lovable → service folder
                                                # renders Dockerfile + nginx + health.json
git add -A && git commit -m "feat: real content for my-app"
noclickops create-pr "feat: real content for my-app"
noclickops merge-pr <pr-id>

# Deploy + observe:
noclickops deploy my-app test --watch
noclickops info my-app test                    # config + live container-app state
noclickops logs my-app test --follow           # stream container logs
noclickops shell my-app test                   # open /bin/sh in the running container
```

## What it operates against

- **Target repos**: Azure DevOps repos in the **FRT-shaped** monorepo layout (`services/<svc>/` per service, with `.pipelines/variables/{common,test,prod}.yaml` for per-env config). GitHub-target support is a future extension.
- **Pipelines**: Azure DevOps (`az pipelines run` against the `<repo>-<svc>-CD` and `<repo>-add-service` pipelines).
- **Cloud**: Azure Container Apps (`az containerapp list / logs show / exec`).

Identity is derived at call time:

- The **target tenant** (`AZDO_ORG` / `AZDO_PROJECT` / `AZDO_REPO`) is parsed from the target repo's `origin` URL — supports both `https://[user@]dev.azure.com/…` and `git@ssh.dev.azure.com:v3/…`.
- The **subscription** for `info` / `logs` / `shell` is read from `.pipelines/variables/<env>.yaml` (`SUBSCRIPTION_ID`).
- **noclickops's own upstream** (for the version check) is derived from `~/.noclickops`'s `origin`. A fork at `alice/noclickops` checks alice's `main`, not the original maintainer's.

No tenant / repo / project identity is hardcoded anywhere in `bin/`, `lib/`, `templates/`, or `shell/` — guarded by a portability grep in `tests/test-portability.sh`.

## Auth

| Commands | Required |
| --- | --- |
| `create-pr`, `merge-pr`, `deploy`, `add-service`, `status` | `az login` to the target's ADO tenant; first run also installs the `azure-devops` extension automatically |
| `info`, `logs`, `shell` | The above, plus **Reader** (or higher) on the Azure subscription in the target's `.pipelines/variables/<env>.yaml` |

Commands that need subscription access fail closed with a clear "ask your team admin for Reader on subscription `<id>`" message when the access isn't there. `info` degrades gracefully (still shows static config from the YAML files); `logs` and `shell` exit non-zero — the user wants live data, partial output is worse than a clear error.

## Keeping up to date

```bash
noclickops update           # git pull --ff-only in ~/.noclickops
```

The lister also shows a friendly hint when your install is behind:

```text
noclickops v1.0.0 — portable script suite for developers
...
⬆ Update available: v1.0.1 — run 'noclickops update'
```

The remote check is cached for 1 hour to keep the lister snappy. Failures (network down, no GitHub access) are silent — no warning, no hint.

## Status

**v1.0.0** — full surface shipped. All 11 commands work; the 285-test suite passes locally.

### Known v1 limitations

- **PowerShell ports** ship for every script but are **unverified on macOS** (no `pwsh` on the maintainer's machine). The Bash side is the validated surface.
- **`sync-lovable` is bash-only.** The PowerShell port is a stub that errors with "use Git Bash or WSL" — `rsync`'s exclude+delete semantics don't safely map to `robocopy` / `Copy-Item` without thorough testing.
- **End-to-end integration tests** (real `az`, real PRs, real pipelines) are deferred. Manual gating remains — the next real `noclickops <cmd>` against a live target is the live validation.

## Forks

`noclickops` is fork-friendly:

- The version-check looks at `~/.noclickops`'s `origin` remote — your fork checks itself.
- The target-tenant derivation looks at each target repo's `origin` remote — any FRT-shaped ADO repo works.
- The portability guard (`tests/test-portability.sh`) ensures nobody re-introduces hardcoded identity.

## Development

This repo uses a structured AI-developer workflow — see [`CLAUDE.md`](CLAUDE.md) (or [`AGENTS.md`](AGENTS.md) for Codex) for the entry point.

The v1 surface was built across the PLANs documented in [`website/docs/ai-developer/plans/completed/`](website/docs/ai-developer/plans/completed/) — design rationale, completion notes, and per-PLAN smoke-test results are all there.

### Running the test suite

```bash
bash tests/run-all.sh
```

### Working on the docs site

`website/` is a Docusaurus app — `cd website && npm install && npm start`. Full instructions in [`project-noclickops.md`](website/docs/ai-developer/project-noclickops.md#working-on-the-docs-site).

285 tests across 11 files. No `az` / network / auth required — every fixture is built in `mktemp -d`.

## License

[MIT](LICENSE).
