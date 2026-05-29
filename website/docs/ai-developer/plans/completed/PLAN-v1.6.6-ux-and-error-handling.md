# PLAN-v1.6.6 — UX patches + error handling for `watch_run`

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Backlog

**Goal**: Land the UX gaps surfaced by the live v1.6.x smoke runs as a single coherent patch. Four items: command-header line, `add-service` step counter, `watch_run` polling-dot cleanup, and `watch_run` failure handling that fetches the ADO timeline + prints actionable hints instead of just an URL.

**Last Updated**: 2026-05-29

**Driver**: Live-smoke session 2026-05-29 (v1.6.0 → 1.6.5). The smoke surfaced 5 real-az-API bugs (shipped as v1.6.1 → 1.6.5) AND multiple UX gaps. The bugs are patched; the UX gaps are this plan.

**Branch**: standalone — `feat/v1.6.6-ux-errors`. Single PR, single version bump (1.6.5 → 1.6.6).

**Out of scope**: PR-merge-failure handling (separate plan: PLAN-v1.6.7), `SCRIPT_EXAMPLE_OUTPUT` field (separate plan: PLAN-help-example-output), v1-cleanup (separate plan: PLAN-G).

---

## What changes

### 1. Command header line on every command

Every `bin/<cmd>.sh` prints, immediately after arg-parsing:

```
noclickops <cmd> v<version> — <one-line summary of what's about to happen>
```

Examples:
- `noclickops info v1.6.6 — frontend (test)`
- `noclickops logs v1.6.6 — frontend (test, --tail 5)`
- `noclickops add-service v1.6.6 — scaffolding 'smk1' (~1-3 min, 4 steps)`
- `noclickops deploy v1.6.6 — 'smk1' → test (FIRST-TIME, 4 pipelines, ~6-10 min)`

Implementation: a single helper in `lib/metadata.sh`:

```bash
nco_command_header() {
  local summary="$1"
  printf '\n%s — %s\n\n' "$NCO_HEADER_PREFIX" "$summary"
}
# NCO_HEADER_PREFIX expands to "noclickops <SCRIPT_NAME> v<version>"
# Computed once from SCRIPT_NAME + nco_load_version.
```

Each `bin/<cmd>.sh` calls `nco_command_header "<summary>"` once.

### 2. Step counter for `add-service`

Mirror `deploy`'s `[1/4] ... [4/4]` pattern. Each step prints estimated duration inline based on observed times from the v1.6.x smoke:

```
  [1/4] Trigger add-service pipeline             (~30-60s)   run 28578 … succeeded (0m 23s)
  [2/4] Wait for PR-A in source repo             (~10-30s)   found #4849 … merged
  [3/4] Wait for PR-B in IaC/platform-infra      (~10-30s)   found #4850 … merged
  [4/4] Sync local main                          (~5s)       ok
```

### 3. `watch_run` polling-dot cleanup

Currently dots get printed inline on the same line as the step label, then the `succeeded (Xm Ys)` summary appears on a new line. Looks like:

```
  [1/4] FrontendPlatform/<repo>-<svc>-build   run 28580 … ...
succeeded (1m 3s)
```

Fix: dots go on their own line after the label, summary replaces the dots when done. Target:

```
  [1/4] FrontendPlatform/<repo>-<svc>-build   run 28580 ▶ in-progress (45s)…
  [1/4] FrontendPlatform/<repo>-<svc>-build   run 28580 ✓ succeeded (1m 3s)
```

(Or simpler: rewrite the same line with `\r` and overwrite on each poll.)

### 4. `watch_run` failure handling — fetch timeline + actionable hint

When a pipeline reports `failed`, `watch_run` currently prints the elapsed time + a URL. Replace with the full block:

```
✗ FAILED: TCH900001-mrkmedlem-smkpub-deploy-test (run 28585, 2m 25s)

  Step:    AzureResourceManagerTemplateDeployment

  Error:   Template validation failed.
           The deployment 'acaService' in rg-test-nrx-tch900001 cannot be
           saved because an existing deployment is still active
           (started 21:09:40 UTC).

  Action:  → Wait ~3 min for the prior deploy to complete, then retry:
               noclickops deploy smkpub test

  Full log: https://dev.azure.com/RedCrossNorway/IaC/_build/results?buildId=28585
```

Implementation: new helper in `lib/service-v2.sh`:

```bash
report_pipeline_failure <project> <run-id>
  # 1. GET /_apis/build/builds/<run-id>/timeline?api-version=7.0 via _nco_ado_rest_get
  # 2. Extract records with result=failed && issues != null
  # 3. From each record's issues[], pick the last non-empty message (most specific)
  # 4. Match the message against the action-pattern table; emit Action line
  # 5. Print the formatted block (header / step / error / action / URL)
```

Action-pattern table (initial set — extensible):

| Signature in error message | Action |
|---|---|
| `cannot be saved, because this would overwrite an existing deployment` | Wait ~3 min and retry: `noclickops deploy svc env` (where `<svc>` and `<env>` are placeholders for the actual service + env) |
| `ContainerAppInvalidName` | Service name too long. Full container app name `ca-env-TENANT-svc` must fit 32 chars; rename service to ≤ 20 chars. |
| `AuthorizationFailed` | You don't have the required role on the subscription. Ask the admin or check PIM eligibility for the subscription named in the error. |
| `ResourceGroupNotFound` | The IaC PR-B may not be merged yet. Check `IaC/platform-infrastructure` for an open PR titled "Add service \<svc\>". |
| `Trivy ... CRITICAL` (image scan) | Image has critical CVEs. Bump the base image in `services/<svc>/Dockerfile` and re-deploy. |
| _(no match)_ | See full log for details. If this happens repeatedly, file a finding. |

`watch_run` calls `report_pipeline_failure` instead of just `printf 'failed (...)'`.

---

## Phase 1: Header + version variable — DONE

### Tasks

- [x] 1.1 Add `nco_command_header <summary>` helper to `lib/metadata.sh` (or a new `lib/header.sh` if metadata.sh gets crowded). Uses `nco_load_version` for the version.
- [x] 1.2 Add a `nco_command_header` call to each `bin/<cmd>.sh` (11 commands; `noclickops`-lister doesn't need it). Pick a meaningful summary per command:
  - `info`: `<svc> (<env>)`
  - `logs`: `<svc> (<env>, --tail N[, --follow][, --system])`
  - `shell`: `<svc> (<env>, cmd: <cmd>)`
  - `status`: `recent runs in <repo>` (or `run <id>` when an id is given)
  - `deploy`: `<svc> → <env> (FIRST-TIME, 4 pipelines, ~6-10 min)` OR `<svc> → <env> (subsequent, ~30-45s)`
  - `add-service`: `scaffolding '<svc>' (~1-3 min, 4 steps)`
  - `clean-sample`: `strip Express+OIDC sample from services/<svc>/app/`
  - `create-pr`: `'<title>' (<branch> → main) in <repo>`
  - `merge-pr`: `PR #<id> in <repo>`
  - `update`: `pull latest noclickops`
  - `sync-lovable`: `sync <source> → <svc>`

### Validation

```bash
for cmd in info logs shell status deploy add-service clean-sample create-pr merge-pr update sync-lovable; do
  noclickops $cmd --help | head -2
done
```

Each must show the header line right after the lister banner (or instead of, when `--help` doesn't dispatch to the function).

Wait — `--help` exits early. Decide: should the header print on `--help` too, or only when the command is actually doing work? Reasonable answer: only when doing work (header is "what's about to happen", and `--help` isn't doing it). Detailed in 1.3.

- [x] 1.3 Decision: header prints AFTER `case ... in -h|--help) show_help` early-exit. Document.

User confirms phase is complete.

---

## Phase 2: `add-service` step counter — DONE

### Tasks

- [x] 2.1 Rewrite the step output in `bin/add-service.sh` to use the `[N/4]` format with inline estimated durations matching `deploy`. Each step:
  - Print step label + estimate on a partial line: `  [1/4] Trigger add-service pipeline       (~30-60s) `
  - Do the work
  - Replace `(~estimate)` portion with the actual outcome: ` run 28578 … succeeded (0m 23s)`
  - Newline.
- [x] 2.2 The four step labels:
  - `[1/4] Trigger add-service pipeline             (~30-60s)`
  - `[2/4] Wait for PR-A in source repo             (~10-30s)`
  - `[3/4] Wait for PR-B in IaC/platform-infra      (~10-30s)`
  - `[4/4] Sync local main                          (~5s)`
- [x] 2.3 Update test fixtures + assertions in `tests/test-PLAN-F-add-service.sh` to expect the new format.

### Validation

`bash tests/run-all.sh` green. Manual run shows the new step format.

User confirms phase is complete.

---

## Phase 3: `watch_run` polling-dot cleanup — DONE

### Tasks

- [x] 3.1 In `lib/service-v2.sh`'s `watch_run`, replace the inline dot pattern with line-rewrite via `\r` + `printf` (when stdout is a tty). Format:
  - In-progress poll: `  [N/4] <label>   run <id> ▶ in-progress (<elapsed-s>s)…\r`
  - Terminal: `  [N/4] <label>   run <id> ✓ succeeded (Xm Ys)\n` (overwrites the in-progress line; the `\n` commits it)
- [x] 3.2 When stdout is NOT a tty (CI / piped output), fall back to the current dot pattern or print each poll on its own line — the line-rewrite trick doesn't work without a tty.
- [x] 3.3 Update tests that grep for the old dot output. Most tests use `NCO_WATCH_INTERVAL=0` so the polling loop runs once and the format change is contained.

### Validation

`bash tests/run-all.sh` green. Manual deploy run shows live progress overwriting the same line instead of accumulating dots.

User confirms phase is complete.

---

## Phase 4: `report_pipeline_failure` helper + wire into `watch_run` — DONE

### Tasks

- [x] 4.1 Add `report_pipeline_failure <project> <run-id>` to `lib/service-v2.sh`:
  - Calls `_nco_ado_rest_get` on `/_apis/build/builds/<id>/timeline?api-version=7.0`.
  - Parses the JSON (uses `python3` — `python3` is already a documented dependency for `scripts/generate-docs.sh`; alternative: use `jq` if available; or a careful awk/sed pipeline).
  - For each failed record with issues:
    - Pick the last non-empty `issues[].message` (most specific).
    - Pattern-match against the action table (Phase 4.2 below).
    - Format the block.
  - If no failed-with-issues records: fall back to printing the original "failed + URL" message (so we never make things worse).
- [x] 4.2 Action-pattern table — initially defined inline in the helper. Each entry: a regex/glob and a hint template (templates can include `<svc>`, `<env>`, `<sub>` — passed in or pulled from env). Five initial patterns per the table above.
- [x] 4.3 Update `watch_run` to call `report_pipeline_failure` on terminal-failed instead of `printf 'failed (...)'`. Keep the elapsed time in the summary so we still see "how long until it failed".
- [x] 4.4 Tests:
  - Unit-test `report_pipeline_failure` against canned timeline JSON (fixture file). Cover: each known pattern matches, unknown pattern falls through, empty issues array falls back.
  - Update `watch_run` failure tests to expect the new output (or wrap the `watch_run` fail-path test to assert on the formatted block).

### Validation

`bash tests/run-all.sh` green. Manual smoke: trigger a known-failing pipeline (e.g. re-deploy smkpub before the "active deployment" lock clears) — expect the formatted block + "wait + retry" hint.

User confirms phase is complete.

---

## Phase 5: Docs + version bump — DONE

### Tasks

- [x] 5.1 Update `website/docs/contributors/lib-service-v2.md`: add `report_pipeline_failure` to the Public API table.
- [x] 5.2 Update `website/docs/contributors/v2-smoke-test.md`: each pipeline-failure case in the smoke now expects the formatted-failure block; update assertions if any.
- [x] 5.3 Bump `version.txt` → `1.6.6`.

### Validation

`cd website && npm run build` clean.

User confirms phase is complete.

---

## Acceptance Criteria

- [ ] Every `bin/<cmd>.sh` (except the lister) prints `noclickops <cmd> v<version> — <summary>` when doing work (where each placeholder in angle brackets is filled at runtime)
- [ ] `add-service` shows `[1/4]…[4/4]` with inline `(~estimate)` and final actual time
- [ ] `watch_run` polling progress overwrites the same line (tty mode) instead of accumulating dots
- [ ] `watch_run` on terminal-failed prints the formatted block (Step / Error / Action / Full log) — at minimum for the 5 known patterns
- [ ] `tests/run-all.sh` green
- [ ] `version.txt` shows `1.6.6`

## Files to Modify

- `lib/metadata.sh` (add `nco_command_header`)
- `lib/service-v2.sh` (add `report_pipeline_failure`; update `watch_run`)
- `bin/info.sh`, `logs.sh`, `shell.sh`, `status.sh`, `deploy.sh`, `add-service.sh`, `clean-sample.sh`, `create-pr.sh`, `merge-pr.sh`, `update.sh`, `sync-lovable.sh` (header calls)
- `bin/add-service.sh` (step counter rewrite)
- `tests/test-PLAN-A-service-discovery.sh` (lib-level tests for `report_pipeline_failure`)
- `tests/test-PLAN-F-add-service.sh` (step-format assertions)
- `tests/test-PLAN-C-deploy.sh` (watch-format assertions)
- `website/docs/contributors/lib-service-v2.md`
- `version.txt`

## Implementation Notes

### Why one PR for all four items

Each item alone is too small to justify its own PR (sub-100-line patches). Bundling them into v1.6.6 keeps the version-bump rhythm matching the patch density. If any item turns out larger than expected during implementation, split at that point.

### `python3` for JSON parsing

`scripts/generate-docs.sh` already uses Python for JSON parsing. `report_pipeline_failure` can do the same. Alternative: require `jq` (already de-facto on every dev machine but not currently a noclickops dep). Decide during implementation; lean toward python3 to avoid adding a hard dep.

### Action-pattern table extensibility

Initial 5 patterns cover what we've seen in the live smoke. Real-world use will surface more. Format the patterns + actions as a simple data structure (e.g. a bash assoc array or a heredoc parsed at runtime) so adding a 6th pattern is one new entry, not a code change.

### Out of scope for v1.6.6

- `report_pr_merge_failure` + `report_rest_failure` (PLAN-v1.6.7)
- `SCRIPT_EXAMPLE_OUTPUT` field (separate plan)
- The smoke-test doc's Run history block for the v1.6.x session — that ships whenever the user signs off on the captured results.
