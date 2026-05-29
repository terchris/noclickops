# PLAN-106: Slim install via git sparse-checkout

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Backlog

**Goal**: Cut a fresh `noclickops` install from ~10 MB to ~250 KB by sparse-checking out only the folders users actually run from (`bin/`, `lib/`, `templates/`). `website/`, `tests/`, `.github/`, and the plans tree stay in the repo but never reach user disks.

**Last Updated**: 2026-05-29

**Investigation**: [INVESTIGATE-plans-and-scaffolding.md](INVESTIGATE-plans-and-scaffolding.md) (this PLAN is the "PLAN-A — Sparse-checkout slim install" entry)

**Prerequisites**: none.

**Blocks**: nothing — this PLAN is standalone. PLAN-107 / 108 / 109 (the scaffolding trio) ship later in their own PR.

**Priority**: Medium — install bloat is real but not painful enough to block work. Shipping this first because it's small, isolated, and reversible.

**Branch**: `feat/v1.5.1-slim-install`.

---

## Problem

`install.sh` does a plain `git clone` of the whole repo. As of v1.5.0:

| Folder | Size | Used at runtime? |
|---|---|---|
| `bin/` | 120 KB | yes — every command |
| `lib/` | 72 KB | yes — sourced by bin |
| `templates/` | 12 KB | yes — `welcome.txt` + `lovable/` |
| `scripts/` | 20 KB | no — internal docs generator |
| `tests/` | 108 KB | no — contributor test suite |
| `website/` | ~9 MB | no — docs site source, built in CI |
| `.github/` | 8 KB | no — CI workflows |
| `plans/` (under `website/docs/`) | growing | no — project management history |

~95 % of every user's `~/.noclickops` is content they never touch, and the `website/docs/ai-developer/plans/completed/` tree grows monotonically with each shipped PLAN.

Sparse-checkout fixes this without moving any files — git materialises only the configured paths in the working tree. The full repo history stays in `.git/` (so `git log` etc. still work) but the working tree shrinks to what's actually run.

---

## What it delivers

### `install.sh` — sparse-checkout on clone

After `git clone`, the installer initialises cone-mode sparse-checkout with the runtime-only path set:

```bash
git -C "$NOCLICKOPS_DIR" sparse-checkout init --cone
git -C "$NOCLICKOPS_DIR" sparse-checkout set bin lib templates shell
```

Cone mode requires git 2.25+ (January 2020); already universal on supported macOS / Linux / WSL / Git Bash.

### `install.sh` — slim existing installs on re-run

After the existing `git pull --ff-only` for already-installed users, the installer checks whether sparse-checkout is enabled and turns it on if not — so anyone who re-runs `install.sh` to upgrade from v1.5.0 gets the slim layout. No surprises: the script prints what it's about to do.

### `bin/update.sh` — no code change, header note only

`git pull --ff-only` is sparse-aware (git won't materialise excluded paths). Update behaviour is unchanged. Add a comment in the header noting this so the next reader knows the interaction was considered.

### `version.txt` → 1.5.1

Patch bump — install behaviour change only; no new commands, no CLI surface change.

### `README.md` — short note in the install section

One paragraph after the install one-liner explaining what gets checked out (and that contributors who want the full tree can `git clone` the repo directly instead of going through the installer).

### What this PLAN does NOT do

- **No content moves.** `website/`, `plans/`, `tests/` all stay exactly where they are in the repo. Only the *user-side checkout* changes.
- **No `bin/update.sh` logic changes.** Adding a "convert to sparse" path to `update.sh` is unnecessary — re-running `install.sh` is the documented way to change the install layout.
- **No partial clone (`--filter=blob:none`).** That would shrink `.git/` itself too, but introduces lazy blob fetching at runtime. Not worth the operational complexity for the ~2-3 MB it'd save on top of sparse-checkout.
- **No `noclickops` subcommand for sparse management.** Users who want the full clone use `git clone` directly instead of `install.sh`.
- **No opt-out env var.** The installer's job is to set users up to run commands — the slim tree is the right layout for that audience. Contributors who need the full tree (to edit `website/` or `tests/`) clone the repo the normal way, not through `install.sh`.

---

## Phases

### Phase 1: Add sparse-checkout to the clone path — DONE 2026-05-29

#### Tasks

- [x] 1.1 Added `slim_checkout()` helper in `install.sh`; called after `git clone` succeeds.
- [x] 1.2 Prints `ok "Slim layout applied (bin/ lib/ templates/ shell/ only)."` on completion.
- [x] 1.3 Comment block at top of `install.sh` documents the slim-by-default behaviour. Validation passed: fresh install via mktemp produces a 240 KB working tree (3 MB `.git/`).

#### Validation

```bash
# Manual test, fresh install:
rm -rf /tmp/noclickops-test
NOCLICKOPS_DIR=/tmp/noclickops-test \
  NOCLICKOPS_REPO_URL=$(pwd) \
  bash install.sh < /dev/null
du -sh /tmp/noclickops-test          # expect < 500 KB working tree
ls /tmp/noclickops-test              # expect only bin/ lib/ templates/ shell/ + LICENSE README.md install.sh install.ps1 version.txt
```

---

### Phase 2: Slim existing installs on re-run — DONE 2026-05-29

#### Tasks

- [x] 2.1 In the "already installed" branch, check `core.sparseCheckout` config; if not `true`, run `slim_checkout()`.
- [x] 2.2 Same helper as Phase 1 — idempotent, safe to call on either path.
- [x] 2.3 `info` line printed: "Slimming install — restricting working tree to bin/ lib/ templates/ shell/ only." + a hint about `git sparse-checkout disable` to restore. Validation passed: upgrade flow (full clone → re-run installer) went from 1.6 MB → 240 KB working tree.

#### Validation

```bash
# Manual test, upgrade flow:
rm -rf /tmp/noclickops-test
git clone . /tmp/noclickops-test     # simulates an existing v1.5.0 full install
du -sh /tmp/noclickops-test          # baseline ~10 MB
NOCLICKOPS_DIR=/tmp/noclickops-test \
  NOCLICKOPS_REPO_URL=$(pwd) \
  bash install.sh < /dev/null
du -sh /tmp/noclickops-test          # should now be < 500 KB
```

---

### Phase 3: `bin/update.sh` header note + README

#### Tasks

- [ ] 3.1 Add a short comment block at the top of `bin/update.sh` noting that `git pull --ff-only` is sparse-aware and doesn't need adjustment, but pointing readers at `install.sh` if they want to change the sparse set.
- [ ] 3.2 Add a paragraph after the install one-liner in `README.md`:

   > **Slim by default.** The installer sparse-checks-out only the folders users run from (`bin/`, `lib/`, `templates/`) — around 250 KB instead of the full ~10 MB. Contributors who want the full tree should `git clone` the repo directly instead of using the installer.

#### Validation

User confirms README reads clearly.

---

### Phase 4: Version bump + tests + commit — DONE 2026-05-29

#### Tasks

- [x] 4.1 `version.txt` → `1.5.1`.
- [x] 4.2 `bash tests/run-all.sh` — 308 pass, 0 fail. Initial run found 6 failures in `test-PLAN-002-installer.sh` because `shell/` was missing from the sparse set (v1.0.x shell-function dispatch). Added `shell` to the sparse set; tests now green.
- [x] 4.3 Commit on `feat/v1.5.1-slim-install`.
- [x] 4.4 PLAN moved to `active/` at start (per convention); moves to `completed/` in Phase 5's final commit.

#### Validation

```bash
git log --oneline -1
cat version.txt          # 1.5.1
```

---

### Phase 5: Push, open PR, merge

#### Tasks

- [ ] 5.1 `git push -u origin feat/v1.5.1-slim-install`.
- [ ] 5.2 `gh pr create` — title `feat(v1.5.1): slim install via git sparse-checkout`; body summarises the size cut.
- [ ] 5.3 `gh pr merge --merge --delete-branch`.
- [ ] 5.4 `git checkout main && git pull --ff-only`.
- [ ] 5.5 Watch the docs deploy run (the only consumer of this branch's changes is `install.sh` content; docs build is unaffected, but a green deploy confirms no incidental regression).

#### Validation

```bash
gh pr view --json state --jq '.state'    # MERGED
git log --oneline -3
```

---

## Acceptance criteria

- [ ] Fresh install via `install.sh` produces a working tree under 500 KB.
- [ ] `noclickops`, `noclickops update`, and at least one inspect command (`noclickops info --help`) work on the slim install.
- [ ] Re-running `install.sh` on a pre-v1.5.1 full install slims it (with an `info` message explaining the change).
- [ ] `bash tests/run-all.sh` → 308 pass, 0 fail (no command logic changed).
- [ ] `version.txt` = `1.5.1`.
- [ ] PR opened, reviewed, merged; deploy still green.

---

## Implementation notes for whoever picks this up

- **Cone-mode is faster + safer than non-cone.** Non-cone sparse-checkout has known performance cliffs on big repos and supports gitignore-style patterns that overlap in surprising ways. Cone-mode is path-prefix-only, but that's exactly what we want (`bin lib templates shell`). Stick with `--cone`.
- **`git sparse-checkout set` is idempotent.** Running it twice with the same args is a no-op. Safe to call on every install.sh run if cleaner than the "is it enabled?" check — but the explicit gate is more readable for the slim-existing-install message.
- **`templates/welcome.txt` ships in the slim install.** `templates/` is already in the included set; this is by design (the installer prints it on first run). If the future moves `welcome.txt` somewhere else (`bin/`?), update the sparse set in lockstep.
- **`scripts/generate-docs.sh` does NOT ship to users.** Contributors who want to regenerate docs locally need a manual `git clone` of the repo (not `install.sh`). Document this in the relevant contributor section of `project-noclickops.md` if it isn't already.
- **The slim install still has `.git/` with the full history**, so contributors can convert their slim install to full with `git sparse-checkout disable` if they want, no re-clone needed.
- **The `welcome.txt` template printing** in `install.sh` (line 146) reads `$NOCLICKOPS_DIR/templates/welcome.txt`. That path is still present in a slim install. Good.

---

## Files to modify / create

**Modify:**

- `install.sh` — Phase 1 (sparse-checkout on clone), Phase 2 (slim on re-run).
- `bin/update.sh` — Phase 3.1 (header comment about sparse-awareness).
- `README.md` — Phase 3.2 (one paragraph after install one-liner).
- `version.txt` — `1.5.1`.

**Move:**

- `website/docs/ai-developer/plans/backlog/PLAN-106-slim-install.md` → `plans/active/` → `plans/completed/` per the convention.

**No new files.**
