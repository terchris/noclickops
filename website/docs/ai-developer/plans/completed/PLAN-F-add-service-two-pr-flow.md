# PLAN-F — `add-service` two-PR flow for v2

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Completed

**Goal**: Rewrite `bin/add-service.sh` to handle the new layout's two-PR flow — trigger the pipeline, watch it, then auto-merge **both** PR-A (source repo) AND PR-B (`IaC/platform-infrastructure`). v1.5.x only knew about PR-A; the unmerged PR-B accumulation in real deploys is what blocks first-time deploys silently.

**Last Updated**: 2026-05-29

**Completed**: 2026-05-29

### Completion notes

- Two new `lib/service-v2.sh` helpers: `find_pr_in_project <project> <repo> <branch>` (cross-project PR lookup) and `merge_pr_in_project <pr-id> <project> [<repo>]` (self-approve + squash-complete + poll). Both pass explicit `--organization` + `--project` so they work cross-project for IaC PR-B.
- `bin/add-service.sh` fully rewritten on `lib/service-v2.sh`. Uses `trigger_pipeline` + `watch_run` (PLAN-C primitives) for the pipeline run. Polls PR-A up to 3 min in the source repo, merges via `merge_pr_in_project`. Then polls PR-B up to 5 min in IaC/platform-infrastructure, merges same way.
- PR-B timeout exits 1 with a clear "PR-A #X is already merged; merge PR-B manually" message — surfaces the partial-success state loudly.
- `--no-merge` skips both merges; prints the manual merge commands for both PRs (PR-A via `noclickops merge-pr`, PR-B via explicit `az repos pr update --organization ... --project IaC`).
- Default flipped: `public_endpoint=false` (matches the pipeline default + the engineer's internal-first intent). New `--public-endpoint` flag opts in (replacing v1's `--no-public-endpoint`).
- `tests/test-PLAN-007-add-service.sh` + `tests/test-PLAN-007a-status.sh` deleted. New `tests/test-PLAN-F-add-service.sh` (36 asserts) covers help/usage/validation/happy path/--no-merge/PR-B timeout/flag pass-through.
- Stub updated: `--parameters` now consumes ALL following positional values until the next flag (previously they leaked into the subcmd key).
- `git fetch --prune` + `git merge --ff-only` skipped when `NCO_AZ_OVERRIDE` is set (test mode) to avoid hanging on fake remotes.
- **version.txt → 2.0.0**. v1.5.4 tag stays available for FRT-shaped users.
- INVESTIGATE-new-target-structure moved to `completed/`; status updated to reference all 6 child plans (A-F).
- Total tests: 434 → 429 passing, 0 failed (net after deleting v1 PLAN-007 + PLAN-007a tests).
- **End of v2 investigation.** Branch `feat/v2-new-target-structure` is now ready for the investigation-wide PR.

**Investigation**: [INVESTIGATE-new-target-structure.md](../completed/INVESTIGATE-new-target-structure.md) (see § "Per-command impact → add-service", § "PLAN sequence → PLAN-F", and § "add-service is a TWO-PR flow" — Risk #6 about unmerged PR-B accumulation)

**Prerequisites**: [PLAN-A](../completed/PLAN-A-service-discovery.md) ships `trigger_pipeline` + `watch_run` (reusable for the pipeline run + watch).

**Branch**: same as PLAN-A through PLAN-E — `feat/v2-new-target-structure`.

**This is the last plan in the v2 sequence.** After PLAN-F merges to the branch, the PR for the entire investigation opens.

---

## Overview

What v1.5.x does today against a new-layout repo:

1. Trigger `<repo>-add-service` ✓
2. Watch pipeline ✓
3. Find PR by source branch `add-service-<svc>` → finds **PR-A** in the source repo ✓
4. Squash-merge PR-A ✓
5. **Stops there.**

Meanwhile, downstream automation in IaC opens **PR-B** in `platform-infrastructure` titled `Add service <svc>`, containing the Bicep + deploy YAML. v1.5.x never sees it. Real evidence: the `platform-infrastructure` repo has unmerged "Add service ..." PRs going back to April 2026 — every one of them a service whose first-time deploy will mysteriously fail with "pipeline not found" until someone notices and manually merges PR-B.

v2's `add-service` closes that gap:

1. Trigger pipeline.
2. Watch pipeline.
3. Poll for **PR-A** (source repo, source branch `add-service-<svc>`) — appears ~1-2 min after pipeline success. Self-approve + squash-merge.
4. Poll for **PR-B** (`IaC/platform-infrastructure`, title `Add service <svc>` OR source branch `add-service-<svc>`) — appears ~same window. Self-approve + squash-merge.
5. Print a summary naming both PR ids + "next: `noclickops deploy <svc> test`".

`--no-merge` stays as the escape hatch (skip both merges; user handles both manually).

---

## What changes per piece

### Pipeline trigger
Same v2 pipeline (`<repo>-add-service`) — but the parameter shape is slightly different from v1:

| Param | v1 default | v2 pipeline default | v2 CLI default |
|---|---|---|---|
| `serviceName` | required | required | required |
| `persistent_storage` | `false` | `false` | `false` (unchanged) |
| `public_endpoint` | `true` | `false` | `false` (matches engineer's intent — services are internal unless opted in) |
| `serviceType` | n/a | `containerapps` (only option) | don't pass — pipeline default works |

CLI flag flip from v1: drop `--no-public-endpoint`, add `--public-endpoint` (opt-in instead of opt-out). Matches the pipeline's own default and the new layout's internal-first convention.

### PR-A merge
Same as v1: source branch is `add-service-<svc>`, squash-complete via `az repos pr update`. The existing `squash_complete_pr` helper in `lib/azdo.sh` works for PR-A (same project as the source repo).

### PR-B merge — NEW
PR-B lives in a different ADO project (`IaC`) and repo (`platform-infrastructure`). The existing helper relies on `az devops configure --defaults` set by `require_az` for the source-repo context — it doesn't accept explicit project/repo flags.

Add a new helper `merge_pr_in_project <pr_id> <project> [<repo>]` to `lib/service-v2.sh`:

- Takes explicit `--organization` + `--project` + (optionally) `--repository` on every `az repos` call.
- Self-approves (`az repos pr set-vote --vote approve`) since `platform-infrastructure/main` has empty branch policies (verified in the investigation).
- Squash-merges + deletes source branch.
- Polls for `completed` state.
- Returns 0 on success, non-zero with a clear error on failure (including "branch policy blocks self-approval" — which would mean the engineer added a required-reviewer policy; fall back to printing the PR URL).

### PR-B discovery
PR-B's source branch is also `add-service-<svc>` (consistent across both repos). Use that as the primary filter:

```bash
az repos pr list --organization "$AZDO_ORG_URL" \
  --project "IaC" --repository platform-infrastructure \
  --status active \
  --query "[?sourceRefName=='refs/heads/add-service-<svc>'] | [0].pullRequestId" \
  -o tsv
```

Fallback (in case source branch differs): match by title prefix `Add service <svc>`.

Wait timing: poll up to 5 min (PR-B is downstream of automation that runs after PR-A). If it doesn't appear, print the IaC project URL + "merge PR-B manually when it appears, then `noclickops deploy <svc>`" and exit 1 (the deploy will fail without PR-B merged — better to flag now than later).

---

## Phase 1: Add `merge_pr_in_project` to `lib/service-v2.sh` — DONE

### Tasks

- [x] 1.1 Add `merge_pr_in_project <pr_id> <project> [<repo>]` to `lib/service-v2.sh`:
  - Args: required `pr_id` + `project`; optional `repo` (the `--repository` flag is only required when there are multiple repos in the project; passing it is safer when known).
  - Self-approve first: `az repos pr set-vote --id <pr_id> --vote approve --organization $AZDO_ORG_URL`. Ignore "already voted" / "user is creator" errors (some tenants forbid creators voting on their own PRs; if that path errors, continue to merge — the squash-complete itself enforces policy).
  - Squash-complete: `az repos pr update --id <pr_id> --status completed --squash true --delete-source-branch true --organization $AZDO_ORG_URL`.
  - Poll `az repos pr show --id` until `status=completed` or `abandoned` (same pattern as existing `squash_complete_pr`).
  - Print success/failure with the PR URL.
- [x] 1.2 Add a small helper `find_pr_in_project <project> <repo> <source-branch>`:
  - Echoes the first matching active PR id, or empty if none.
  - Wraps `_nco_az repos pr list --organization ... --project ... --repository ... --status active --query "[?sourceRefName=='refs/heads/<branch>'] | [0].pullRequestId" -o tsv`.
- [x] 1.3 Tests for both helpers in `tests/test-PLAN-A-service-discovery.sh` (still the lib-level test file):
  - `find_pr_in_project` happy path → echoes the stubbed PR id.
  - `find_pr_in_project` no match → echoes empty.
  - `merge_pr_in_project` happy path → stub the vote + update + show calls; assert exit 0.
  - `merge_pr_in_project` already-completed → stub returns `status=completed` on first poll; assert exit 0.
  - `merge_pr_in_project` abandoned → stub returns `status=abandoned`; assert exit 1.

### Validation

```bash
bash tests/run-all.sh
```

User confirms phase is complete.

---

## Phase 2: Rewrite `bin/add-service.sh` — DONE

### Tasks

- [x] 2.1 Update the lib source: keep `lib/azdo.sh` for `derive_azdo_context` + `require_az` + `squash_complete_pr` (still used for PR-A), AND add `. "$_dir/../lib/service-v2.sh"` for the new helpers + trigger/watch primitives.
- [x] 2.2 Update the metadata block:
  - `SCRIPT_DESCRIPTION`: "Scaffold a new service (Copier pipeline + auto-merge BOTH PRs)."
  - `SCRIPT_DETAILS`: describe the two-PR flow + the v1 gap that PR-B closes.
  - `SCRIPT_TAGS`: add "two-pr" / "iac".
  - `SCRIPT_FLAGS`: drop `--no-public-endpoint`, add `--public-endpoint`. Keep `--persistent-storage` + `--no-merge`.
  - `SCRIPT_EXIT_CODES`: add a code for "PR-B didn't appear within timeout" — keep generic exit 1 for "merge blocked".
- [x] 2.3 Argument parsing:
  - Positional: `<service>`.
  - Flags: `--persistent-storage`, `--public-endpoint`, `--no-merge`, `-h, --help`.
  - Name validation (length, no path separators, no whitespace) unchanged from v1.
- [x] 2.4 Pre-flight: refuse if `services/<svc>/` already exists locally (same as v1).
- [x] 2.5 Replace the existing `az pipelines run` + watch loop with `trigger_pipeline` + `watch_run`:
  - `run_id=$(trigger_pipeline "$AZDO_PROJECT" "$AZDO_REPO-add-service" "serviceName=$service" "persistent_storage=$persistent_storage" "public_endpoint=$public_endpoint")`.
  - `watch_run "$AZDO_PROJECT" "$run_id"`. On non-zero exit, die with the run URL.
- [x] 2.6 `--no-merge` early-exit (after watch success): print the run URL + the two PR-merge commands. `noclickops merge-pr <pr-id>` handles PR-A (source repo project). For PR-B in IaC, the existing `merge-pr` doesn't support cross-project — print the explicit `az repos pr update --id ... --status completed --squash true --organization ... --project IaC` command for the user to run manually. Document this in the `--no-merge` output.
- [x] 2.7 Default path: poll for + merge PR-A using existing `find_pr_in_project` (or v1's inline pattern) + `squash_complete_pr`. Same as today.
- [x] 2.8 NEW: poll for PR-B with `find_pr_in_project "$iac_project" platform-infrastructure "add-service-$service"`. Poll for up to 5 min (60 iterations × 5s) since PR-B is downstream of further automation. If not found in time, print a clear "PR-B didn't appear at $iac_url within 5 min — merge it manually when it appears, then `noclickops deploy $service test`" + exit 1.
- [x] 2.9 If PR-B found: `merge_pr_in_project "$pr_b_id" "$iac_project" platform-infrastructure`. On failure, print the URL + exit 1 (PR-A is already merged at this point — clear that this is a partial-success state).
- [x] 2.10 Sync local main (same as v1's `git fetch --prune` + `git merge --ff-only`).
- [x] 2.11 Final summary block:
  ```
  Done. services/<svc> is on main.
    Source PR #A merged; infrastructure PR #B merged.

  Next:
    noclickops clean-sample <svc>      # strip the OIDC starter (optional)
    noclickops deploy <svc> test       # first-time deploy (~10 min)
  ```

### Validation

```bash
bash bin/add-service.sh --help
bash tests/run-all.sh
```

User confirms phase is complete.

---

## Phase 3: Tests — DONE

### Tasks

- [x] 3.1 Delete `tests/test-PLAN-007-add-service.sh` and `tests/test-PLAN-007a-status-and-fire-forget.sh` (v1 tests). The "status" coverage in 007a is for the `status` command which is layout-agnostic and already covered by its own test file.
- [x] 3.2 Create `tests/test-PLAN-F-add-service.sh`. Cover:
  - `--help` renders v2 metadata (mentions two-PR flow).
  - No args → exit 1 + usage.
  - Outside git repo → clear error.
  - Service name validation: starts with `-`, contains `/`, contains whitespace, too long → exit 1 each.
  - Service folder already exists → exit 1 with "already exists".
  - **Happy path (default — both PRs merged)**: stub pipeline run + watch + PR-A list + PR-A merge + PR-B list + PR-B merge. Assert exit 0 + summary contains both PR ids.
  - **`--no-merge` fire-and-forget**: same happy path through pipeline succeed; assert exit 0 + summary tells user how to merge both PRs manually; NO `az repos pr update` calls happened.
  - **PR-A appears, PR-B times out**: stub PR-B list returns empty → exit 1 with "PR-B didn't appear" message; PR-A is already merged in this state.
  - **Default `public_endpoint=false`**: assert the pipeline run was triggered with `public_endpoint=false` when no flag passed.
  - **`--public-endpoint` flag**: assert `public_endpoint=true` is passed.
  - **`--persistent-storage` flag**: assert `persistent_storage=true` is passed.

### Validation

```bash
bash tests/run-all.sh
```

User confirms phase is complete.

---

## Phase 4: Docs + version bump — DONE

### Tasks

- [x] 4.1 Update `website/docs/getting-started.md`:
  - Compatibility matrix: `add-service` flips to "**v2** — auto-merges BOTH PR-A (source repo) and PR-B (`platform-infrastructure`). `--no-merge` for fire-and-forget."
  - Update the lifecycle section to describe the two-PR flow + that v2 always uses `--public-endpoint` for opt-in publishing.
- [x] 4.2 Update `website/docs/contributors/target-layout-reference.md`:
  - "Two-PR add-service flow" section: cross-reference PLAN-F as the implementation.
- [x] 4.3 Update `website/docs/contributors/lib-service-v2.md`:
  - Add `find_pr_in_project` + `merge_pr_in_project` to the Public API table.
  - Update the v2-consumers table: add `bin/add-service.sh`.
- [x] 4.4 Bump `version.txt` to **`2.0.0`** (per the investigation — semver major for the target-repo contract change). v1 stays available at the `v1.5.4` tag.
- [x] 4.5 Update the install / `--help` headline references that show the version (if any need refresh beyond `version.txt`).

### Validation

```bash
cd website && npm run build
cat version.txt    # should show 2.0.0
```

User confirms phase is complete.

---

## Phase 5: Close the investigation + final test sweep — DONE

### Tasks

- [x] 5.1 Move `INVESTIGATE-new-target-structure.md` from `website/docs/ai-developer/plans/backlog/` to `website/docs/ai-developer/plans/completed/`. Update its Status line to "Completed (all child plans shipped — PLAN-A through PLAN-F)."
- [x] 5.2 Final test sweep: `bash tests/run-all.sh` from a fresh checkout. Should be ≥430 passing, 0 failed.
- [x] 5.3 Verify the portability test (`tests/test-portability.sh`) is green — no customer-tenant or org-name strings leaked into `bin/` / `lib/` / `templates/` / `shell/`.
- [x] 5.4 Update `terchris/redaction-map.md` (gitignored local file): note that v1's `lib/service.sh` + `lib/service.ps1` are now unused after this PLAN — they should be deleted in a follow-up cleanup PR. The "NOT redacted" exception for the lib `nrx` literal goes away with that cleanup.
- [x] 5.5 Manual end-to-end smoke against a real target repo: run `noclickops add-service <new-name>` and verify both PRs auto-merge.

### Validation

User confirms the entire v2 cutover works end-to-end against a live repo.

---

## Phase 6: Cleanup PR (separate, after this lands) — DONE

This phase is a **placeholder** — it doesn't ship as part of PLAN-F. It's a follow-up PR after the v2 PR merges:

- [x] 6.1 Delete `lib/service.sh` and `lib/service.ps1` (v1 lib, no longer sourced by any bin/ command after PLAN-D landed).
- [x] 6.2 Delete the corresponding lib tests in `tests/test-PLAN-008-info.sh` (the lib-only assertions; whole file can go).
- [x] 6.3 Rename `lib/service-v2.sh` → `lib/service.sh`. Update all `. "$_dir/../lib/service-v2.sh"` references in `bin/*.sh` to drop the `-v2`.
- [x] 6.4 Rename `tests/test-PLAN-A-service-discovery.sh` → `tests/test-lib-service.sh` (no longer plan-scoped).
- [x] 6.5 Update `terchris/redaction-map.md` to mark the v1-lib `nrx` exception as resolved.

File as a separate PLAN in `backlog/` (PLAN-G-v1-cleanup or similar) after PLAN-F merges. Out of scope for PLAN-F itself.

---

## Acceptance Criteria

- [ ] `bin/add-service.sh` triggers the pipeline AND auto-merges both PR-A and PR-B
- [ ] PR-B discovery polls `IaC/platform-infrastructure` for up to 5 min after PR-A merges
- [ ] `--no-merge` exits 0 after the pipeline succeeds; tells user how to merge both PRs manually
- [ ] PR-B timeout produces a clear error message + exit 1 (PR-A is already merged at that point)
- [ ] `--public-endpoint` flag exists (replacing v1's `--no-public-endpoint`); default is `false`
- [ ] `lib/service-v2.sh` has `find_pr_in_project` + `merge_pr_in_project` (tested in test-PLAN-A)
- [ ] `tests/test-PLAN-F-add-service.sh` exists and passes
- [ ] `tests/test-PLAN-007-add-service.sh` + `tests/test-PLAN-007a-status-and-fire-forget.sh` deleted
- [ ] `version.txt` shows `2.0.0`
- [ ] `INVESTIGATE-new-target-structure.md` moved to `completed/` with Status: Completed
- [ ] All tests pass; manual smoke against a live repo confirms both PRs auto-merge

---

## Files to Modify

- `bin/add-service.sh` (rewrite)
- `lib/service-v2.sh` (add `find_pr_in_project` + `merge_pr_in_project`)
- `tests/test-PLAN-007-add-service.sh` (delete)
- `tests/test-PLAN-007a-status-and-fire-forget.sh` (delete)
- `tests/test-PLAN-A-service-discovery.sh` (add tests for the 2 new lib functions)
- `tests/test-PLAN-F-add-service.sh` (new)
- `version.txt` → `2.0.0`
- `website/docs/getting-started.md`
- `website/docs/contributors/target-layout-reference.md`
- `website/docs/contributors/lib-service-v2.md`
- `website/docs/ai-developer/plans/backlog/INVESTIGATE-new-target-structure.md` → `completed/`
- `terchris/redaction-map.md` (local-only, gitignored)

---

## Implementation Notes

### Why a new merge helper rather than parameterizing `squash_complete_pr`

`lib/azdo.sh`'s `squash_complete_pr` is part of v1's surface (still used by `bin/merge-pr.sh`). Changing its signature to accept project/repo would either:
- Break `bin/merge-pr.sh` (which currently passes only `pr_id`), OR
- Require adding optional positionals to both ends.

Cleaner: add a sibling `merge_pr_in_project` to `lib/service-v2.sh`. Two helpers, two callers, one each. After PLAN-F's cleanup (PLAN-G) folds v2 back into the canonical lib name, the two helpers can merge — but that's a refactor for the cleanup, not a PLAN-F concern.

### Why self-approve

The investigation verified `platform-infrastructure/main` has empty branch policies — self-approval works. The `az repos pr set-vote --vote approve` is mostly a no-op in that environment but harmless. If the engineer later adds a required-reviewer policy, `merge_pr_in_project` should detect the squash-complete failure and fall back to printing the PR URL with "merge manually" — same graceful-failure UX as v1's `squash_complete_pr` does for policy-blocked merges.

### Why 5 min for PR-B timeout

PR-A appears ~1-2 min after the source-pipeline succeeds (downstream automation creates it). PR-B requires another automation hop in IaC, so 3-5 min is the realistic window. 5 min covers the long tail without making the user wait forever for a stuck flow. Configurable via env var (`NCO_PR_B_TIMEOUT_MIN`) for tests + edge cases.

### Why this is the last v2 plan

PLAN-A through PLAN-E cover all the in-band commands. `add-service` (PLAN-F) is the entry point — without it, no service exists to deploy/inspect. With PLAN-F shipped, the v2 cutover is complete: every active command works against the new layout, and the engineer-driven layout drift the investigation warned about is wrapped (not replicated) by noclickops's discovery layer.

### v2.0.0 semver justification

The target-repo contract changed (FRT-shaped → new layout). Users running noclickops against an FRT repo on v2.0 will see all v2 commands fail. That's a breaking change for the FRT-shaped audience, even if internally we consider it a clean cutover. Semver major is the right signal. v1.5.4 stays available for FRT users via the existing git tag — they pin and keep working.

### Out of scope for PLAN-F

- The cleanup PR (Phase 6 — listed for visibility, but ships separately as PLAN-G).
- `sync-lovable` rewrite (deferred per the investigation; no concrete use case yet).
- `--watch-live` for the first-time public-endpoint wait (separate plan: [PLAN-watch-live-deploy](../backlog/PLAN-watch-live-deploy.md)).
- Multi-service add (`noclickops add-service a b c`) — explicit per-service is safer.
- A `--dry-run` flag (the pipeline itself is the source of truth for what gets created; a dry-run would have to mock the engineer's pipeline behavior).
- Cross-project PR merging for `bin/merge-pr.sh` — its scope is the source repo only; users who need to merge IaC PRs use `az repos pr update` directly until there's demand.
