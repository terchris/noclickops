# Investigate: Lessons from UIS — patterns to adopt for noclickops

> **IMPLEMENTATION RULES:** Before implementing the plans that come out of this investigation, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Backlog

**Goal**: Survey the [Urbalurba Infrastructure Stack (UIS)](https://github.com/helpers-no/urbalurba-infrastructure) — a substantial sister project with a mature CLI for managing Kubernetes-based developer infrastructure — and identify which of its patterns to **adopt** for `noclickops` v1, which to **defer**, and which to **deliberately diverge** from. Findings here feed back as edits into [`INVESTIGATE-noclickops.md`](INVESTIGATE-noclickops.md).

**Last Updated**: 2026-05-28

**Source surveyed**: `/Users/terje.christensen/learn/helpers/urbalurba-infrastructure/` (cloned from `helpers-no/urbalurba-infrastructure`).

---

## What UIS is, briefly

UIS is a portable platform for running a complete datacenter stack (Kubernetes, observability, databases, AI, auth, ingress, networking) on a developer's laptop, replicable to cloud platforms (AKS, Azure microk8s, Rancher Desktop, multipass, etc.). It's substantial — hundreds of files, dozens of services. Its CLI (`./uis <command>`) has ~50 subcommands across categories: service discovery / deployment / configuration, stacks, templates, platform / network management, secrets, ArgoCD, integration testing, docs generation.

Compared to noclickops:

| | UIS | noclickops |
|---|---|---|
| **Scale** | ~50 subcommands, hundreds of files | ~10 subcommands, ~30 files (planned) |
| **Domain** | Deploys K8s manifests, runs Ansible, manages clusters | Wraps existing pipelines and APIs |
| **Distribution** | Container (`uis-provision-host`) with kubectl/helm/ansible pre-installed; `./uis` host wrapper does `docker exec` | Host scripts with `az`/`gh`/`git`/`jq` as deps |
| **Audience** | Platform-curious developers | Application developers |
| **Per-project state** | `.uis.extend/` + `.uis.secrets/` written by the tool | None — operates against the target repo's existing files |

The **patterns that transcend domain** are what's interesting here.

---

## Patterns to ADOPT (for v1)

### A1 — `lib/` with focused files + sourcing guards

UIS's `provision-host/uis/lib/` has 22 single-purpose files: `logging.sh`, `utilities.sh`, `paths.sh`, `service-scanner.sh`, `first-run.sh`, `secrets-management.sh`, `menu-helpers.sh`, etc. Each begins with a guard:

```bash
[[ -n "${_UIS_LOGGING_LOADED:-}" ]] && return 0
_UIS_LOGGING_LOADED=1
```

Lets multiple scripts source overlapping libraries without redundant work. Standard idiom; reliable.

**Apply**: split `lib/_common.sh` into `lib/logging.sh`, `lib/utilities.sh`, `lib/paths.sh`, `lib/metadata.sh` (the `show_help` + metadata pattern), each with a guard. Same pattern in `.ps1`.

### A2 — Help output grouped by category

UIS's `--help` lists subcommands grouped by purpose ("Interactive", "Service Discovery", "Service Deployment", "Stack Deployment", "Configuration", "Platform", "Network", "Secrets", "Tools", "Information") with a one-line description per command. Much more scannable than a flat list when the count grows.

**Apply**: add a `SCRIPT_CATEGORY` metadata variable on each script (e.g. `git`, `deploy`, `inspect`, `service-lifecycle`). The `noclickops` lister groups output by category. Defines categories in `lib/metadata.sh` so the list of valid categories stays consistent.

### A3 — Service scanner reading metadata from files

UIS's `service-scanner.sh` greps each service script for `SCRIPT_ID` / `SCRIPT_NAME` / `SCRIPT_DESCRIPTION` and builds an in-memory index. Caches results across calls within one invocation.

**Apply**: exactly what `INVESTIGATE-noclickops` [Q5] proposed; UIS's production implementation confirms the pattern works. We can borrow the file naming and parsing style directly.

### A4 — Idempotent first-run wizard

UIS's `uis init` is an interactive first-time setup wizard. `lib/first-run.sh::copy_defaults_if_missing` seeds `.uis.extend/` and `.uis.secrets/` from `templates/` only when they're missing. Idempotent — safe to re-run.

**Apply**: the `install.sh` we proposed under [Q1] follows this shape — create `~/.noclickops/` if missing (clone or pull), print the shell-function snippet, interactively offer to append it to `~/.zshrc` / `~/.bashrc` / `$PROFILE`. Re-running just refreshes. Borrow the "idempotent and safe" framing.

### A5 — `welcome.txt` on first install

UIS ships a `provision-host/uis/templates/welcome.txt` displayed during first-run. Small touch; sets the tone; orients the user.

**Apply**: `install.sh` prints a brief welcome + the next command to try (`noclickops` to list, or a specific subcommand for context). Trivial; high UX value.

### A6 — `AGENTS.md` alongside `CLAUDE.md`

UIS ships BOTH `AGENTS.md` (for Codex / OpenAI-family tooling) and `CLAUDE.md` (for Claude Code) — same content, different audiences. Near-duplicate; reaches two tooling ecosystems instead of one.

**Apply**: add `AGENTS.md` at the noclickops root as a sibling/near-mirror of `CLAUDE.md`. Almost-free coverage gain.

---

## Patterns to CONSIDER but probably DEFER

### B1 — Container-based distribution

UIS runs everything inside `uis-provision-host`. The host `./uis` is a thin `docker exec` wrapper. Means: zero host-side deps; tooling stays in sync with the container; auth/state lives in mounted host dirs.

For noclickops: we have a few host deps (`az`, `gh`, `git`, `jq`). Containerizing would mean pulling a `noclickops` image, mounting `~/.azure` + `~/.config/gh` + `~/.ssh` + the target repo + `pwd`, plus latency on every invocation.

**Verdict**: defer. v1 stays as host scripts with documented prerequisites. Revisit if dep drift becomes a pain or if a future contributor wants reproducible behaviour across very different machines.

### B2 — Stacks / bundles of operations

UIS has `stack list`, `stack info`, `stack install` — install a *group* of related services in one call (e.g. "observability" bundle = grafana + prometheus + loki + tempo + otel).

For noclickops: not v1. Could be relevant once we have natural bundles ("bootstrap a new Lovable service" = `add-service` then `sync-lovable` then `deploy`). Cheap to add later.

### B3 — Template registry from a separate repo

UIS pulls templates from `helpers-no/dev-templates` via `template list` / `template install`. Decouples templates from the tool.

For noclickops: the Lovable template will live inside this repo at `templates/lovable/`. If 3+ stacks emerge (Astro, plain Node, etc.) the registry pattern starts to pay off.

**Verdict**: defer; in-repo templates are fine for v1.

### B4 — Interactive TUI menu (`uis setup`)

UIS's `uis setup` opens a categorized TUI menu with statuses and actions.

For noclickops: most commands have tiny arg lists (`deploy <service> [test|prod]`); a TUI would add latency without clear value. Different audience.

**Verdict**: defer indefinitely unless a real need surfaces.

### B5 — Per-target `.uis.extend/` + `.uis.secrets/` pattern

UIS creates per-project `.uis.extend/` (committed config) and `.uis.secrets/` (gitignored secrets) when it runs against a directory.

For noclickops: target repos already have their own config (`.pipelines/variables/`) and secrets (Key Vault); the tool reads existing structures, doesn't impose new ones. UIS's pattern fits when the tool needs per-target persistent state; we don't.

**Verdict**: not adopted. Different problem shape, not a deferred opportunity.

---

## Patterns we explicitly DIFFER from

### C1 — Numbered ordered files (000-, 010-, 020-, …)

UIS numbers manifests (`000-storage.yaml`, `040-postgres.yaml`, `075-authentik.yaml`) and ansible playbooks for deterministic deployment order. Makes sense in declarative infra-as-code with sequential dependencies.

For noclickops: every command is independent. Numbered filenames would add ceremony without value.

### C2 — Centralized state in a "provision host"

UIS routes everything through one container that owns its own `lib/`, `manage/`, `templates/`. Heavyweight by design — it manages a cluster.

For noclickops: the dispatcher is a shell function, each command is a small standalone script in `bin/`, no persistent runtime state, no central process.

---

## Specific edits to INVESTIGATE-noclickops.md (on approval)

If this investigation is approved, the following changes propagate back into `INVESTIGATE-noclickops.md`:

1. **Repo layout ([Q3])** — refine the `lib/` description to call out UIS-style multi-file split (`lib/logging.sh`, `lib/utilities.sh`, `lib/paths.sh`, `lib/metadata.sh`), each guarded against double-sourcing.
2. **Metadata extension** — add `SCRIPT_CATEGORY` to the standard script header (alongside `SCRIPT_NAME` / `SCRIPT_DESCRIPTION` / `SCRIPT_USAGE` / `SCRIPT_EXAMPLE`). `noclickops` lister groups by category.
3. **PLAN-002 (installer)** — describe the first-run flow as **idempotent**: copy/clone if missing, no-op if present; print a welcome message + next-step command on a fresh install.
4. **PLAN-001 (foundation)** — split `_common.sh` into the lib/ files above; add the sourcing-guard idiom.
5. **Documentation** — add `AGENTS.md` at repo root as a sibling/near-mirror of `CLAUDE.md`.

---

## Out of scope

- Adopting any UIS code directly (different domain; would couple us to their assumptions).
- Containerizing noclickops.
- Stacks / template registry / TUI menu.
- The `.uis.extend/` + `.uis.secrets/` pattern.
- Replicating UIS's command surface (we have ~10 subcommands; they have ~50).

---

## Decisions — RESOLVED 2026-05-28

- ✅ **[U1]** Adopt **A1** — `lib/` separation with sourcing guards.
- ✅ **[U2]** Adopt **A2** — `SCRIPT_CATEGORY` metadata + grouped help output.
- ✅ **[U3]** Adopt **A3** — file-grep service scanner.
- ✅ **[U4]** Adopt **A4** — idempotent first-run wizard inside `install.sh`.
- ✅ **[U5]** Adopt **A5** — `welcome.txt` shown on first install.
- ✅ **[U6]** Adopt **A6** — `AGENTS.md` sibling of `CLAUDE.md`.
- ✅ **[U7]** Defer B1–B4 (container model, stacks, template registry, TUI). Not adopt B5 (per-target state).

---

## Next Steps

- [ ] Review. Reply with `[U<N>] yes/no` per item to lock in.
- [ ] On approval, propagate the accepted A-items into `INVESTIGATE-noclickops.md` as edits (per "Specific edits" above) — no new PLAN files; this investigation refines an existing one.
- [ ] B-items live as documented future opportunities; no PLANs spawned.
- [ ] When `INVESTIGATE-noclickops.md` and this one are both resolved, both move to `plans/completed/` together.
