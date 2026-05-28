# PLAN-007a: drop `--watch` from `add-service`; add `noclickops status`

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-28

**Goal**: Fix a UX mismatch in PLAN-007 (add-service watches for ~30min while the pipeline takes ~1h) by switching add-service to fire-and-forget, and adding a generic `noclickops status <run-id>` checker so the user can ask "is run X done?" any time.

**Last Updated**: 2026-05-28

**Investigations**: none — direct response to user feedback after PLAN-007 shipped.

**Depends on**: PLAN-001 (lib/), PLAN-003 (`lib/azdo.sh`), PLAN-007 (the add-service flow this amends).

**Priority**: High — without this, the add-service flow as shipped in PLAN-007 quietly hits the 30-min `--watch` timeout while the real pipeline keeps running, leaving the user with a misleading "timed out" message and no easy way to find out if it actually succeeded.

---

## Problem

PLAN-007 shipped `add-service [--watch]` using the same poll loop as `deploy`: every 20s up to 90 iterations = 30 min cap. That's fine for deploys (typical 5–15 min). It's wrong for `add-service`, which routinely runs for ~1h: it provisions infra, runs Copier, opens a PR, then creates the new `<repo>-<svc>-CD` pipeline. The watch is guaranteed to time out before the pipeline finishes.

Two distinct fixes are needed:

1. `add-service` shouldn't block a shell for an hour. Fire-and-forget is the right shape.
2. The user still needs a way to ask "is run X done yet?" — without leaving a `--watch` running.

---

## What it delivers

### Change to `bin/add-service.{sh,ps1}` (PLAN-007 amendment)

- **Remove the `--watch` flag.** The script always fires-and-forgets.
- **Update the trailing next-steps message** to point at `noclickops status <run-id>` and to set expectations on runtime ("This pipeline takes ~1h …").
- Keep the run-id + URL print so the user has what they need to check later.

### New `bin/status.{sh,ps1}`

```text
noclickops status <run-id>
```

Behaviour:

- Numeric-id validation (ADO run ids are integers).
- `lib/azdo.sh` derives the org+project from the target repo's `origin`; same auth path as `deploy` / `create-pr` / `merge-pr`.
- One `az pipelines runs show` call returns `definition.name`, `status`, `result`, `startTime`, `finishTime` in TSV.
- Prints the run id, pipeline name, status, result (if completed), started + finished timestamps (if set), and the build-results URL.
- Exit 0 if the lookup succeeded — **regardless of the pipeline outcome**. CI gating callers can grep the output for `Result: succeeded`. (No `--exit-code` flag for v1; defer until a real use case asks.)
- No `--watch`. Re-running the command is cheap; if the user wants periodic polls, `watch -n 60 noclickops status 12345` from their shell does the job.

### Lister + categorisation

`status` declares `SCRIPT_CATEGORY="inspect"`. The lister already reserves the **"Inspect / observe"** section header; this is its first occupant. (PLAN-008's `info` will join later.)

### Tests

- **Update** `tests/test-PLAN-007-add-service.sh`: the existing test set doesn't exercise `--watch`, so no test removals; only the **next-steps** message changes if we assert on it. We don't, so the existing 21 tests stay as-is.
- **New** `tests/test-PLAN-007a-status.sh`: validation-only coverage (no `az`).
  - Lister shows `status` under "Inspect / observe".
  - `--help` prints metadata block.
  - No-arg call → usage error.
  - Non-numeric run-id → distinct rejection.
  - Outside-repo call → "Not inside a git repository".
  - Pipeline-name composition isn't applicable (status doesn't compose a name).

End-to-end against real ADO runs is deferred — same gate as PLAN-003/004/007.

---

## Phases

1. Strip `--watch` from `bin/add-service.{sh,ps1}`; rewrite the next-steps message.
2. Add `bin/status.{sh,ps1}`.
3. Add `tests/test-PLAN-007a-status.sh`.
4. Run the full suite; confirm aggregate count grows correctly.

---

## Validation criteria

- `noclickops add-service <name>` no longer accepts `--watch`; passing it triggers the existing "Unknown flag" error.
- `noclickops` lister now shows the "Inspect / observe" section with `status`.
- `noclickops status` (no arg) errors with usage.
- `noclickops status abc` (non-numeric) errors with "Run id must be numeric".
- `noclickops status 12345` outside a git repo errors with the documented message.
- `tests/run-all.sh` exit 0; aggregate count grows by the new test file's tests.

---

## Completion notes (2026-05-28)

Four-phase ship on `feature/ai-developer-bootstrap`.

**Tests** — `tests/test-PLAN-007a-status.sh`, 17 tests:

| # | Test | Result |
| --- | --- | --- |
| 1–2 | Lister now shows the "Inspect / observe" section with `status` | ✅ |
| 3–4 | `status --help` shows the metadata block (category + usage) | ✅ |
| 5–6 | `status` no args → usage error | ✅ |
| 7–10 | Non-numeric run-ids rejected: `abc`, `12.3` | ✅ |
| 11–12 | Negative id rejected (either as numeric guard or arg-parsing) | ✅ |
| 13–14 | `status` outside a git repo → "Not inside a git repository" | ✅ |
| 15 | `add-service --help` no longer mentions `--watch` | ✅ |
| 16–17 | `add-service myservice --watch` now rejected as "Unknown flag" | ✅ |

**Aggregate**: `tests/run-all.sh` total is **172, 0 failed, 0 skipped** (was 155 after PLAN-007).

**Lister now fully populated** — every category from PLAN-002 has at least one occupant:

```text
Meta                noclickops, update
Git / pull requests create-pr, merge-pr
Deployment          deploy
Service lifecycle   add-service, clean-sample, sync-lovable
Inspect / observe   status                                  ← new
```

**`bin/add-service.{sh,ps1}` changes**:

- Dropped the `--watch` flag (parser, poll loop, both happy-path and timeout branches gone).
- Trailing message now reads: "This pipeline takes ~1 hour. The shell returns now." plus a 5-line next-steps chain that starts with `noclickops status <run-id>`.

**`bin/status.{sh,ps1}`** is intentionally generic — works for any pipeline-run id in the target repo's project, not only add-service runs. That same status checker will be useful after `deploy` (when the user closes the `--watch` and wants to re-check), after any pipeline retry, etc.

**Exit code policy**: `status` exits 0 if the lookup succeeded, regardless of pipeline outcome. CI gating callers can grep the output for `Result: succeeded`. No `--exit-code` flag for v1; defer until a real use case asks.

**End-to-end against real ADO runs still deferred** — same gate as PLAN-003/004/007. The next manual `noclickops status <real-id>` is the live validation.
