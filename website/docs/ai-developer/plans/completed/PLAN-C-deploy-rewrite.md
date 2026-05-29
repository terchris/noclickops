# PLAN-C — `deploy` rewrite for v2 (multi-pipeline orchestration)

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Completed

**Goal**: Rewrite `bin/deploy.sh` so `noclickops deploy <svc> <env>` orchestrates the right set of pipelines for the new two-project / two-repo layout. v1's single `<repo>-<svc>-CD` trigger doesn't exist in the new layout; v2 detects whether this is the first deploy and runs the appropriate chain.

**Last Updated**: 2026-05-29

**Completed**: 2026-05-29

### Completion notes

- `bin/deploy.sh` rewritten end-to-end on `lib/service-v2.sh`. Three new lib functions: `is_first_time_deploy` (predicate), `trigger_pipeline` (wraps `az pipelines run`), `watch_run` (polls until terminal).
- Detection works against stubbed IaC `pipelines runs list`: prior succeeded ≥1 → subsequent path; zero or missing pipeline → first-time path.
- Subsequent path: triggers `<repo>-<svc>-deploy`, watches it, exits. `--watch` also polls IaC for the auto-triggered deploy-test run and watches it.
- First-time path: 4-pipeline chain (build → deploy → infra-build → deploy-test) with fail-fast at any failed step. Summary block prints derived container app + public URL (with --watch-live hint when public).
- Specific PR-A vs PR-B error messages surface the most common cause of missing pipelines (developers don't always know PR-B exists in `platform-infrastructure`).
- `tests/test-PLAN-C-deploy.sh` adds 21 assertions covering all paths. `tests/test-PLAN-004-deploy.sh` deleted (v1 deploy gone).
- Test-only env vars `NCO_WATCH_INTERVAL` + `NCO_WATCH_TIMEOUT_MIN` let `watch_run` complete in milliseconds during tests.
- Total tests: 396 → 435 passing, 0 failed.
- Branch stays `feat/v2-new-target-structure`. Per CLAUDE.md PR-per-investigation rule.

**Investigation**: [INVESTIGATE-new-target-structure.md](INVESTIGATE-new-target-structure.md) (see § "Per-command impact → deploy" and § "PLAN sequence → PLAN-C")

**Prerequisites**: [PLAN-A](../completed/PLAN-A-service-discovery.md) ships `lib/service-v2.sh` (used for `discover_pipelines`, `read_service_config`, `read_iac_variables`).

**Branch**: same as PLAN-A/B — `feat/v2-new-target-structure`.

**Out of scope (separate plan)**: `--watch-live` first-time-public polling. See [PLAN-watch-live-deploy.md](../backlog/PLAN-watch-live-deploy.md).

---

## Overview

v1's deploy is a single `az pipelines run --name <repo>-<svc>-CD --parameters targetEnvironment=<env>`. That pipeline doesn't exist in the new layout. The new layout splits the work across **five pipelines in two projects**:

```text
FrontendPlatform/<repo>-<svc>-build         (~1-2 min, publishes deploy-package artifact)
FrontendPlatform/<repo>-<svc>-deploy        (~30s, publishes deployment-package-<env> artifact)
   ↓ resource trigger (auto, after first successful run)
IaC/<repo>-<svc>-infra-build                (~3 min, pushes image to ACR)  — first time only
IaC/<repo>-<svc>-deploy-test                (~6 min, ARM template deploys container app)
```

For **subsequent deploys**, only the first two need to be triggered explicitly — the resource trigger on IaC's `deploy-test` fires automatically off FrontendPlatform's `deploy` succeeding.

For **first-time deploys** (no `<repo>-<svc>-deploy-test` run has ever succeeded for this service), the resource trigger isn't wired yet (ADO quirk: it activates only after the IaC pipeline has run once manually). v2 must trigger all four explicitly, in sequence, waiting for each to finish before starting the next.

v2's `deploy` automates that decision.

---

## Two execution paths

### Subsequent (default — only path when `<repo>-<svc>-deploy-test` has a prior success)

```text
1. Trigger FrontendPlatform/<repo>-<svc>-deploy
2. Wait for it to complete (~30s)
3. Exit with the FrontendPlatform run URL printed.
   With --watch, also poll IaC for the auto-triggered deploy-test run and watch it.
```

User sees output:
```text
Deploying frontend → test (subsequent run, resource trigger expected)
  ✓ FrontendPlatform/ABC100001-myservice-frontend-deploy   run 4521 succeeded (28s)
  ✓ IaC/ABC100001-myservice-frontend-deploy-test           run 8932 succeeded (4m12s)   [--watch only]
```

### First-time (no prior successful `<repo>-<svc>-deploy-test` run)

```text
1. Trigger FrontendPlatform/<repo>-<svc>-build, watch to success
2. Trigger FrontendPlatform/<repo>-<svc>-deploy, watch to success
3. Trigger IaC/<repo>-<svc>-infra-build,         watch to success
4. Trigger IaC/<repo>-<svc>-deploy-test,         watch to success
5. Print summary + Public URL line (or "no public endpoint configured")
```

User sees output:
```text
Deploying frontend → test (FIRST-TIME — full chain, ~10 min)
  [1/4] FrontendPlatform/ABC100001-myservice-frontend-build       ▶ running… ✓ (1m42s)
  [2/4] FrontendPlatform/ABC100001-myservice-frontend-deploy      ▶ running… ✓ (28s)
  [3/4] IaC/ABC100001-myservice-frontend-infra-build              ▶ running… ✓ (2m51s)
  [4/4] IaC/ABC100001-myservice-frontend-deploy-test              ▶ running… ✓ (5m37s)

Deploy complete.
  Container app: ca-abc100001-frontend (rg-test-myteam-frontend-common)
  Public URL:    https://frontend.example.cloud   (first-time public endpoint — Front Door + cert ~30-90 min)
```

The public-URL note hints the user toward `--watch-live` (PLAN-watch-live-deploy) for the longer first-time wait.

---

## Detection

Query IaC for prior successful runs of `<repo>-<svc>-deploy-test`:

```bash
az pipelines runs list \
  --organization "$AZDO_ORG_URL" --project "$iac_project" \
  --pipeline-ids "$iac_deploy_test_id" \
  --query "[?result=='succeeded'] | length(@)" \
  -o tsv
```

If result > 0 → subsequent path. If 0 → first-time path. The `iac_deploy_test_id` comes from `discover_pipelines`.

Edge case: if `iac_deploy_test_id` is empty (pipeline doesn't exist yet in IaC), that means `<repo>-infra-add-service` hasn't completed (PR-B not merged). Die with a clear message: "IaC pipeline `<repo>-<svc>-deploy-test` doesn't exist yet — merge the platform-infrastructure PR-B for this service first (see `noclickops add-service`)."

---

## Phase 1: Detection helper — DONE

### Tasks

- [x] 1.1 Add `is_first_time_deploy <svc>` to `lib/service-v2.sh`:
  - Requires `discover_pipelines` to have run (or runs it internally).
  - Returns exit 0 (first-time) when IaC `deploy-test` pipeline either doesn't exist OR has zero successful runs.
  - Returns exit 1 (subsequent) when there's ≥1 successful run.
  - Echoes nothing — communicates via exit code (Bash convention for predicates).
- [x] 1.2 Add a small helper `_v2_pipeline_succeeded_count <project> <pipeline-id>`:
  - Wraps `_nco_az pipelines runs list --pipeline-ids ... --query "[?result=='succeeded'] | length(@)" -o tsv`.
  - Echoes the count (integer).
- [x] 1.3 Tests in `tests/test-PLAN-A-service-discovery.sh` (this is still discovery work):
  - `is_first_time_deploy` returns first-time when pipeline ID is empty.
  - Returns first-time when stub `az pipelines runs list` returns 0.
  - Returns subsequent when stub returns `>= 1`.

### Validation

```bash
bash tests/run-all.sh
```

User confirms phase is complete.

---

## Phase 2: Pipeline trigger + watch helpers — DONE

These could live in `lib/service-v2.sh` or a sibling `lib/pipeline-v2.sh`. **Decision: keep in `lib/service-v2.sh`** for now — it's small, already sources `_nco_az`, and PLAN-D might reuse `watch_run` for `logs --follow-deploy`-style ergonomics. If the module grows past ~500 lines, split later.

### Tasks

- [x] 2.1 Add `trigger_pipeline <project> <pipeline-name> [--param k=v ...]` to `lib/service-v2.sh`:
  - Wraps `_nco_az pipelines run --organization $AZDO_ORG_URL --project <project> --name <name> --branch refs/heads/main [--parameters ...] --query id -o tsv`.
  - Echoes the new run ID on stdout. Dies on failure.
- [x] 2.2 Add `watch_run <project> <run-id> [--timeout-min N]`:
  - Polls `_nco_az pipelines runs show --id ... --query "{status, result}"` every 20s.
  - Default timeout 30 min (single pipeline) — first-time chain phases set `--timeout-min 10` for build/deploy and `--timeout-min 10` for infra-build/deploy-test (so total ≤ 40 min).
  - Echoes one progress dot per poll (when stdout is a tty).
  - Returns exit 0 on `result=succeeded`, exit 1 on any other terminal state or timeout.
  - Always echoes a final summary line: `succeeded (3m41s)` / `failed (1m22s)` / `timed out after 10m`.
- [x] 2.3 Tests:
  - `trigger_pipeline` happy path → echoes the stubbed run ID.
  - `watch_run` happy path → stub `runs show` returns `inProgress` then `completed/succeeded`; assert exit 0 + "succeeded" in stdout.
  - `watch_run` failure path → stub returns `completed/failed`; assert exit 1 + "failed" in stdout.
  - `watch_run` timeout → set `--timeout-min 0` (or override poll interval); assert exit 1 + "timed out".

### Validation

```bash
bash tests/test-PLAN-A-service-discovery.sh
```

User confirms phase is complete.

---

## Phase 3: Subsequent-deploy path in `bin/deploy.sh` — DONE

### Tasks

- [x] 3.1 In `bin/deploy.sh`, replace the v1 source line `. "$_dir/../lib/azdo.sh"` → `. "$_dir/../lib/service-v2.sh"` (the v2 lib already sources azdo.sh transitively).
- [x] 3.2 Update docstring + `SCRIPT_DETAILS` to describe the multi-pipeline orchestration.
- [x] 3.3 Argument parsing (keep familiar):
  - Positionals: `<service>` `[test|prod]` (default test).
  - Flags: `--watch` (opt-in for subsequent path; mandatory for first-time path, no flag needed).
  - `-h, --help`.
- [x] 3.4 Resolve context:
  ```bash
  read_iac_variables "$env"
  pipelines=$(discover_pipelines "$service")
  # parse the 5 role=id lines into role_* variables
  ```
- [x] 3.5 Detection: `if is_first_time_deploy "$service"; then ... first-time path ... else ... subsequent path ... fi`.
- [x] 3.6 Subsequent-path block:
  - Validate `frontend_deploy_id` is non-empty (else die with "pipeline `<repo>-<svc>-deploy` not found in FrontendPlatform; has `add-service` run?").
  - Print "Deploying $service → $env (subsequent run, resource trigger expected)".
  - `frontend_run_id=$(trigger_pipeline "$AZDO_PROJECT" "$frontend_deploy_name")`.
  - Print `[1/1] FrontendPlatform/... run $frontend_run_id  ` (or `[1/2]` if --watch).
  - Always watch `frontend_run_id` (it only takes ~30s).
  - If `--watch`: poll IaC for the auto-triggered run. Use `az pipelines runs list --pipeline-ids $iac_deploy_test_id --top 5 --query "[?triggerInfo.\"pr.sourceBranch\"==null]|[0]"` — first non-PR-triggered recent run. Watch it.
  - Exit 0 with both run URLs printed.

### Validation

```bash
bash tests/run-all.sh
```

User confirms phase is complete.

---

## Phase 4: First-time deploy path — DONE

### Tasks

- [x] 4.1 First-time block in `bin/deploy.sh`:
  - Validate all four required pipeline IDs are non-empty (`frontend_build`, `frontend_deploy`, `iac_infra_build`, `iac_deploy_test`). If any missing, die with a specific message naming the missing one + most likely cause:
    - missing `frontend_build` / `frontend_deploy` → "FrontendPlatform pipelines not registered for $service. Has `add-service` PR-A merged?"
    - missing `iac_infra_build` / `iac_deploy_test` → "IaC pipelines not registered for $service. Has `add-service` PR-B (platform-infrastructure) merged?"
  - Print "Deploying $service → $env (FIRST-TIME — full chain, ~10 min)".
  - Run the four pipelines in sequence:
    1. `trigger_pipeline` $frontend_build_name → `watch_run` → fail fast on non-success
    2. Same for $frontend_deploy_name
    3. Same for $iac_infra_build_name
    4. Same for $iac_deploy_test_name
  - On success, print "Deploy complete." block:
    - `Container app: <derived-name>` (use `derive_containerapp_name`)
    - `Public URL: https://<host>  (first-time public endpoint — Front Door + cert ~30-90 min)` when `SVC_CFG_ENABLE_PUBLIC_ENDPOINT=true`. Mention `--watch-live` as the way to wait for HTTPS-200.
  - On failure: print which step failed + run URL; exit 1.
- [x] 4.2 Add a `--no-chain` escape hatch flag: triggers only the next-step pipeline based on which previous ones already succeeded, in case the user wants to resume a stuck flow manually. Low priority — file as a Phase 4 task but acceptable to skip in v1 of PLAN-C and add later.

### Validation

```bash
bash tests/run-all.sh
```

User confirms phase is complete.

---

## Phase 5: Tests + docs — DONE

### Tasks

- [x] 5.1 Create `tests/test-PLAN-C-deploy.sh`. Cover:
  - `--help` renders v2 metadata.
  - No args → usage + exit 1.
  - Outside a git repo → clear error.
  - Detection: stub IaC `pipelines runs list` returns empty → first-time; returns count ≥1 → subsequent.
  - Subsequent path: triggers frontend-deploy, watches it, exits 0. With `--watch`, also polls + watches IaC deploy-test.
  - First-time path: triggers all 4 pipelines in sequence; each pipeline returns `succeeded`; final summary block has container-app name + public URL line.
  - First-time partial failure: pipeline 2 returns `failed` → exit 1 with specific "Deploy failed at step 2/4" message; pipelines 3 and 4 are NOT triggered.
  - Missing pipeline IDs → specific error messages naming PR-A vs PR-B as the likely cause.
- [x] 5.2 Delete `tests/test-PLAN-004-deploy.sh` if it exists (v1 deploy tests). If it tests anything still relevant to `lib/azdo.sh` etc., move those assertions to `tests/test-PLAN-008-info.sh`'s lib-level section (rename misnomer? not worth it — keep the file name as-is).
- [x] 5.3 Update `website/docs/getting-started.md`:
  - Compatibility matrix: `deploy` flips to v2-ready, drop the "fails with no build definitions" line.
  - Add a v2 example output snippet (subsequent path + first-time path).
- [x] 5.4 Update `website/docs/contributors/target-layout-reference.md`: cross-reference the "First-time vs subsequent deploy" section to PLAN-C.
- [x] 5.5 Manual end-to-end smoke against a live target repo: trigger one subsequent deploy + one first-time deploy (on a freshly-added service via `add-service`). Verify the output matches the spec.

### Validation

```bash
bash tests/run-all.sh
```

All green. New `test-PLAN-C-deploy.sh` contributes a meaningful number of assertions (target ~30).

User confirms phase is complete.

---

## Acceptance Criteria

- [ ] `bin/deploy.sh` sources `lib/service-v2.sh` (not `lib/azdo.sh` directly)
- [ ] Detection correctly picks first-time vs subsequent path against a stubbed IaC
- [ ] Subsequent path triggers exactly one pipeline by default (two with `--watch`)
- [ ] First-time path runs all four in strict sequence and fails fast on the first failure
- [ ] Clear error messages for each "missing pipeline ID" cause (PR-A vs PR-B)
- [ ] No `<repo>-<svc>-CD` reference (v1's pipeline name) remains in `bin/deploy.sh`
- [ ] No hardcoded `nrx` / customer-tenant string anywhere new
- [ ] `tests/test-PLAN-C-deploy.sh` exists and passes; `tests/run-all.sh` green
- [ ] `website/docs/getting-started.md` reflects v2-ready status for `deploy`
- [ ] Manual smoke: both paths verified against a live target repo

---

## Files to Modify

- `bin/deploy.sh` (rewrite)
- `lib/service-v2.sh` (add `is_first_time_deploy`, `trigger_pipeline`, `watch_run` + helpers)
- `tests/test-PLAN-A-service-discovery.sh` (add lib-level tests for the 3 new functions)
- `tests/test-PLAN-C-deploy.sh` (new)
- `tests/test-PLAN-004-deploy.sh` (delete if present)
- `website/docs/getting-started.md`
- `website/docs/contributors/target-layout-reference.md`
- `website/docs/contributors/lib-service-v2.md` (document the 3 new helpers)

---

## Implementation Notes

### Why `is_first_time_deploy` returns exit code, not stdout

`if is_first_time_deploy "$svc"; then ...` reads naturally in bash. Predicate helpers conventionally use exit code. The function doesn't emit anything user-visible — it's a decision input, not an observation.

### Why a `--no-chain` escape hatch is low priority

The four-pipeline chain is brittle in theory (one pipeline can fail mid-flight, leaving a half-deployed state). In practice, each pipeline is idempotent — re-running from step 1 doesn't break anything. So the recovery story is "just re-run `noclickops deploy <svc> <env>`" — detection figures out where we are based on which pipelines have ever succeeded.

`--no-chain` only matters when a user *knows* one of the earlier steps already succeeded (don't want to re-run it) AND the chain logic can't detect that. The detection in v1 of PLAN-C is binary (any successful deploy-test → subsequent path). Step-level resume is a refinement we can add when there's actual demand.

### Why `bin/deploy.sh` is the right place for the orchestration loop (not a new lib)

The orchestration is specific to deploy — `info` / `logs` / `shell` don't trigger pipelines. Putting the `for step in build deploy infra-build deploy-test; do trigger + watch; done` loop in `bin/deploy.sh` keeps the lib focused on reusable primitives (`trigger_pipeline`, `watch_run`) rather than command-specific flow.

### Why `--watch-live` is a separate plan

`--watch-live` adds DNS / cert / HTTPS polling on TOP of the pipeline orchestration. It's a follow-on capability that only matters for first-time public-endpoint deploys. Bundling it into PLAN-C would balloon scope and conflate two different watch primitives (pipeline status vs HTTPS reachability). See [PLAN-watch-live-deploy.md](../backlog/PLAN-watch-live-deploy.md) for the dedicated plan.

### Out of scope for PLAN-C

- `--watch-live` (separate plan; PLAN-C provides the hook by printing "Front Door + cert ~30-90 min" hint).
- Step-level resume / `--from-step N` flags.
- Triggering deploys against arbitrary branches (v2 stays on `refs/heads/main` like v1).
- Rollback workflow (not in the investigation; separate concern).
- Parallel pipeline execution (the chain is inherently serial — each step's artifact feeds the next).
