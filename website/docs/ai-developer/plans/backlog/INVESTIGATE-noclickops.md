# Investigate: `noclickops` v1 — portable script suite for "no clickops" operations

> **IMPLEMENTATION RULES:** Before implementing the plans that come out of this investigation, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Backlog

**Goal**: Design and ship the **v1** of `noclickops` — a portable script suite that automates the day-to-day developer operations across many repos (open PR, merge PR, deploy, scaffold a service, tail logs, see what's deployed, open a shell). **Installed once per developer machine**, **operates on whichever git repo the developer is currently in**, **wraps existing automation rather than re-implementing it**, **works on macOS / Linux / Windows**.

**Last Updated**: 2026-05-28

---

## Why this matters

A developer has many repos and three possible OSes; today they click through Azure DevOps / GitHub web UIs and Azure Portal to do work that's already automatable. The same operations get done many times in different places.

The previous attempt (in `JKL900X016-NerdMeet` under `website/scripts/`) embedded the scripts inside each project repo, with the intent of dropping the folder into newly-created repos. That works once per repo but doesn't solve the *update* problem: when a script changes, every embedding has to be updated by hand. This investigation pivots to **one repo for the tooling, installed per-machine**, with the scripts dispatching against `pwd`'s git root — so one update reaches every dev's every repo.

The previous investigation (`INVESTIGATE-no-clickops.md` in `JKL900X016-NerdMeet`) is **superseded by this one**; that investigation's decisions are inherited as prose under "Inherited decisions" below.

---

## Principles — non-negotiable

### Portability

**No script in this repo may hard-code any target repo's identity.** Not org names, not repo names, not project names, not platform `APP_NAME` values. All such values come from the *target* repo's git remote, its variables files, or environment-variable overrides. This is what makes `noclickops` work against any project the developer `cd`s into.

### Wrap existing automation, never replicate it

`noclickops` triggers and observes existing pipelines and APIs — it never re-implements them locally. When a target repo's pipeline owner ships a new step (Copier upgrade, Bicep change, secrets handling), every `noclickops` user gets it for free because they're calling the same pipeline. Same applies to GitHub / Azure DevOps APIs: we call them, we don't replace them.

### Multi-repo, multi-OS

- **Many repos** — the shell-function dispatcher calls `git rev-parse --show-toplevel` at *call* time, so the same command resolves to the right repo's context based on `pwd`.
- **macOS / Linux / Windows** — Bash function in `~/.zshrc` / `~/.bashrc` covers macOS (zsh), Linux (bash), Windows via Git Bash and WSL. A PowerShell function in `$PROFILE` covers native Windows PowerShell. Every command ships `.sh` and `.ps1` siblings.

### Multi-provider (GitHub *and* Azure DevOps)

`noclickops`'s own repo is on GitHub, but the **target repos** it operates against can be on either GitHub or Azure DevOps. Commands like `create-pr` / `merge-pr` detect the target's host from its git remote and dispatch to `gh` or `az repos` accordingly. Commands that wrap pipelines (`deploy`, `add-service`) assume the target's pipeline platform (Azure DevOps for the Red Cross stack today; GitHub Actions in the future is out of v1 scope).

---

## v1 command set

| Command | Purpose | Target-side needs |
| --- | --- | --- |
| `noclickops` | Discovery — list all commands with descriptions | none |
| `create-pr "<title>"` | Open a PR from current branch to `main` | `gh` or `az` auth |
| `merge-pr <pr-id>` | Squash-complete the PR + sync local main + delete branches | `gh` or `az` auth |
| `deploy <service> [test\|prod] [--watch]` | Run the service's CD pipeline | `az` auth + ADO read |
| `add-service <name> [--public]` | Trigger the add-service pipeline (Copier + PR + new CD) | `az` auth + ADO write |
| `clean-sample <service>` | Strip the Next.js Copier sample from a service folder | git only |
| `sync-lovable <lovable-repo> <service>` | Mirror a Lovable repo into a service folder; render Vite/nginx template; write `health.json` | git + filesystem |
| `info <service> [--env test\|prod]` | Describe a service's deployment: internal name, port, external URL, RG, sub, image repo, pipeline, live `/health`, recent runs | local files + ADO; sub-read for full FQDN |
| `logs <service> [--env test\|prod] [--follow]` | Tail Azure Container Apps logs | Reader on the env subscription |
| `shell <service> [--env test\|prod]` | Drop into a running container | Reader on the env subscription |
| `update` | `git pull` the installed `noclickops` repo | network |

---

## Inherited decisions (from the superseded `INVESTIGATE-no-clickops.md` in FRT)

Recorded here as prose so future readers don't have to chase IDs across repos. **All resolved unless noted.**

1. **Folder naming**: the suite is branded `noclickops` (no hyphen). The discovery command shares the name.
2. **`add-service`** wraps the existing ADO pipeline (`az pipelines run --name "$AZDO_REPO-add-service" --parameters …`); does **not** re-implement Copier locally. Pipelines are maintained; our job is to trigger them.
3. **`logs`** and **`shell`** ship with fail-closed messaging when the dev's `az` login doesn't have Reader access to the env's Azure subscription. Documented limitation; follow-up admin task: grant Reader to a dev AD group.
4. **`info`** reads mostly local files (variables YAML + `health.json`) and ADO data (pipeline runs); the few sub-only fields (Internal FQDN, live replica count) print `—` when access is missing — so `info` is usable for every dev.
5. **Help + metadata**: every script declares `SCRIPT_NAME` / `SCRIPT_DESCRIPTION` / `SCRIPT_USAGE` / `SCRIPT_EXAMPLE` near the top; `--help` reads them via a shared `show_help` helper in `lib/_common.sh` / `.ps1`. Borrowed pattern from `devcontainer-toolbox/.devcontainer/additions/`.
6. **Discovery**: `noclickops` (no args) grep-extracts the metadata from every script in `bin/` and prints a table. Single source of truth = the script files themselves.
7. **Typability**: `~/.zshrc` / `~/.bashrc` / `$PROFILE` shell function uses `git rev-parse --show-toplevel` to locate the install dir's `bin/<cmd>.{sh,ps1}` and exec it. The same function gives subcommand dispatch (`noclickops deploy …`) for free.
8. **PowerShell parity**: every command ships `.sh` and `.ps1` siblings. PowerShell is part of the contract because the team has Windows users.
9. **Templates**: shipped in the suite at `templates/<stack>/` (e.g. `templates/lovable/`) and copied into target repos at run time by commands that need them (`sync-lovable`). Not embedded per-project.
10. **`/health` for Lovable services**: nginx serves a static `health.json` written by `sync-lovable` carrying `source.repo` + `source.commit` + `source.commit_date`. PWA `navigateFallback` intercepting `/health` in a browser is a known limitation (works for probes / `curl` / Incognito).

---

## Open architecture decisions

These are the v1 questions specific to `noclickops` as a separately-installed repo.

### [Q1] Installation mechanism

How a developer first installs `noclickops`.

- **[Q1a]** `curl -fsSL <raw-url> | bash` one-liner that clones to `~/.noclickops/` and prints the shell-function snippet to paste. ← **recommended.** Two operations: clone + advise. Standard idiom (homebrew, rust, nvm).
- **[Q1b]** Manual `git clone` + manual edit of `~/.zshrc`. No installer script. Lower magic; higher friction.
- **[Q1c]** Homebrew / `winget` / package manager. Best UX; biggest infra commitment. Defer until adoption justifies it.

PowerShell mirror in `install.ps1` for Windows-native installs.

### [Q2] Update mechanism

How the user gets a newer version.

- **[Q2a]** `noclickops update` — a regular command in the suite that does `git -C ~/.noclickops pull --ff-only`. ← **recommended.** Self-hosted, no extra infra.
- **[Q2b]** Auto-update on each invocation (cheap `git fetch` + compare). Higher freshness but slows every command and brittle offline.
- **[Q2c]** Periodic check (once per day on `noclickops` invocation). Middle ground.

### [Q3] Repository layout

Where the executable scripts live in this repo.

- **[Q3a]** `bin/` for scripts, `lib/` for shared helpers, `templates/` for stack templates, `install.{sh,ps1}` at the root. ← **recommended** — conforms to common project layouts; the shell function dispatches to `bin/<cmd>.{sh,ps1}` cleanly.
- **[Q3b]** Flat — all scripts at repo root. Simpler. Doesn't scale past ~10 scripts; clutters the root.

### [Q4] Versioning approach

- **[Q4a]** Track `main` only; `noclickops update` always fast-forwards to latest `main`. ← **recommended for v1** — simplest; one release channel; matches how dev tooling typically works at this maturity.
- **[Q4b]** Semver tags + a `--version` pin in the install (`~/.noclickops` checked out at a tag). Stable but heavier process.

### [Q5] How target repos opt into `noclickops`

What identifies a repo as "a noclickops-using repo" beyond "the dev has noclickops installed."

- **[Q5a]** Nothing. Every script just runs against the current repo; if the repo lacks the structures the script expects (e.g. `services/<service>/.pipelines/variables/<env>.yaml`), the script reports it. **Per-script discovery**, no opt-in marker. ← **recommended for v1** — zero ceremony.
- **[Q5b]** A `.noclickops` marker file at repo root with config (subscription overrides, custom paths, etc.). Per-repo config; useful when something needs customization. Add when the need emerges.

---

## Out of scope for v1

- Secrets management (KV rotation).
- Multi-service dashboard / global status across all services.
- GitHub Actions target (we wrap Azure DevOps pipelines for `deploy` / `add-service`; GHA support is a future investigation).
- A "doctor" / `setup` command (verify `az` / `gh` / `git` / `jq` are present and authenticated). Useful but not blocking; can be added later.
- Telemetry / usage tracking.

---

## v1 deliverables — proposed PLANs

After approval. Dependency-ordered so each PLAN builds on what landed before:

- **PLAN-001-foundation** — repo skeleton (`bin/`, `lib/`, `templates/`, `README.md` at root), `lib/_common.{sh,ps1}` with the portability helpers (parse org / project / repo from any git remote; parse `APP_NAME` from target repo's `.pipelines/variables/common.yaml`), `show_help` helper, the metadata convention. Adds **`noclickops update`** (script under `bin/`).
- **PLAN-002-noclickops-and-installer** — `bin/noclickops.{sh,ps1}` lister (the discovery command), plus `install.{sh,ps1}` at the root that clones to `~/.noclickops/` and prints the shell-function snippet. Documents the Bash + PowerShell snippets in `README.md`.
- **PLAN-003-pr-and-merge** — `create-pr` + `merge-pr`. Detect the target's git remote (GitHub vs ADO) and dispatch to `gh` or `az repos`. This is the first PLAN where multi-provider matters.
- **PLAN-004-deploy** — `deploy`. Wraps `az pipelines run` against the target repo's CD pipeline; respects the `<repo>-<service>-CD` naming convention.
- **PLAN-005-clean-sample** — `clean-sample`. Pure local; strips the Next.js Copier sample. Smallest of the new PLANs; good place to validate the metadata/help pattern on a near-trivial script.
- **PLAN-006-sync-lovable** — `sync-lovable` + `templates/lovable/` (`Dockerfile` + `nginx.conf` carried over from FRT, with the `/parties`-style nginx fix applied). Renders templates into the target repo; generates `health.json`.
- **PLAN-007-add-service** — `add-service`. Wraps `az pipelines run --name "$AZDO_REPO-add-service" …`.
- **PLAN-008-info** — `info`. The richest local-data command. Establishes the env-aware `SUBSCRIPTION_ID` lookup pattern that PLAN-009 and PLAN-010 reuse.
- **PLAN-009-logs** — `logs`. Wraps `az containerapp logs show`. Fail-closed access messaging.
- **PLAN-010-shell** — `shell`. Wraps `az containerapp exec`. Same access pattern as `logs`.

After PLAN-010 the suite is feature-complete and ready for first-customer dry-runs against the FRT repo. The FRT repo's `website/scripts/` is then removed in a separate PR there; its `project-nerdmeet.md` / `CLAUDE.md` / `AZURE-DEVOPS.md` get edits pointing at the `noclickops` install.

---

## Failure modes the suite handles

Every script handles, with explicit messages:

- **Not in a git repo** (the dispatcher) → "noclickops: not in a git repo."
- **Unknown subcommand** (the dispatcher) → "noclickops: no such command '<cmd>' (try: noclickops)."
- **`az` / `gh` missing or unauthenticated** (commands that need them) → exit naming the missing tool + login command.
- **Target repo doesn't match expectations** (e.g. `services/<service>/` doesn't exist) → exit naming what's missing.
- **Subscription read access missing** (`logs` / `shell` / some `info` fields) → fail-closed with the missing permission named.
- **`git pull` fails in the install dir** (`noclickops update`) → preserves prior state; reports the error.

---

## Next Steps

- [ ] Review this investigation. Reply with `[Q<N>] yes / no / alternative` on the five open architecture questions above; revise as needed.
- [ ] On approval, spawn ordered PLANs as listed in "v1 deliverables."
- [ ] First customer of the suite: re-point `JKL900X016-NerdMeet` from its embedded `website/scripts/` at the installed `noclickops`, and delete the embedded copy.
- [ ] **In the superseded FRT investigation**: mark `INVESTIGATE-no-clickops.md` as superseded by this one, with a link.
