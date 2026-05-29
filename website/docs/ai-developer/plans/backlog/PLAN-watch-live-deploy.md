# PLAN: `noclickops deploy --watch-live` — poll a deploy until the public endpoint is reachable

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Backlog

**Goal**: Add a `--watch-live` flag to `noclickops deploy` that polls the full deployment chain (pipeline → downstream → container app → ingress → firewall → DNS → HTTPS) and reports progress until the public endpoint actually serves traffic. Covers the case the Azure engineer flagged: first-time deploys of public-endpoint services take ~1 hour while the firewall/WAF registers the new hostname.

**Last Updated**: 2026-05-29

**Investigation**: [INVESTIGATE-new-target-structure.md](../completed/INVESTIGATE-new-target-structure.md) — this PLAN is filed during the empirical-test phase of that investigation; ships as part of v2's deploy command or as a follow-up patch.

**Prerequisites**: v2 deploy command in place (the layout-aware version targeting `<repo>-<svc>-deploy`).

---

## Problem

A `deploy` with `--watch` today polls the ADO pipeline run until completion. With the new layout, the deploy pipeline finishes in ~30s — it just publishes a `deployment-package-{env}` artifact. The actual deployment happens in a downstream system; for first-time public-endpoint services, the user-visible "ready" state can be **~60 minutes** later, after:

1. Downstream picks up the request (seconds–minutes).
2. Container App created in Azure (~1–5 min).
3. Ingress + cert provisioned (~5–15 min).
4. **Firewall / WAF registers the new hostname (~30–60 min — the bottleneck).**
5. DNS propagates (~5–10 min after firewall accepts).

The user has no single command to wait for all of this. They `noclickops deploy --watch`, see "succeeded" after 30s, then have to manually poll `dig` / `curl` for the next hour.

---

## What it delivers

### `noclickops deploy <svc> [test|prod] --watch-live`

Triggers the deploy pipeline (same as `--watch`), then polls in layers until the public endpoint serves traffic OR the user Ctrl-Cs.

**Progress output** (one line per state change):

```text
✓  17:23:01  Deploy pipeline 'ABC100001-myservice-frontend-deploy' run 12345 queued.
✓  17:23:31  Deploy pipeline succeeded.
✓  17:24:12  Downstream pipeline 'NRX.Infrastructure.Shared - CD' run 4567 picked up the request.
✓  17:27:48  Container app 'frontend-test' provisioningState: Succeeded (rg: rg-frontend-test-euw).
⏳ 17:35:00  Waiting for ingress... (probing https://frontend.example.cloud/health)
⏳ 17:55:00  Waiting for ingress... (HTTP 503 — firewall registration in progress)
⏳ 18:15:00  Waiting for ingress... (HTTP 503)
✓  18:23:14  DNS resolved: frontend.example.cloud → 20.117.x.x
✓  18:24:02  HTTPS endpoint live: https://frontend.example.cloud/health → 200 OK (total wait: 1h 1m).
```

**Polling cadence**:
- Pipeline state: every 5s for first 2 min, every 15s after.
- Container App `provisioningState`: every 30s once the downstream pipeline succeeds (if Azure Reader access is present).
- DNS + HTTPS probes: every 60s after container app reaches `Succeeded`.

**Configurable timeout**:
- `--watch-live-timeout 90m` (default 90 min — gives the firewall step its ~60 min plus headroom).
- On timeout: prints current state of every layer + exits non-zero with "Endpoint not live after 90m; check `noclickops info <svc> <env>` for live state."

### What this PLAN does NOT do

- **No discovery of the downstream pipeline name.** Hardcoded for now to `NRX.Infrastructure.Shared - CD` (observed during the investigation). If the Azure engineer renames it, this stops working — re-discover empirically.
- **No deep Azure introspection.** The Container App probe uses only `az containerapp show --query "properties.{state:provisioningState, fqdn:configuration.ingress.fqdn}"`. Anything deeper (revision history, replica counts) belongs to `noclickops info`.
- **No retry of failed deploys.** If the pipeline or downstream fails, report the state + exit; user re-runs `noclickops deploy`.

---

## Phases (sketched — details deferred until v2 deploy is shipped)

1. **`lib/deploy-watcher.sh`** — layered state machine (pipeline → downstream → container app → ingress → DNS → HTTPS) with per-layer probes and graceful degradation when permissions are missing.
2. **`deploy.sh` integration** — `--watch-live` and `--watch-live-timeout` flags wired into the existing `deploy` command flow.
3. **Smoke test against a fresh public-endpoint service** — exercise the full ~1-hour path; record the actual cadence and tune polling intervals.
4. **Documentation** — add a section to the `deploy` per-command page on the docs site: "Use `--watch-live` for first-time public-endpoint services; expect ~60 min on a cold deploy."

---

## Open questions

- **Q1** Is the downstream pipeline name (`NRX.Infrastructure.Shared - CD` today) stable, or does it change per project / over time? If it changes, fold its discovery into the layout helper from PLAN-A.
- **Q2** Does the firewall/WAF expose any direct status endpoint we could poll (faster signal than HTTPS probing) — `az network front-door show` or similar? Defer until we know which firewall product is in use.
- **Q3** Should `--watch-live` also work for non-public services? They skip the firewall + DNS step but still go through downstream + container-app provisioning. Probably yes — same code path, different "ready" condition.

---

## Out of scope

- Building this for the v1.x FRT layout — only ships as part of v2.
- A separate `noclickops wait <svc> <env>` command — covered by `--watch-live` on `deploy`.
- Failure / rollback handling — single happy-path polling; failures get reported, not remediated.
