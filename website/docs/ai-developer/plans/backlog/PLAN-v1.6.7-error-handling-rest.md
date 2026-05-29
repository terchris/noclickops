# PLAN-v1.6.7 — error handling for the rest of the commands

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Backlog

**Goal**: Extend the v1.6.6 failure-handling pattern (fetch the actual reason + give an actionable next step, not "failed + URL") to the rest of the commands that currently emit cryptic ADO errors: `merge-pr` / `add-service`'s PR-merge step, `read_iac_variables` REST failures, `create-pr` errors, and `update`'s git-pull conflict.

**Last Updated**: 2026-05-29

**Prerequisites**: [PLAN-v1.6.6-ux-and-error-handling](../completed/PLAN-v1.6.6-ux-and-error-handling.md) ships `report_pipeline_failure` + the action-pattern table format. This plan reuses both.

**Branch**: standalone — `feat/v1.6.7-error-handling-rest`. Single PR, version bump 1.6.6 → 1.6.7.

---

## What changes

### 1. `report_pr_merge_failure <project> <pr-id>`

When `merge_pr_in_project` (v2) or `squash_complete_pr` (v1) fails to mark a PR completed, fetch the PR + its branch policies and tell the user exactly which policy blocked them. Examples of common blockers in ADO:

- Required reviewers haven't approved
- Required build hasn't run / passed
- Linked work items missing
- Auto-complete waiting on something
- PR is in draft mode

Output format (matches PLAN-v1.6.6 `report_pipeline_failure`):

```
✗ FAILED to merge PR #4839 in TCH900001-mrkmedlem (FrontendPlatform)

  Reason:  Required policy "Build validation" hasn't completed.
           Last run: pending (queued 5 min ago).

  Action:  → Wait for the build to finish, then re-run:
               noclickops merge-pr 4839

  PR URL:  https://dev.azure.com/RedCrossNorway/FrontendPlatform/_git/TCH900001-mrkmedlem/pullrequest/4839
```

Helper signature:

```bash
report_pr_merge_failure <project> <pr-id>
  # 1. GET /_apis/policy/evaluations?artifactId=... to find the PR's policies + their state
  # 2. Identify which policy is NOT 'approved' yet
  # 3. Pattern-match against the policy-action table
  # 4. Print the formatted block
```

Initial policy-action table:

| Policy type | Status: not approved | Action |
|---|---|---|
| Build validation | pending | Wait for the build to finish, then re-run merge-pr |
| Required reviewers | waiting | Ping the listed reviewers; they need to approve |
| Linked work items | violation | Link a work item to the PR (web UI) |
| Comments | violation | Resolve all comments on the PR |
| Auto-complete | n/a | Already set; will complete when blockers clear |
| _(no match)_ | | See PR in web UI for details |

Used by both:
- `merge_pr_in_project` in `lib/service-v2.sh` (v2; called by `add-service`)
- `squash_complete_pr` in `lib/azdo.sh` (v1; called by `merge-pr` and the v1 surface)

### 2. `report_rest_failure <verb> <url> <http-status> <body>`

When `_nco_ado_rest_get` (or any wrapped REST call) returns a non-2xx, decode the status + body and explain. Most common cases for `read_iac_variables`:

| Status | Body signature | Action |
|---|---|---|
| 401 | `TF400813` (invalid auth) | Refresh az login: `az logout && az login` |
| 403 | `TF401019` (no read access on repo) | You don't have read access to `IaC/platform-infrastructure`. Ask the admin for "Reader" on that repo. |
| 404 | item not found at path | Variables file doesn't exist at the expected path. Has the IaC PR-B for `<svc>` been merged? Check: `noclickops status` for recent `<repo>-infra-add-service` runs. |
| 5xx | transient | ADO is having a moment. Retry in ~30s. |
| _(other)_ | | Network or unknown error. Check connectivity. |

Output format:

```
✗ FAILED: GET https://dev.azure.com/.../variables/common.yaml (HTTP 404)

  Reason:  Variables file doesn't exist at the expected IaC path.

  Action:  → Has the IaC PR-B for 'smk1' been merged in platform-infrastructure?
               Check: noclickops status | grep infra-add-service
```

`read_iac_variables` (and any other caller of `_nco_ado_rest_get`) replaces the bare `die "failed to GET ..."` with a call to `report_rest_failure` + exit.

### 3. `create-pr` error mapping

`az repos pr create` failures, mapped to friendlier output:

| az error | Action |
|---|---|
| `TF401179: An active pull request for the source and target branch already exists` | A PR for this branch already exists. Use `noclickops merge-pr <existing-id>` instead. (Lookup the id, print it.) |
| `TF401028: The reference 'refs/heads/<branch>' does not exist` | The branch isn't on the remote. Run: `git push -u origin <branch>` first. (Or noclickops should push automatically — investigate.) |
| `Source branch and target branch are the same` | You're on main. Create a feature branch first: `git checkout -b feature/<name>`. |
| `Permission denied` | You don't have permission to create PRs in this repo. Check ADO permissions. |

Output: same formatted block. Replaces the current raw az error.

### 4. `update` git-pull conflict

`noclickops update` runs `git pull --ff-only` in `~/.noclickops`. If the install dir has diverged (uncommitted changes, fork commits, etc.), the pull fails with `fatal: Not possible to fast-forward, aborting.` — currently dies with a vague "resolve manually" message.

Better output:

```
✗ FAILED: noclickops update — local install has diverged from origin/main

  Reason:  ~/.noclickops has 2 commits not on origin/main, OR uncommitted changes.

  Action:  Pick ONE:
           a) If you have no local edits worth keeping (most likely — this dir is install-only):
                git -C ~/.noclickops fetch origin && git -C ~/.noclickops reset --hard origin/main

           b) Wipe + reinstall (always safe):
                rm -rf ~/.noclickops && curl -fsSL https://raw.githubusercontent.com/terchris/noclickops/main/install.sh | bash

           c) If you DO have edits and want to keep them:
                cd ~/.noclickops && git status   # inspect, decide manually
```

`bin/update.sh` checks `git status` + `git rev-list` to detect WHICH divergence pattern applies, then prints the targeted message.

---

## Phase 1: `report_pr_merge_failure` helper

### Tasks

- [ ] 1.1 Add `report_pr_merge_failure <project> <pr-id>` to `lib/service-v2.sh`. Calls `_nco_ado_rest_get` for `/_apis/policy/evaluations?artifactId=...`.
- [ ] 1.2 Action table (initial 5 entries per the table above). Same data-structure format as PLAN-v1.6.6's `report_pipeline_failure`.
- [ ] 1.3 Update `merge_pr_in_project` (v2): on `pr update` failure, call `report_pr_merge_failure` then return 1.
- [ ] 1.4 Update `squash_complete_pr` (v1 in `lib/azdo.sh`): same treatment. Source `lib/service-v2.sh` for the helper (same source pattern that v1.6.4 introduced).
- [ ] 1.5 Tests: stub the policy-evaluations REST response; assert the helper formats each known policy type correctly.

### Validation

`bash tests/run-all.sh` green. Manual: create a PR with a deliberately failing build policy, run merge-pr — expect the formatted block.

User confirms phase is complete.

---

## Phase 2: `report_rest_failure` helper

### Tasks

- [ ] 2.1 Add `report_rest_failure <verb> <url> <http-status> [<body>]` to `lib/service-v2.sh`.
- [ ] 2.2 Status-action table (initial 5 entries).
- [ ] 2.3 Update `_nco_ado_rest_get` to capture HTTP status + body on failure, return them as a structured error.
- [ ] 2.4 Update `read_iac_variables`: on REST failure, call `report_rest_failure` then `die`. Similar for any other callers.
- [ ] 2.5 Tests: stub REST responses with 401 / 404 / 5xx; assert formatted output for each.

### Validation

`bash tests/run-all.sh` green. Manual: deliberately invalidate the az token, run `info` — expect the 401 hint.

User confirms phase is complete.

---

## Phase 3: `create-pr` error mapping

### Tasks

- [ ] 3.1 In `bin/create-pr.sh`, wrap the `az repos pr create` call: capture stderr, pattern-match against the error table, print the formatted block + exit 1.
- [ ] 3.2 For the "PR already exists" case: also do a `az repos pr list` to find the existing PR id and include it in the suggestion.
- [ ] 3.3 Tests: stub az to return each known error; assert formatted output.

### Validation

`bash tests/run-all.sh` green. Manual: try create-pr twice with the same branch — expect "PR already exists at #XXXX, use `merge-pr <id>`".

User confirms phase is complete.

---

## Phase 4: `update` git-pull conflict diagnostics

### Tasks

- [ ] 4.1 In `bin/update.sh`, after a `git pull --ff-only` failure: detect divergence pattern (uncommitted changes vs fork commits vs both) using `git status --porcelain` + `git rev-list HEAD..origin/main` + `git rev-list origin/main..HEAD`.
- [ ] 4.2 Print the targeted message (matching the diagnosis) with the specific recovery commands.
- [ ] 4.3 Tests: simulate each divergence pattern in a temp repo; assert the right message prints.

### Validation

`bash tests/run-all.sh` green. Manual: create a divergent install state and run `noclickops update` — expect the targeted recovery commands.

User confirms phase is complete.

---

## Phase 5: Docs + version bump

### Tasks

- [ ] 5.1 Update `website/docs/contributors/lib-service-v2.md`: add `report_pr_merge_failure` + `report_rest_failure` to the Public API table.
- [ ] 5.2 Bump `version.txt` → `1.6.7`.

---

## Acceptance Criteria

- [ ] `merge-pr` and `add-service` (via merge_pr_in_project) print the formatted PR-failure block when a policy blocks the merge
- [ ] `read_iac_variables` HTTP errors print the formatted REST-failure block (at minimum for 401 / 404 / 5xx)
- [ ] `create-pr` "PR already exists" suggests the existing PR id + merge-pr command
- [ ] `update` git-pull conflict prints the targeted recovery commands matching the divergence pattern
- [ ] `tests/run-all.sh` green
- [ ] `version.txt` shows `1.6.7`

## Files to Modify

- `lib/service-v2.sh` (add `report_pr_merge_failure`, `report_rest_failure`)
- `lib/azdo.sh` (update `squash_complete_pr` to source lib/service-v2.sh + call the helper)
- `bin/create-pr.sh` (wrap az error)
- `bin/update.sh` (divergence diagnostics)
- `tests/test-PLAN-A-service-discovery.sh` (lib-level helper tests)
- `tests/test-PLAN-F-add-service.sh` (PR-merge-failure path)
- `tests/test-PLAN-008-info.sh` (REST-failure path via `read_iac_variables`, if still in tree)
- New: `tests/test-PLAN-003-create-pr.sh` or extend existing — for create-pr error mapping
- New: `tests/test-PLAN-101-update.sh` or extend — for update divergence
- `website/docs/contributors/lib-service-v2.md`
- `version.txt`

## Implementation Notes

### Reuse PLAN-v1.6.6's action-table format

Whatever data structure PLAN-v1.6.6 settles on for the pipeline-failure action table, reuse it for the three new tables. Avoid 4 different formats.

### Out of scope for v1.6.7

- `status` showing inline step-failure info when querying a specific run (could use `report_pipeline_failure` but it's lower priority — file as v1.6.8 if needed)
- `sync-lovable` error handling (rsync errors are usually clear enough; revisit if real users complain)
- `info` / `logs` / `shell` discover_containerapp failures (the current "set SVC_APP_NAME_OVERRIDE" message is already good; only the underlying read_iac_variables REST failure case improves here)
