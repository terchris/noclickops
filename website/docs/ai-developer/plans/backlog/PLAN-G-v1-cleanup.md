# PLAN-G — v1 cleanup (remove the orphan v1 lib + rename v2 back)

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Backlog

**Goal**: Remove the orphan v1 lib files (`lib/service.sh`, `lib/service.ps1`) that no `bin/*.sh` sources anymore after PLAN-D landed. Then rename `lib/service-v2.sh` → `lib/service.sh` so the canonical lib name reflects the only lib. This closes the v1→v2 transition cleanly.

**Last Updated**: 2026-05-29

**Prerequisites**:
- [PLAN-F](../completed/PLAN-F-add-service-two-pr-flow.md) has shipped (all bin/ commands now source lib/service-v2.sh; no caller of lib/service.sh remains).
- v2 has been **demonstrably verified working end-to-end** against a live target repo. See the smoke-test doc + the verdict on `website/docs/contributors/v2-smoke-test.md`'s Run history. Currently waiting on full verification (some Reader-access constraints; tracking).

**Branch**: standalone — `chore/v1-cleanup`. Single PR.

**Triggers a major version bump** (2.0.0) — this PR is the natural moment to flip semver-major since the v1 surface fully disappears.

---

## Overview

After PLAN-A through PLAN-F shipped, v2 commands source `lib/service-v2.sh` exclusively. The v1 lib files (`lib/service.sh` + `lib/service.ps1`) became orphan code — kept in the tree only so `tests/test-PLAN-008-info.sh` could continue testing them while they technically still existed.

PLAN-G removes the orphans and renames the v2 lib back to the canonical name, since it's now the only one.

This is mechanical work — no behavior change, just cleanup. The win is conceptual clarity (no `-v2` suffix dragging through the codebase) and a small footprint reduction.

---

## What changes

### 1. Delete v1 lib files

- `lib/service.sh` → deleted (orphan; no caller)
- `lib/service.ps1` → deleted (PowerShell was dropped at v2; this file was kept only for paired existence with the .sh version)

### 2. Delete v1 lib tests

- `tests/test-PLAN-008-info.sh` → deleted (only purpose was to test `lib/service.sh`'s `yaml_var` + `resolve_service_context`; both functions go away)
- Confirm via grep that no other test references the v1 lib.

### 3. Rename `lib/service-v2.sh` → `lib/service.sh`

- Move the file.
- Update every `. "$_dir/../lib/service-v2.sh"` reference in `bin/*.sh` to `. "$_dir/../lib/service.sh"`.
- Update the `_NCO_SERVICE_V2_LOADED` guard variable to `_NCO_SERVICE_LOADED`.
- Update the docstring inside the file ("v2 service discovery" → "service discovery").
- Update lib/azdo.sh's source line (added in v1.6.4 for merge-pr).

### 4. Rename `tests/test-PLAN-A-service-discovery.sh`

This file is no longer plan-scoped (the plan completed); it's the lib's test file. Rename to `tests/test-lib-service.sh`.

### 5. Update docs

- `website/docs/contributors/lib-service-v2.md` → rename to `website/docs/contributors/lib-service.md` and update title/headings.
- `website/sidebars.ts` may need adjustment if the doc name is referenced directly.
- Search docs site for any `service-v2` references and update.

### 6. Update redaction map

- `terchris/redaction-map.md` (local-only): remove the "What was NOT redacted" exception that documented v1's `nrx` literal. With the v1 lib gone, the only code containing `nrx`-derived names is in the test fixtures that intentionally use them.

### 7. Version bump → 2.0.0

The v1 surface fully disappears with this PR. That IS the semver-major moment — the target-repo contract change is now also reflected in the file structure. Bump `version.txt` → `2.0.0`.

---

## Phase 1: Delete v1 lib + tests

### Tasks

- [ ] 1.1 Verify no `bin/*.sh` sources `lib/service.sh` (run grep first):
  ```bash
  grep -rn 'service\.sh' bin/ lib/ shell/
  ```
  Expected: only matches for `lib/service-v2.sh` (the v2 lib about to be renamed). If any plain `lib/service.sh` references exist outside the v2 lib itself, fix those first.
- [ ] 1.2 Delete `lib/service.sh` and `lib/service.ps1`.
- [ ] 1.3 Delete `tests/test-PLAN-008-info.sh`.
- [ ] 1.4 Run `bash tests/run-all.sh`. Expect tests to still pass (the lib was orphan; nothing breaks).

### Validation

User confirms phase is complete.

---

## Phase 2: Rename `lib/service-v2.sh` → `lib/service.sh`

### Tasks

- [ ] 2.1 `git mv lib/service-v2.sh lib/service.sh`
- [ ] 2.2 In the new `lib/service.sh`, rename the guard:
  ```bash
  [[ -n "${_NCO_SERVICE_V2_LOADED:-}" ]] && return 0
  _NCO_SERVICE_V2_LOADED=1
  ```
  to:
  ```bash
  [[ -n "${_NCO_SERVICE_LOADED:-}" ]] && return 0
  _NCO_SERVICE_LOADED=1
  ```
- [ ] 2.3 Update the file's docstring header (drop "v2"; describe as "the discovery library for noclickops").
- [ ] 2.4 In every `bin/*.sh` that sources the lib, change `lib/service-v2.sh` → `lib/service.sh`. List of files (verify via grep):
  - `bin/info.sh`
  - `bin/logs.sh`
  - `bin/shell.sh`
  - `bin/deploy.sh`
  - `bin/add-service.sh`
  - `bin/merge-pr.sh` (added in v1.6.4)
  - `bin/create-pr.sh` (added in v1.6.5)
- [ ] 2.5 Run `bash tests/run-all.sh`. Tests still expect the `service-v2.sh` filename in fixtures — update them too (search/replace `service-v2.sh` → `service.sh` in `tests/`).

### Validation

User confirms phase is complete.

---

## Phase 3: Rename `tests/test-PLAN-A-service-discovery.sh`

### Tasks

- [ ] 3.1 `git mv tests/test-PLAN-A-service-discovery.sh tests/test-lib-service.sh`
- [ ] 3.2 Update the file's docstring header (drop "PLAN-A" since the plan is long completed; describe as "tests for lib/service.sh — the discovery library").
- [ ] 3.3 Spot-check assertion descriptions that mention "phase1: ..." etc. — those naming references stay (history is fine; they trace back to the plans).

### Validation

`bash tests/run-all.sh` green. User confirms phase is complete.

---

## Phase 4: Docs updates

### Tasks

- [ ] 4.1 `git mv website/docs/contributors/lib-service-v2.md website/docs/contributors/lib-service.md`
- [ ] 4.2 Update front-matter `title:` and the first H1.
- [ ] 4.3 Find/replace `lib/service-v2.sh` → `lib/service.sh` inside the doc body.
- [ ] 4.4 Find/replace `service-v2` → `service` across `website/docs/` (search first; eyeball each match — some may be in historical PLAN files we'd want to keep as-is).
- [ ] 4.5 `website/sidebars.ts`: if it references the doc by id (e.g. `contributors/lib-service-v2`), update to `contributors/lib-service`. (Probably not — sidebars are autogenerated for contributors.)
- [ ] 4.6 Update `website/docs/contributors/v2-smoke-test.md` if it references `lib/service-v2.sh` paths.

### Validation

`cd website && npm run build` clean. User confirms phase is complete.

---

## Phase 5: Local redaction map + version bump

### Tasks

- [ ] 5.1 Update `terchris/redaction-map.md` (local-only, gitignored): remove the "lib/service.sh + lib/service.ps1 hard-code `nrx`" exception. Note that as of this PR, the noclickops codebase is entirely tenant-token-free.
- [ ] 5.2 Bump `version.txt` → `2.0.0`. This is the moment — v1 is gone, v2 is the only thing, and the target-repo contract change deserves the semver major.

### Validation

User confirms phase is complete.

---

## Acceptance Criteria

- [ ] `lib/service.sh` exists (renamed from `lib/service-v2.sh`); `lib/service.ps1` is deleted; the old `lib/service.sh` is gone (no shadowing)
- [ ] No `service-v2` references remain in `bin/`, `lib/`, `tests/` (grep clean)
- [ ] `tests/test-PLAN-008-info.sh` is gone; `tests/test-lib-service.sh` exists with the same content as the old PLAN-A test
- [ ] `tests/run-all.sh` green
- [ ] Docs build clean; `contributors/lib-service.md` renders
- [ ] `version.txt` shows `2.0.0`
- [ ] `terchris/redaction-map.md` (local) no longer documents the v1 `nrx` exception

## Files to Modify

- `lib/service.sh` (delete)
- `lib/service.ps1` (delete)
- `lib/service-v2.sh` → `lib/service.sh` (rename + edit)
- `lib/azdo.sh` (update source path)
- `bin/info.sh`, `logs.sh`, `shell.sh`, `deploy.sh`, `add-service.sh`, `merge-pr.sh`, `create-pr.sh` (source-path updates)
- `tests/test-PLAN-008-info.sh` (delete)
- `tests/test-PLAN-A-service-discovery.sh` → `tests/test-lib-service.sh` (rename)
- `tests/_fixtures.sh` (any service-v2.sh refs)
- `website/docs/contributors/lib-service-v2.md` → `website/docs/contributors/lib-service.md` (rename + edit)
- `website/docs/contributors/v2-smoke-test.md` (path references)
- `website/sidebars.ts` (if doc id changes)
- `terchris/redaction-map.md` (local)
- `version.txt` → `2.0.0`

## Implementation Notes

### Why this triggers 2.0.0 specifically

The v1 → v2 contract change was committed at v1.6.0 (PLAN-A through PLAN-F shipped together). We kept the version at 1.6.x while v2 was being patched live (1.6.1 → 1.6.2 → 1.6.3 → 1.6.4 → 1.6.5 from real-az-API bugs the smoke surfaced). 1.6.6 / 1.6.7 ship the UX patches on top.

PLAN-G is the final removal of v1 traces from the codebase. AT THAT POINT, the major-bump rationale is clear: "noclickops 2.0 supports the new layout exclusively; v1.x stays at the v1.5.4 tag for FRT users." No more "transition lib" / "transitional naming" ambiguity.

### What NOT to do

- Don't squash this with a feature change. PLAN-G is a pure rename/delete cleanup — squashing with new behavior makes the diff illegible.
- Don't change function signatures during the rename. If something needs renaming for clarity (e.g. `read_iac_variables` → just `read_variables`), file that as a separate PLAN.
- Don't touch the action tables / failure handling from PLAN-v1.6.6/v1.6.7. Those land as separate plans before or after PLAN-G; don't mix.

### Dependency on verification

This plan is **gated on v2 being demonstrably working end-to-end**. The current state (as of 2026-05-29) is: pipeline-success signal is solid, but full end-to-end HTTPS-200 hasn't been verified due to test-sub Reader-access constraints. Don't ship PLAN-G until verification is complete — the version bump to 2.0.0 should not be premature.

### Out of scope

- Behavior changes (those go in PLAN-v1.6.6 / 1.6.7)
- Adding new commands (separate plans)
- The `SCRIPT_EXAMPLE_OUTPUT` field (PLAN-help-example-output)
