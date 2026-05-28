# PLAN-001: Foundation — repo skeleton, `lib/`, metadata convention, `noclickops update`

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Completed 2026-05-28

**Goal**: Lay down the foundation every other PLAN builds on — the directory layout, the `lib/` helpers (with sourcing guards), the metadata convention every `bin/` script will follow, an `AGENTS.md` sibling for `CLAUDE.md`, and the first two scripts: `noclickops update` (real implementation) and a `noclickops` stub (real lister comes in PLAN-002).

**Last Updated**: 2026-05-28

**Investigations**:

- [INVESTIGATE-noclickops.md](INVESTIGATE-noclickops.md) — the v1 design
- [INVESTIGATE-uis-lessons.md](INVESTIGATE-uis-lessons.md) — `[U1]`–`[U6]` adopted; `lib/` split, metadata with `SCRIPT_CATEGORY`, `AGENTS.md`

**Blocks**: PLAN-002 onwards — every later PLAN sources files from `lib/`.

**Priority**: High.

---

## Completion notes (2026-05-28)

All five phases shipped on branch `feature/ai-developer-bootstrap`.

**Smoke-test results** (run in-place against the working tree, with `NOCLICKOPS_DIR` resolving to the repo root via `lib/paths.sh`):

| # | Test | Result |
| --- | --- | --- |
| 1 | `bin/noclickops.sh` lists both commands with descriptions from metadata | ✅ |
| 2 | `bin/noclickops.sh --help` prints the metadata-driven help block | ✅ |
| 3 | `bin/update.sh --help` prints the same uniform help shape | ✅ |
| 4 | `update.sh` against a non-git dir fails fast with clear error | ✅ |
| 5 | `TARGET_REPO` empty outside a repo, populated inside | ✅ |
| 6 | Sourcing-guards prevent double-initialization on repeated `.` | ✅ |

**Deviations from the PLAN as written**:

- `lib/paths.sh` resolves `NOCLICKOPS_DIR` as **one level up** from `lib/` (the parent of `$(dirname "${BASH_SOURCE[0]}")`), not "3 parents above" as the PLAN's prose claimed. The PLAN prose was confused; the implementation is correct.
- PowerShell ports of every file shipped but were **not executed** — no `pwsh` on the maintainer's Mac. Each `.ps1` carries a "NOTE: unverified on Mac" header; Windows verification deferred to whoever first runs it on Windows.

**What this PLAN does NOT do — typability still comes in PLAN-002**:

After PLAN-001, scripts are invoked by full path (e.g. `~/.noclickops/bin/noclickops.sh`). The typeable `noclickops <subcommand>` form needs the shell function from [`INVESTIGATE-noclickops.md` → "How `noclickops` becomes typeable"], which `install.{sh,ps1}` (PLAN-002) will print for the user to paste.

---

## Problem

`noclickops` has no code yet — just docs. PLAN-002 (`noclickops` lister + installer) will need `lib/metadata.{sh,ps1}` to grep script headers; PLAN-003+ (`create-pr`, `deploy`, …) will all `source lib/logging.sh` + `lib/utilities.sh` + `lib/paths.sh` for shared behaviour. This PLAN authors all of that so the rest of the work is purely additive.

It also delivers the smallest end-user-visible feature — `noclickops update` — so the foundation can be tested end-to-end against a real `~/.noclickops/` clone before PLAN-002 lands.

## What this PLAN does NOT do — typability comes in PLAN-002

After PLAN-001 lands and the user has cloned the repo to `~/.noclickops/`, they invoke scripts by **full path**:

```bash
~/.noclickops/bin/noclickops.sh          # the stub lister
~/.noclickops/bin/update.sh              # pulls latest
~/.noclickops/bin/update.sh --help       # metadata-driven help
```

The plain `noclickops` and `noclickops deploy …` forms require the **shell function** documented under "How `noclickops` becomes typeable" in `INVESTIGATE-noclickops.md` — that function lives in the user's `~/.zshrc` / `~/.bashrc` / `$PROFILE`. **PLAN-002's `install.{sh,ps1}` is what prints the snippet** for the user to paste; PLAN-001 ships only the scripts the function dispatches *to*.

This split is deliberate: PLAN-001 is end-to-end runnable via full paths (so the foundation is testable on its own); PLAN-002 layers in the install UX. Foundation first, polish second.

---

## Phase 1: Repo skeleton + root docs

- [ ] 1.1 Create `bin/`, `lib/`, `templates/` (with a `.gitkeep` in `templates/` since v1 doesn't ship a template until PLAN-006).
- [ ] 1.2 Write a minimal `README.md` at the repo root — what `noclickops` is, the install command (stub: "see PLAN-002"), and one-line usage examples. Detailed install instructions land with PLAN-002.
- [ ] 1.3 Write `AGENTS.md` at the repo root as a near-mirror of `CLAUDE.md` ([U6]). Same content; `AGENTS.md` is the entry point for Codex / OpenAI tooling, `CLAUDE.md` for Claude. To minimise drift, the body says "same content as CLAUDE.md — see that file" and both point at `project-noclickops.md` as the source of truth.

**Validation**: `ls` shows `bin/ lib/ templates/ README.md AGENTS.md CLAUDE.md` at the root. Both AI-tooling files reference `project-noclickops.md`.

---

## Phase 2: `lib/` Bash files

Each file starts with a sourcing guard (`[[ -n "${_NCO_*_LOADED:-}" ]] && return 0`) so multiple `bin/` scripts can source overlapping libs without redundant work.

- [ ] 2.1 `lib/logging.sh` — colored output helpers:
  - `log_info "<msg>"` (blue ℹ icon)
  - `log_success "<msg>"` (green ✓)
  - `log_warn "<msg>"` (yellow ⚠)
  - `log_error "<msg>"` (red ✗, to stderr)
  - `log_step "<msg>"` (bold; for top-of-phase banners)
- [ ] 2.2 `lib/utilities.sh` — shared helpers:
  - `die "<msg>"` — print to stderr (using `log_error`), exit 1.
  - `require_cmd <name>` — `command -v <name> >/dev/null` or die with "<name> not found; install …" hint.
  - `set -euo pipefail` is left to each script (not the lib) — libs only get sourced, they shouldn't change the caller's shell mode.
- [ ] 2.3 `lib/paths.sh` — define and export at source time:
  - `NOCLICKOPS_DIR` — the install dir (resolved as 3 parents above `lib/paths.sh`: i.e. wherever this lib lives, `noclickops` is that lib's grandparent's parent).
  - `BIN_DIR="$NOCLICKOPS_DIR/bin"`
  - `LIB_DIR="$NOCLICKOPS_DIR/lib"`
  - `TEMPLATES_DIR="$NOCLICKOPS_DIR/templates"`
  - `TARGET_REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"` — the repo the dev is currently in; empty if not in a git repo. Scripts that need it check non-empty themselves.
- [ ] 2.4 `lib/metadata.sh`:
  - The metadata-variable contract: every `bin/*.sh` declares `SCRIPT_NAME`, `SCRIPT_DESCRIPTION`, `SCRIPT_USAGE`, `SCRIPT_EXAMPLE`, `SCRIPT_CATEGORY` near the top (commented `# --- noclickops metadata ---` header).
  - `parse_metadata <file>` — grep-extracts the five fields from a script file (NOT by sourcing it — safe).
  - `show_help <file>` — calls `parse_metadata` and prints a consistent help block to stdout. Exits 0.
  - `valid_category <category>` — returns 0 if the category is in the v1 set (`meta`, `git`, `deploy`, `service-lifecycle`, `inspect`); 1 otherwise. PLAN-002's lister uses this to sanity-check.
- [ ] 2.5 Syntax-check each: `bash -n lib/*.sh`.

**Validation**: each lib sources cleanly in isolation; `parse_metadata` on a stub test file returns the expected values; `show_help` prints a readable block; the sourcing guards prevent re-init when the same lib is sourced twice in the same shell.

---

## Phase 3: `lib/` PowerShell mirrors

Functional parity with Phase 2. Same guards (`if ($script:NCO_*_LOADED) { return }; $script:NCO_*_LOADED = $true`).

- [ ] 3.1 `lib/logging.ps1` — `Log-Info` / `Log-Success` / `Log-Warn` / `Log-Error` / `Log-Step` using `Write-Host` with `-ForegroundColor`.
- [ ] 3.2 `lib/utilities.ps1` — `Die`, `Require-Cmd`.
- [ ] 3.3 `lib/paths.ps1` — sets `$script:NCO_INSTALL_DIR`, `$script:NCO_BIN_DIR`, etc. (PowerShell namespacing uses `$script:` scope where Bash uses globals).
- [ ] 3.4 `lib/metadata.ps1` — `Parse-Metadata`, `Show-Help`, `Valid-Category`. Uses `Select-String` for the grep equivalent.
- [ ] 3.5 Inspection-only sanity check (no `pwsh` on this dev machine — Windows users are the verification path; this caveat is documented in each PowerShell file's header).

**Validation**: visual diff of Bash and PowerShell parity — function names map, same arguments, same outputs in normal cases.

---

## Phase 4: `bin/update` and `bin/noclickops` stub

The first two real scripts. Both demonstrate the metadata pattern.

- [ ] 4.1 `bin/update.sh`:
  - Metadata block: `SCRIPT_CATEGORY="meta"`, name `update`, description "Pull the latest noclickops from origin.", usage `noclickops update`.
  - Sources `lib/logging.sh`, `lib/utilities.sh`, `lib/paths.sh`, `lib/metadata.sh`.
  - Dispatches `-h` / `--help` to `show_help "$0"`.
  - Runs `git -C "$NOCLICKOPS_DIR" pull --ff-only` (via `require_cmd git` first); `die` with a clear message on failure.
- [ ] 4.2 `bin/noclickops.sh` (stub):
  - Metadata block: `SCRIPT_CATEGORY="meta"`, name `noclickops`, description "List all noclickops commands grouped by category.", usage `noclickops [<subcommand> [args]]`.
  - For PLAN-001 the body just prints "PLAN-002 implements the real lister; here are the scripts found in `bin/`:" and `ls`'s `bin/*.sh` with the basename. PLAN-002 replaces it.
- [ ] 4.3 `bin/update.ps1` + `bin/noclickops.ps1` — PowerShell siblings, same behaviour.
- [ ] 4.4 `chmod +x bin/*.sh`.
- [ ] 4.5 Syntax-check: `bash -n bin/*.sh`.

**Validation**: `./bin/update.sh --help` prints the metadata-driven help block. `./bin/noclickops.sh` prints the stub listing. `./bin/update.sh` (without args) succeeds against the locally-cloned `noclickops` repo (the test dev machine has it at `/Users/terje.christensen/learn/helpers/noclickops/`).

---

## Phase 5: End-to-end smoke test

The PLAN-002 installer doesn't exist yet, so we simulate the "installed" state manually for a smoke test.

- [ ] 5.1 In a scratch dir, `git clone https://github.com/terchris/noclickops.git ~/.noclickops-test` (a parallel checkout, won't conflict with the real one).
- [ ] 5.2 `~/.noclickops-test/bin/noclickops.sh` → expect the stub listing showing `noclickops` and `update`.
- [ ] 5.3 `~/.noclickops-test/bin/update.sh` → expect "Already up to date." plus a `log_success`.
- [ ] 5.4 `~/.noclickops-test/bin/update.sh --help` → expect the metadata-driven help block.
- [ ] 5.5 Cleanup: `rm -rf ~/.noclickops-test`.

**Validation**: every command returns 0; output matches expectations; no missing-lib or missing-cmd errors.

---

## Acceptance Criteria

- [ ] `bin/`, `lib/`, `templates/` exist (templates has `.gitkeep`).
- [ ] `README.md`, `AGENTS.md`, `CLAUDE.md` all at root; `AGENTS.md` mirrors `CLAUDE.md`.
- [ ] `lib/{logging,utilities,paths,metadata}.{sh,ps1}` exist with sourcing guards.
- [ ] `bin/{update,noclickops}.{sh,ps1}` exist, executable, with metadata headers.
- [ ] `bash -n` passes on every shipped `.sh`.
- [ ] Smoke test (Phase 5) green.
- [ ] No `.ps1` runtime verification on this dev machine — documented in the script headers.

---

## Implementation Notes

**Sourcing guards** are at the top of every `lib/` file. The variable name encodes the lib so collisions can't happen:

```bash
[[ -n "${_NCO_LOGGING_LOADED:-}" ]] && return 0
_NCO_LOGGING_LOADED=1
```

PowerShell equivalent:

```powershell
if ($script:NCO_LOGGING_LOADED) { return }
$script:NCO_LOGGING_LOADED = $true
```

**`parse_metadata` reads, doesn't source.** Sourcing would execute the script. We `grep`-extract the five fields with a regex anchored on `^SCRIPT_<NAME>="..."$` (and PowerShell `^\$Script:Script<Name> = '...'$` if/when the PowerShell metadata convention firms up — for now PowerShell uses the same flat `$SCRIPT_NAME="..."` syntax as Bash for parsing parity).

**`TARGET_REPO` is allowed to be empty.** Some commands operate on `pwd`'s git root (`deploy`, `info`, `logs`, …); others don't need it (`update` operates on `NOCLICKOPS_DIR`). Each script checks the values it needs and `die`s if missing — `lib/paths.sh` itself is non-fatal even outside a git repo.

**`AGENTS.md` mirroring CLAUDE.md** — for v1 we use a "see CLAUDE.md" body to avoid drift. UIS keeps both files in full sync; we can promote ours to a real mirror later if the two tooling families need different framing.

---

## Files to Modify / Create

**Create**:

- `bin/noclickops.sh`, `bin/noclickops.ps1`
- `bin/update.sh`, `bin/update.ps1`
- `lib/logging.sh`, `lib/logging.ps1`
- `lib/utilities.sh`, `lib/utilities.ps1`
- `lib/paths.sh`, `lib/paths.ps1`
- `lib/metadata.sh`, `lib/metadata.ps1`
- `templates/.gitkeep`
- `README.md` (root)
- `AGENTS.md` (root)
