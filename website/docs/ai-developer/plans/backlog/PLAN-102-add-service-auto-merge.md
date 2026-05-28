# PLAN-102: `add-service` auto-merges the scaffold PR

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Backlog

**Goal**: Make `noclickops add-service <name>` complete the full scaffold-to-main flow in one command — trigger the pipeline, wait for it to succeed, and merge the resulting PR — instead of fire-and-forget. Saves one manual `noclickops merge-pr <id>` step and closes the loop.

**Last Updated**: 2026-05-28

**Investigations**: none — direct response to user feedback after the first real `noclickops add-service` run on 2026-05-28.

**Depends on**: PLAN-007 (`add-service`), PLAN-003 (`merge-pr` logic).

**Priority**: Medium — polish over an existing flow that works.

---

## Problem

PLAN-007a (post-PLAN-007) **removed** `--watch` from `add-service` because the pipeline was thought to take ~1 hour, making a watch loop hostile. The first real run (`28498` in `JKL900X016-NerdMeet`, 2026-05-28) actually completed in **37 seconds** — and observed runs from other repos in the same project (e.g. `28453` `DEF900099-oktatest-add-service`) follow the same pattern. The "1 hour" figure that drove PLAN-007a's design was wrong.

With a fast pipeline:

1. **Watching becomes viable** — under a minute, a developer wouldn't even tab away.
2. **Auto-merging becomes natural** — the next manual step after the PR opens is always `noclickops merge-pr <id>` on the scaffold PR; doing it automatically eliminates a context switch.

The current flow makes the developer:

```text
noclickops add-service postgres ...     # returns immediately
[wait ~1 min]
noclickops status <run-id>              # see it's done
[look up the PR id on ADO web]
noclickops merge-pr <pr-id>             # squash + sync + cleanup
```

After this PLAN ships:

```text
noclickops add-service postgres ...     # one command, returns when scaffold is on main
```

---

## What it delivers

### `bin/add-service.{sh,ps1}` — new default + opt-out flag

```text
noclickops add-service <service-name> [--persistent-storage] [--no-public-endpoint] [--no-merge]
```

| Flag | Effect |
| --- | --- |
| default | Trigger pipeline → watch until completed → find the scaffold PR → squash-complete it → sync local main → exit |
| `--no-merge` | Trigger pipeline → print run id + URL → return (PLAN-007a's fire-and-forget) |

### Watch + merge flow

1. Trigger pipeline (existing logic; unchanged).
2. **Watch loop** — poll `az pipelines runs show --query status` every 5s. Timeout 10 min (typical runs are ~1 min; budget covers package-install retries and similar slowdowns).
3. On `Status = completed, Result = succeeded`:
   1. **Locate the scaffold PR** by source branch:

      ```bash
      pr_id=$(az repos pr list --status active \
        --query "[?sourceRefName=='refs/heads/add-service-${service}'] | [0].pullRequestId" \
        -o tsv)
      ```

      The branch name is deterministic — the target repo's add-service pipeline yaml hard-codes `branchName: "add-service-${{ parameters.serviceName }}"`.
   2. **Merge** via the same logic as `bin/merge-pr.sh` — `az repos pr update --status completed --squash true --delete-source-branch true`, poll for `completed`, switch local to `main`, `git fetch --prune`, `git merge --ff-only origin/main`, delete the local feature branch if any.
4. On failure paths (see below): print clear next steps and exit non-zero.

### Failure handling

| Cause | Behaviour |
| --- | --- |
| Pipeline fails (`Result ≠ succeeded`) | Exit 1 with the run URL. **Do not** attempt merge. |
| Pipeline times out at 10 min | Exit 1 with run URL + "use `noclickops status` later" hint. **Do not** attempt merge. |
| Pipeline succeeded but no PR found (Copier had nothing to commit) | Warning + exit 0. Informational, not an error. |
| Merge step fails (branch policies, conflict, etc.) | Exit 1 with the PR URL. The pipeline's scaffold remains on its branch for manual handling. |
| User Ctrl-C during watch | Pipeline keeps running server-side. No merge happens. User can re-attach later via `noclickops status <run-id>`. |

### What this PLAN does NOT do

- **No auto-deploy.** After the scaffold lands, the new service still has placeholder content (Next.js sample). Auto-deploying a placeholder service is wrong by default.
- **No auto-`clean-sample`.** Some developers keep the Next.js sample (as a demo / template). Cleaning it stays an explicit step.
- **No `--watch` resurrection as a separate flag.** Watch + merge is the default — they're inseparable. `--no-merge` covers the "don't wait, don't merge" case.

---

## Phases

1. **Code** — update `bin/add-service.{sh,ps1}`:
   - Re-add the watch loop (lift from `deploy`'s; use 10 min cap, 5s poll).
   - Add `--no-merge` flag.
   - Add PR-lookup logic.
   - Add merge step (refactor `merge-pr.sh`'s squash-complete into a helper in `lib/azdo.sh` so we don't duplicate it).
2. **Tests** — update `tests/test-PLAN-007a-status.sh` (or move add-service tests to their own file):
   - The current assertions that `--watch` is rejected need to go (or be replaced; we're adding `--no-merge` instead of resurrecting `--watch`).
   - New assertions: `--no-merge` accepted; default flow exits non-zero on pipeline failure; default flow doesn't merge if pipeline failed.
3. **Refactor** — pull the squash-merge logic out of `bin/merge-pr.sh` into a `lib/azdo.sh::squash_complete_pr` helper. Both `merge-pr.sh` and `add-service.sh` call it.
4. **Docs** — update `bin/add-service.sh`'s metadata (`SCRIPT_DESCRIPTION`, `SCRIPT_USAGE`) and the next-steps message. Update PLAN-007a's completion notes to point readers here.
5. **Version** — bump `version.txt` to **1.3.0** (semver minor: new default behavior; `--no-merge` provides the escape hatch).

---

## Validation criteria

- `noclickops add-service test-fixture-svc` against a real ADO test environment:
  - Triggers the pipeline.
  - Watches until completion.
  - Finds and merges the scaffold PR.
  - Leaves local `main` synced and the `add-service-test-fixture-svc` branch deleted both remotely and locally.
- `noclickops add-service test-fixture-svc --no-merge`:
  - Triggers and returns immediately (PLAN-007a behavior).
- Simulate pipeline failure (mock `az` in tests, or test against a known-failing fixture pipeline):
  - Exit non-zero.
  - No merge attempted.
- Pre-merge-step error message includes the PR URL.
- `tests/run-all.sh` passes.
- Portability grep stays clean.
- README's "Service lifecycle" section reflects the new one-command flow.

---

## Implementation notes for whoever picks this up

- **Reusable squash-complete helper**: factor `bin/merge-pr.sh`'s lines 30-50 into `lib/azdo.sh::squash_complete_pr <pr-id>` so `add-service.sh` can call it without duplicating the `--squash true --delete-source-branch true` + poll-for-completion + local-main-sync logic. Keeps a single source of truth for "how do we merge an ADO PR".
- **Branch name derivation**: the add-service pipeline yaml in target repos uses `branchName: "add-service-${{ parameters.serviceName }}"`. If a target repo customises this, the PR-lookup-by-branch breaks. Future-proof by also accepting a `--pr-id` flag for manual override.
- **Timeout choice**: 10 minutes is generous; observed runs are ~1 min. If a future SP/Copier slowdown bumps typical times into the 2-3 min range, this still works. If it ever runs 8+ min routinely, revisit; the watch UX gets unpleasant past 5 min.
- **Watching from a `curl … | bash` install context (no shell function)**: works fine — the dispatcher (v1.1.0) exec's `add-service.sh` which handles its own loop. No special shell-integration needed.
