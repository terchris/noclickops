---
title: v2 smoke test
sidebar_position: 3
---

# v2 smoke test

The release gate for promoting any v2.x version to **2.0.0**, and the regression checklist for every v2.x release thereafter.

**What this is:** an explicit pass/fail checklist that exercises every v2 command against a real new-layout target repo. Each step has a strict `Result must show:` line so two different runners reach the same verdict.

**What this is not:** a tutorial. For new-user onboarding, see [Getting started](/docs/getting-started). This doc assumes the runner has installed noclickops, is logged in to Azure, has access to the target repo, and has permission to merge PRs in both projects.

**Timing:** the **mandatory** path (phases 1-4, internal-only service) completes in **~15-20 min**. The **optional** public-endpoint path (phase 6) adds **30-90 min** of waiting for Front Door custom-domain validation + DNS + managed cert — kick it off async; check back in an hour. **Never block the mandatory smoke on the public-endpoint wait.**

---

## Prerequisites

- noclickops installed and current: `~/.noclickops/version.txt` matches the version under test (run `noclickops update` first).
- `az login` succeeded for the target's ADO tenant.
- Reader on the IaC-declared deployment subscription (for `info` live state + `logs` + `shell`).
- Pipeline-run + PR-merge permission in BOTH the source project AND the IaC project (for `add-service` + `deploy`).
- Local clone of the target new-layout repo. Default for this run: `/Users/terje.christensen/learn/redcross/TCH900001-mrkmedlem`.
- An existing service in the repo to use for read-only checks (e.g. `frontend`).

Pick a unique service name for the mutating tests, e.g. `smoketest-YYYYMMDD-HHMM` (date+time keeps re-runs from colliding).

```bash
export TARGET_REPO=/Users/terje.christensen/learn/redcross/TCH900001-mrkmedlem
export EXISTING_SVC=frontend
export NEW_SVC=smoketest-$(date +%Y%m%d-%H%M)
cd "$TARGET_REPO"
```

---

## Phase 1: Read-only checks (no mutation, safe to repeat)

### 1.1 Version + lister

```bash
noclickops
```

**Result must show:**
- Header line includes `v<expected-version>` (e.g. `v1.6.0` for the 1.6.0 smoke).
- Five grouped sections: Meta / Git / Deployment / Service lifecycle / Inspect.
- 12 commands total.

### 1.2 `--help` renders v2 metadata for every command

```bash
for cmd in info logs shell deploy add-service clean-sample; do
  echo "=== $cmd ==="
  noclickops $cmd --help | head -5
done
```

**Result must show:** for each command, the description line is the v2 wording (e.g. `info` mentions `config.<env>.yaml`, `add-service` mentions "auto-merge BOTH PRs", `deploy` mentions "v2 multi-pipeline orchestration", `clean-sample` mentions "Hello-World stub").

### 1.3 `status` against the target repo

```bash
noclickops status
```

**Result must show:** Table with recent pipeline runs (id, name, status, result, time). At least one row. Exit 0.

### 1.4 `info <existing-svc> test` — static block

```bash
noclickops info "$EXISTING_SVC" test
```

**Result must show:**
- `Service: <existing-svc> (test)` header.
- `IaC repo (engineer-owned):` section with non-empty `App name (IaC):`, `Subscription:`, `Common RG:`, `DNS zone:`.
- `Service config:` section with numeric `Port:`, `CPU:`, etc.
- For a public service: `Public URL: https://<svc>.<dns-zone>` line.
- `Live state (Azure):` section either populated (`Container app: ca-<repo-prefix>-<svc>`, `Status:`, `Latest revision:` etc.) OR the `(live state unavailable — set SVC_APP_NAME_OVERRIDE ...)` message. Either is a pass — the gate is "static printed in full + live degrades cleanly".
- Exit 0 in BOTH cases (info degrades, never gates).

### 1.5 `info <existing-svc> test` against missing service

```bash
noclickops info nonexistent-service-xyz test
```

**Result must show:** clear `config.test.yaml not found` error. Exit 1.

### 1.6 `logs <existing-svc> test --tail 5`

```bash
noclickops logs "$EXISTING_SVC" test --tail 5
```

**Result must show one of:**
- 5 log lines streamed, exit 0 (if user has Reader on the sub).
- `AuthorizationFailed` / `(no container app found)` / `set SVC_APP_NAME_OVERRIDE` error, exit 1. This is the gate — `logs` fails closed, doesn't degrade.

### 1.7 `shell <existing-svc> test --command "echo hello"`

```bash
noclickops shell "$EXISTING_SVC" test --command "echo hello"
```

**Result must show:** either `hello` printed (exit 0) OR a clear gating error (exit 1). Same gate semantics as logs.

---

## Phase 2: Mutating — `add-service` two-PR flow (internal-only)

> **Always internal-only for the smoke.** The v2 default `public_endpoint=false` is what we want here. Do NOT pass `--public-endpoint` — that triggers Front Door + cert provisioning that takes 30-90 min and would block the test. The public-endpoint path is exercised separately in Phase 6 (async).

### 2.1 Trigger + auto-merge

```bash
noclickops add-service "$NEW_SVC"
```

This is the big one. Expected duration: ~3-5 min (pipeline ~1 min + PR-A appears ~1-2 min + PR-B appears ~1-3 min after PR-A merge).

**Result must show, in order:**
1. `Triggering 'ABC100001-myservice-add-service' to scaffold '<NEW_SVC>'` log line.
2. `persistent_storage=false  public_endpoint=false` in the params line.
3. `Started run <id>` with a `dev.azure.com` URL.
4. `Pipeline succeeded`.
5. `Found PR-A #<id>`, then `PR #<id> completed`.
6. `Found PR-B #<id>`, then `PR #<id> completed`.
7. Final `Done. services/<NEW_SVC> is on main.` block.
8. `Source PR #<a> merged; infrastructure PR #<b> merged.` summary line.
9. Exit 0.

**Verify in Azure DevOps:**
- Source repo PRs page shows the `add-service-<NEW_SVC>` PR as Completed.
- `IaC/platform-infrastructure` PRs page shows `Add service <NEW_SVC>` as Completed.

### 2.2 Local state after add-service

```bash
ls services/$NEW_SVC/
cat services/$NEW_SVC/config.test.yaml
```

**Result must show:**
- `Dockerfile`, `README.md`, `app/`, `config.test.yaml`, `config.prod.yaml`, `.pipelines/` all present.
- `config.test.yaml` has `ENABLE_PUBLIC_ENDPOINT: "false"` (default we passed).

---

## Phase 3: Mutating — `clean-sample` BEFORE the first deploy

Run `clean-sample` first so the deploy ships the minimal Express + `/health` stub instead of the heavier OIDC starter. Smaller Docker image, faster build, no OIDC machinery to fail — exercises the noclickops orchestration without bringing real-app concerns into the smoke.

### 3.1 Strip the OIDC starter

```bash
noclickops clean-sample "$NEW_SVC"
```

**Result must show:**
- `Replacing the Express+OIDC sample in services/<NEW_SVC>/app/`.
- `rewrote services/<NEW_SVC>/app/server.js`.
- `rewrote services/<NEW_SVC>/app/package.json`.
- Exit 0.

### 3.2 Verify the stub

```bash
cat services/$NEW_SVC/app/server.js
cat services/$NEW_SVC/app/package.json
```

**Result must show:**
- `server.js` is the ~10-line minimal Express stub (no `OKTA_CLIENT_SECRET` string).
- `package.json` has only `"express"` in dependencies (no `express-session`, no `openid-client`).

### 3.3 Commit the cleaned sample

```bash
git add services/$NEW_SVC/app/server.js services/$NEW_SVC/app/package.json
git commit -m "smoke: minimal Express stub in $NEW_SVC"
git push
```

The deploy pipeline builds from the source repo at HEAD, so the clean-sample change has to land before triggering deploy.

### 3.4 Idempotent re-run

```bash
noclickops clean-sample "$NEW_SVC"
```

**Result must show:** `is already minimal — nothing to do.` Exit 0.

---

## Phase 4: Mutating — `deploy` first-time chain

### 4.1 Detection: first-time path triggers

```bash
noclickops deploy "$NEW_SVC" test
```

Expected duration: ~10 min (4 pipelines in sequence: build ~1-2m + deploy ~30s + infra-build ~3m + deploy-test ~6m).

**Result must show, in order:**
1. `Deploying '<NEW_SVC>' → 'test' (FIRST-TIME — full chain, ~10 min)`.
2. `[1/4] ABC100001-myservice-<NEW_SVC>-build` line, then `run <id> ... succeeded (Xm Ys)`.
3. `[2/4] ABC100001-myservice-<NEW_SVC>-deploy` line, then `run <id> ... succeeded (Xm Ys)`.
4. `[3/4] ABC100001-myservice-<NEW_SVC>-infra-build` line, then `run <id> ... succeeded (Xm Ys)`.
5. `[4/4] ABC100001-myservice-<NEW_SVC>-deploy-test` line, then `run <id> ... succeeded (Xm Ys)`.
6. `Deploy complete.` block with `Container app: ca-abc100001-<NEW_SVC> (rg-test-myteam-frontend-common)`.
7. `(no public endpoint configured for this service)` — since we used internal-only default.
8. Exit 0.

### 4.2 Verify deployment in Azure

```bash
noclickops info "$NEW_SVC" test
```

**Result must show:** `Live state (Azure):` section populated with the new container app — `Container app: ca-abc100001-<NEW_SVC>`, `Status: Running`, `Latest revision:`, `Image: acrshareduw.azurecr.io/abc100001/<NEW_SVC>:...`, replica counts.

### 4.3 Logs from the new service

```bash
noclickops logs "$NEW_SVC" test --tail 20
```

**Result must show:** at least 1 log line from the minimal Express stub (`Listening on port 3000`). Exit 0.

### 4.4 Detection: subsequent path on re-run

```bash
noclickops deploy "$NEW_SVC" test
```

**Result must show:**
- `Deploying '<NEW_SVC>' → 'test' (subsequent run, resource trigger expected)`.
- `[1/1]` (NOT `[1/4]`) — confirms detection picked the subsequent path.
- `ABC100001-myservice-<NEW_SVC>-deploy run <id> ... succeeded`.
- Exit 0.

---

## Phase 5: Public-endpoint smoke (OPTIONAL, async — 30-90 min wait)

Skip this phase unless you specifically want to verify the public-endpoint deploy path. Use a SECOND service name (don't reuse `$NEW_SVC` from phases 2-4):

```bash
export PUBLIC_SVC=smoketest-pub-$(date +%Y%m%d-%H%M)
noclickops add-service "$PUBLIC_SVC" --public-endpoint
noclickops deploy "$PUBLIC_SVC" test
```

After deploy succeeds (~10 min), the container app exists but the public URL is NOT yet live — Front Door custom-domain validation + DNS propagation + managed-cert issuance is still happening. **DO NOT WAIT.** Move on, check back in 60 min:

```bash
# After ~60 min:
curl -sI https://$PUBLIC_SVC.example.cloud/health
# Expect: HTTP/2 200 with x-azure-ref header (proves Front Door routing works)
```

**Pass criteria for phase 6:** HTTPS-200 within 90 min of `deploy` completing. If it's not live after 90 min, that's a Front Door / DNS problem (engineer-owned, not noclickops). Don't fail the noclickops smoke on it — file a separate issue against the platform team.

When `noclickops deploy --watch-live` ships (see [PLAN-watch-live-deploy](/docs/ai-developer/plans/backlog/PLAN-watch-live-deploy)), this phase becomes "run `noclickops deploy <svc> test --watch-live` and wait for the success line" — no manual poll needed.

---

## Phase 6: Cleanup (optional but recommended)

The smoke-test service shouldn't accumulate in real environments. After the run:

```bash
# 1. Delete the container app from Azure (manual via Portal or):
#    az containerapp delete -n ca-abc100001-$NEW_SVC -g rg-test-myteam-frontend-common --yes
#
# 2. Revert local changes:
git checkout main
git pull
#    services/$NEW_SVC/ now reflects what's on main (the merged add-service + clean-sample).
#    Decide whether to remove the smoke service from main with a follow-up PR, or leave it.
```

---

The smoke-test service shouldn't accumulate in real environments. After the run:

```bash
# 1. Delete the container app from Azure (manual via Portal or):
#    az containerapp delete -n ca-abc100001-$NEW_SVC -g rg-test-myteam-frontend-common --yes
#
# 2. Revert local changes:
git checkout main
git pull
#    services/$NEW_SVC/ now reflects what's on main (the merged add-service + clean-sample).
#    Decide whether to remove the smoke service from main with a follow-up PR, or leave it.
```

---

## Verdict template

After running through phases 1-4, fill in:

```text
Run date:         YYYY-MM-DD HH:MM
noclickops version: 1.6.0  (or under test)
Target repo:      /path/to/repo
NEW_SVC used:     smoketest-YYYYMMDD-HHMM

Phase 1 (read-only):                  PASS | FAIL  (notes: ...)
Phase 2 (add-service internal):       PASS | FAIL  (notes: ...)
Phase 3 (clean-sample):               PASS | FAIL  (notes: ...)
Phase 4 (deploy first-time + sub):    PASS | FAIL  (notes: ...)
Phase 5 (public-endpoint, OPTIONAL):  PASS | FAIL | NOT-RUN  (notes: ...)

Overall (mandatory phases 1-4): PASS | FAIL

If PASS for 1.6.0 → safe to bump to 2.0.0 in a follow-up commit.
If FAIL → file a regression as PLAN-fix-<short-name> on the v2 patch path.

Phase 5 NOT-RUN is acceptable for routine smokes; full verdict still PASS.
```

---

## Run history

(Each smoke run appends a result block here. Most recent at the bottom.)

{/* Append blocks below this comment. Most recent at the bottom. Template:

### 1.6.0 — 2026-05-29 — runner: Terje

- Phase 1: PASS
- Phase 2: PASS (PR-A #X, PR-B #Y both merged in ~3 min)
- Phase 3: PASS (4-pipeline chain ~9m12s)
- Phase 4: PASS

Verdict: PASS — clear to bump 1.6.0 → 2.0.0.
*/}
