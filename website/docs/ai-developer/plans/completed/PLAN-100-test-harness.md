# PLAN-100: Test harness — capture the smoke tests so CI can run them

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-28

**Goal**: Convert the ad-hoc smoke tests that gated PLAN-001 through PLAN-006 into a durable, repeatable test suite. Same tests; structured so a future GitHub Action can run them on every push to a PR.

**Last Updated**: 2026-05-28

**Investigations**: none — this is a retroactive cleanup PLAN, not a feature.

**Depends on**: PLAN-001 through PLAN-006 (the things under test).

**Priority**: High — without this, every PLAN ships with one-time test evidence that disappears the moment the conversation ends.

---

## Problem

PLAN-001 through PLAN-006 each shipped with smoke tests run via `Bash` tool calls inside the implementation conversation. Each PLAN's commit message recorded the results; the commands themselves were thrown away. That's fine for delivery confidence at the moment of writing, but it's worthless for regressions: when someone (a human or another AI session) changes `lib/metadata.sh::_extract_field` six months from now, nothing re-runs the create-pr quote-handling test that drove the original implementation.

We need every test those PLANs ran to be:

- **Captured** as a file in the repo, runnable by anyone.
- **Self-contained** — no real `az`, no real PRs, no live pipelines, no network. Fixtures are fake repos in `mktemp -d`.
- **CI-shaped** — a single command runs everything and exits non-zero on any failure.
- **Cheap** — no Bats, no Pester, no test-framework dependency. Plain bash + assertion helpers; portable to GitHub Actions Ubuntu runners which already have `git`, `bash`, `rsync`, `python3`.

---

## What it delivers

### `tests/` directory at the repo root

```text
tests/
├── README.md                       — how to run + conventions
├── _harness.sh                     — pass/fail/skip + assertion helpers
├── _fixtures.sh                    — make_target_repo / make_service /
│                                     scaffold_nextjs_sample / make_lovable_source
├── run-all.sh                      — discovers test-*.sh, runs each, totals
├── test-PLAN-001-foundation.sh
├── test-PLAN-002-installer.sh
├── test-PLAN-003-pr-and-merge.sh
├── test-PLAN-004-deploy.sh
├── test-PLAN-005-clean-sample.sh
├── test-PLAN-006-sync-lovable.sh
└── test-portability.sh             — cross-cutting grep guard
```

### `tests/_harness.sh` — assertion API

```bash
pass <name>
fail <name> [details]
skip <name> <reason>
assert_eq <expected> <actual> <name>
assert_contains <haystack> <needle> <name>
assert_not_contains <haystack> <needle> <name>
assert_file_exists <path> <name>
assert_file_absent <path> <name>
assert_exit_zero    <name> -- <cmd> [args...]
assert_exit_nonzero <name> -- <cmd> [args...]
summary    # prints totals; returns 1 if any failed
```

Each test file ends with `summary`; `run-all.sh` runs every file in a subshell so a failure in one doesn't poison the rest.

### Output

`run-all.sh` prints each test as it runs (`✓` / `✗` / `-`), then a final block:

```text
─────────────────────────────────────────
Total passed:  47
Total failed:  0
Total skipped: 1
```

Exits 0 if all green, 1 if anything failed. That's enough for a GitHub Action: `bash tests/run-all.sh`, check exit code.

### Coverage

| Test file | Scenarios captured |
| --- | --- |
| `test-PLAN-001-foundation.sh` | lister output, `--help` metadata, `update` fails fast on non-git install dir, `TARGET_REPO` resolves correctly, sourcing-guards prevent double-init |
| `test-PLAN-002-installer.sh` | Fresh install clones from a local source; populates expected dirs; appends rc-file source line exactly once; re-run pulls (idempotent); function dispatch (`noclickops`, `noclickops update`, `noclickops bogus`) |
| `test-PLAN-003-pr-and-merge.sh` | `--help` works with embedded quotes; missing-arg errors; URL derivation across 5 formats; non-ADO URL rejected; "on main" guard fires pre-`az`; no hardcoded identity in code |
| `test-PLAN-004-deploy.sh` | Validation errors fire before any `az` call; "Available services:" listing on miss; pipeline name composition derived from `AZDO_REPO` |
| `test-PLAN-005-clean-sample.sh` | Safety guard refuses without marker; already-clean exit 0; intact sample cleans tracked + untracked correctly; platform scaffolding preserved |
| `test-PLAN-006-sync-lovable.sh` | Source signature checks; full end-to-end mirror against fake source + bare remote + service folder; excludes work; templates render; `health.json` has correct shape |
| `test-portability.sh` | `grep -E 'ExampleOrg\|FrontendPlatform\|JKL900X016' bin/ lib/ templates/` returns nothing |

### What this PLAN does NOT do

- **No GitHub Actions workflow** — the user explicitly deferred that. The tests are CI-shaped (single entry point, exit-code result, no auth/network) but no `.github/workflows/` is added in this PLAN.
- **No PowerShell tests** — every `.ps1` is marked "unverified on Mac" and waits on Windows verification. When Windows is in the loop, `tests/ps/` is the right next step.
- **No `az`/`gh`-touching tests** — those are integration tests requiring auth + real resources. Out of scope for unit CI. End-to-end deploy / PR creation stays a manual gate.
- **No mutation tests, fuzzing, performance** — too far for v1.

---

## Phases

1. `tests/README.md` + `tests/_harness.sh` + `tests/_fixtures.sh` + `tests/run-all.sh`.
2. 6 per-PLAN test files + 1 portability file.
3. Run `tests/run-all.sh` locally, fix any infrastructure issues that surface.

---

## Validation criteria

- `bash tests/run-all.sh` runs everything and exits 0.
- Every test that PLAN-001 through PLAN-006 ran ad-hoc has a counterpart in `tests/`.
- No test requires `az`, network, or anything beyond `git` + `bash` + `rsync` + `python3`.
- Each test file is independently runnable (`bash tests/test-PLAN-003-pr-and-merge.sh`).
- Failure output identifies which test failed and why, in one line per failure.

---

## Completion notes (2026-05-28)

All three phases shipped on `feature/ai-developer-bootstrap`.

**Final test counts** (from `bash tests/run-all.sh`):

| File | Tests | Status |
| --- | --- | --- |
| `test-PLAN-001-foundation.sh` | 15 | ✅ |
| `test-PLAN-002-installer.sh` | 18 | ✅ |
| `test-PLAN-003-pr-and-merge.sh` | 18 | ✅ |
| `test-PLAN-004-deploy.sh` | 17 | ✅ |
| `test-PLAN-005-clean-sample.sh` | 28 | ✅ |
| `test-PLAN-006-sync-lovable.sh` | 37 | ✅ |
| `test-portability.sh` | 1 | ✅ |
| **TOTAL** | **134** | **0 failed, 0 skipped** |

**Implementation design choices**:

- **Plain bash, no Bats**. Each test file sources `_harness.sh` and uses `pass`/`fail`/`assert_*` helpers. Zero framework dependency keeps CI setup to "just install git, bash, rsync, python3" — already default on Ubuntu / macOS / Git Bash.
- **`set -uo pipefail`** but **NOT `-e`** in test files. We want assertions to keep running after a failure so the report shows everything broken, not just the first thing.
- **Runner ↔ test communication via stdout marker**: `summary` prints `##NCO_TEST_COUNTS p=N f=N s=N##` which `run-all.sh` greps from a `tee`-captured copy. Cleaner than re-running each file or fragile cross-subshell env vars.
- **Fixtures in `mktemp -d`** with explicit cleanup at end of each test. Every test creates its own world; nothing persists between runs; no test depends on another's state.
- **GitHub-URL rejection test** uses GitHub-style URLs in the test data (intentional — they're inputs being rejected). The portability grep correctly ignores `tests/` because real tenant names are legitimate test data there.

**Fix made during implementation**: first version of `run-all.sh` ran each test file twice (once for visible output, again to parse counts) because subshell exit codes don't carry sub-shell vars. Replaced with `bash $f 2>&1 | tee $tmp` + grep on the marker line. Single execution; both visible and parseable.

**What's intentionally NOT here**:

- **No `.github/workflows/*.yml`** — user explicitly deferred. The CI integration is `bash tests/run-all.sh` (one line); when ready, a workflow that runs that on push and PR is the whole change.
- **No PowerShell tests** — every `.ps1` is "unverified on Mac". Native-Windows verification first; then `tests/ps/test-PLAN-*.ps1` mirroring this structure.
- **No az/gh/pipeline integration tests** — those need real auth and resources. Manual integration testing remains the gate for those code paths.
