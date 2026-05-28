# PLAN-002: Installer, shell function, grouped lister

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-28

**Goal**: Make `noclickops` a typeable command, ship an idempotent installer, upgrade the lister to category-grouped output.

**Last Updated**: 2026-05-28

**Investigations**:

- [INVESTIGATE-noclickops.md](../backlog/INVESTIGATE-noclickops.md) → [Q1] (install model), [Q2] (shell function), "How `noclickops` becomes typeable" section
- [INVESTIGATE-uis-lessons.md](../backlog/INVESTIGATE-uis-lessons.md) → A4 (idempotent first-run), A5 (welcome.txt), A2 (grouped help)

**Depends on**: PLAN-001 (lib/, metadata convention, baseline `noclickops` + `update` scripts).

**Priority**: High — the typability and one-line install are core UX promises.

---

## Problem

After PLAN-001, scripts are invoked by full path (`~/.noclickops/bin/noclickops.sh`). The investigation requires `noclickops <subcommand>` to also work — which needs:

1. A **shell function** in the user's shell init that dispatches by argv.
2. An **installer** that clones the repo into `~/.noclickops/`, wires the function in, and is **idempotent** (safe to re-run forever).
3. A **grouped lister** so output stays scannable as PLANs 003–010 fill `bin/`.

---

## What it delivers

| File | Role |
| --- | --- |
| `install.sh` / `install.ps1` (repo root) | Bootstrap: clone-or-pull + write source line to rc file. Supports `curl \| bash`. Idempotent. |
| `shell/init.sh` / `shell/init.ps1` | Defines the `noclickops` function. Users `source` this single file; the function evolves via `git pull` without rc edits. |
| `templates/welcome.txt` | One-screen first-run greeting (UIS A5 pattern). |
| `bin/noclickops.{sh,ps1}` (upgraded) | Category-grouped lister; skips empty sections; canonical order (`meta`, `git`, `deploy`, `service-lifecycle`, `inspect`). |

**Installer behaviours**:

- Env-overridable: `NOCLICKOPS_DIR` (default `$HOME/.noclickops`), `NOCLICKOPS_REPO_URL` (default GitHub URL).
- If `$NOCLICKOPS_DIR/.git` exists → `git pull --ff-only` (no re-clone).
- Single source line added to rc file (`~/.zshrc` if zsh, else `~/.bashrc`; `$PROFILE` on Windows). Line added exactly once across re-runs — the grep guard checks before append.
- Prompts via `/dev/tty` so `curl … | bash` still gets interactivity; falls back to print-only if no TTY.
- Prints `welcome.txt` on first install.

**Shell function** (from `INVESTIGATE-noclickops.md` → "How `noclickops` becomes typeable"):

```text
noclickops [<cmd> [args...]]
  no args        → run ~/.noclickops/bin/noclickops.sh (the lister)
  <cmd> [args]   → run ~/.noclickops/bin/<cmd>.sh args
  <unknown cmd>  → clear error + hint
```

---

## Phases

1. `shell/init.{sh,ps1}` — define the function.
2. `install.sh` — standalone bootstrap (no lib/ deps; inlines its own log helpers).
3. `install.ps1` — PowerShell mirror.
4. `templates/welcome.txt`.
5. Upgrade `bin/noclickops.{sh,ps1}` to grouped output (Bash 3.2-compatible — no associative arrays).
6. End-to-end smoke test against a temp install dir.

---

## Validation criteria

- Fresh install via `NOCLICKOPS_DIR=$tmp NOCLICKOPS_REPO_URL=<local> install.sh` → working install.
- Re-running same install is a no-op pull, not a re-clone or error.
- rc-file source line added exactly once after N invocations.
- `source ~/.noclickops/shell/init.sh && noclickops` → lists commands.
- `noclickops update` → dispatches to `update.sh`.
- `noclickops bogus` → clear error, non-zero exit.
- Lister shows "Meta" section with `noclickops`, `update`; other sections suppressed when empty.

---

## Completion notes (2026-05-28)

All six phases shipped on `feature/ai-developer-bootstrap`.

**Smoke test** (`NOCLICKOPS_DIR` = temp dir, `NOCLICKOPS_REPO_URL` = local working tree, `HOME` = sandbox):

| # | Test | Result |
| --- | --- | --- |
| 1 | Fresh install: clones, wires `~/.zshrc`, prints welcome | ✅ |
| 2 | Install dir populated with `bin/`, `lib/`, `shell/`, `templates/`, `install.sh`, `README.md`, … | ✅ |
| 3 | rc file gets the source line exactly once on first install | ✅ |
| 4 | Re-running installer pulls instead of re-cloning, leaves rc alone, **suppresses welcome banner** | ✅ |
| 5 | rc file still has exactly one source line after re-run | ✅ |
| 6 | `source shell/init.sh; noclickops` → grouped lister output | ✅ |
| 7 | `noclickops update --help` → dispatches to `update.sh`, prints metadata help | ✅ |
| 8 | `noclickops bogus` → "no such command 'bogus' (try: noclickops)", exit 1 | ✅ |
| 9 | Lister hides empty category sections (only "Meta" shown) | ✅ |

**Fixes applied during smoke test** (amended into the PLAN-002 commit):

1. **`/dev/tty` stderr leak**. First run in non-interactive mode emitted `/dev/tty: Device not configured` when there was no controlling terminal. Wrapped the `read … < /dev/tty` in a `{ … } 2>/dev/null` block so the device error never reaches stderr; the function still falls through to the default answer.
2. **Welcome-on-update wart**. The full welcome banner was reprinting on every re-run. Per UIS A5, welcome is a first-install affordance. Added `FRESH_INSTALL=0/1` flag set inside the clone branch; welcome gates on it. Mirrored to `install.ps1` (`$FreshInstall`).

**Deviations from the PLAN as written**: none material. PowerShell ports ship but are unverified on Mac (no `pwsh`); each `.ps1` carries a `# NOTE: unverified on Mac` header.

**`templates/.gitkeep`** removed — `templates/welcome.txt` now occupies the dir.

**Shell function dispatch verified**:

| Invocation | Result |
| --- | --- |
| `noclickops` | runs `~/.noclickops/bin/noclickops.sh` (lister) |
| `noclickops update` | runs `~/.noclickops/bin/update.sh` |
| `noclickops update --help` | passes `--help` through; `show_help` reads metadata |
| `noclickops bogus` | error to stderr, exit 1 |

PLAN-001's foundation now translates into the typeable UX promised by the investigation.
