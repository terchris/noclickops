# tests/

Test suite for noclickops. Plain bash; zero framework dependency; runnable on any developer machine that has `git`, `bash`, `rsync`, and `python3` (all default on Ubuntu / macOS / Git Bash for Windows).

## Run everything

```bash
bash tests/run-all.sh
```

Exit code: 0 if all tests pass, 1 otherwise. That's the contract a future GitHub Action will use.

## Run a single PLAN's tests

```bash
bash tests/test-PLAN-003-pr-and-merge.sh
```

Each `test-*.sh` is self-contained and produces its own pass/fail/skip summary.

## What's tested

Each `test-PLAN-NNN-*.sh` captures the smoke tests that gated the corresponding PLAN's shipping commit. The original commit messages reference the test counts; this directory makes those tests permanent and re-runnable.

| File | Covers |
| --- | --- |
| `test-PLAN-001-foundation.sh` | `lib/` sourcing-guards, `TARGET_REPO` resolution, `noclickops` + `update` lister + `--help` shape |
| `test-PLAN-002-installer.sh` | `install.sh` idempotent clone/pull, rc-file source-line dedup, function dispatch |
| `test-PLAN-003-pr-and-merge.sh` | `lib/azdo.sh` URL derivation across 5 URL forms, "on main" guard, metadata quote handling |
| `test-PLAN-004-deploy.sh` | `deploy` validation pre-`az`, "Available services:" listing, pipeline-name composition |
| `test-PLAN-005-clean-sample.sh` | Safety-marker guard, tracked vs untracked dispatch, platform scaffolding preserved |
| `test-PLAN-006-sync-lovable.sh` | End-to-end Lovable → service mirror, template rendering, `health.json` shape |
| `test-portability.sh` | Cross-cutting grep guard: no hardcoded tenant identity in `bin/`, `lib/`, `templates/` |

## What's NOT tested here

These belong in **manual integration tests**, not in this suite:

- Real `az` calls (PR creation, pipeline triggering, container logs/shell). Auth + real resources required.
- PowerShell scripts. Each `.ps1` is marked "unverified on Mac" — Windows verification is the gate.

## How to add a test

1. Open the relevant `test-PLAN-NNN-*.sh`.
2. Add a new block:

   ```bash
   echo "── <PLAN-name>: <scenario> ──"
   out=$(...)
   assert_contains "$out" "expected substring" "<test name>"
   ```

3. Run the file directly; the new line shows up in the output.
4. New PLAN? Create `tests/test-PLAN-NNN-<slug>.sh` from the harness skeleton; the runner discovers it automatically.

## Harness API

See `_harness.sh` for the full assertion API. Helpers:

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
summary    # call at end of each test file
```

Fixtures (see `_fixtures.sh`):

```bash
make_target_repo [origin-url]       # → path to fake ADO-shaped target repo
make_service <repo> <name>          # → path to scaffolded services/<name>/
scaffold_nextjs_sample <svc-dir>    # → adds the Next.js Copier sample
make_lovable_source                 # → path to fake Lovable source with bare remote
```
