# PLAN-005: `clean-sample` — strip the Next.js Copier sample

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-28

**Goal**: A pure-local command to remove the Next.js sample app from a freshly Copier-scaffolded service folder, keeping the platform scaffolding (`Dockerfile`, `service.yaml`, `.pipelines/`, `bicep/`).

**Last Updated**: 2026-05-28

**Investigations**:

- [INVESTIGATE-noclickops.md](../backlog/INVESTIGATE-noclickops.md) → "Outline of v1 PLANs" → PLAN-005

**Depends on**: PLAN-001 (lib/ + metadata).

**Priority**: Medium — used once per new service; not blocking the higher-frequency commands.

---

## Problem

After Copier scaffolds a new service in the FRT-shaped monorepo, the folder contains a placeholder Next.js sample app (`app/`, `components/`, `public/`, `package.json`, …) alongside the platform scaffolding the developer must keep. The first thing a developer does in a new service is delete the sample — by hand, every time, and it's easy to either delete too much (lose `Dockerfile`/`service.yaml`) or leave stragglers.

The FRT repo already has a `website/scripts/clean-sample.sh` that does this cleanly. PLAN-005 ports it into noclickops so it's available in any FRT-shaped repo, not just FRT.

---

## What it delivers

### `bin/clean-sample.{sh,ps1}`

```text
noclickops clean-sample <service>
```

Behaviour:

- Resolves the target repo from `pwd`; refuses to run outside a git repo.
- Validates `services/<service>/` exists.
- **Safety guard**: only auto-deletes when the folder looks like an **unmodified Next.js Copier sample** — detected by the presence of `components/control-panel.js` (a file unique to the template). If sample-like files exist but the control-panel marker is missing, **refuses** and tells the user to delete manually.
- If neither marker nor any sample file exists: prints "already clean" and exits 0.
- For each sample path that exists:
  - If git-tracked: `git rm -rq` (stage the deletion).
  - If untracked: plain `rm -rf`.
- Reports what was kept and prints next-step guidance.

### Sample file list (FRT-shaped repos, v1)

```text
app/                  components/         public/
package.json          package-lock.json   next.config.mjs
```

### What this PLAN does NOT do

- Doesn't commit. The developer commits explicitly so the diff is reviewable.
- Doesn't scaffold the new app (`sync-lovable` in PLAN-006 covers that for Lovable apps).
- Doesn't generalize beyond the Next.js Copier template. Future templates (Astro, plain Node) will need their own `clean-<name>` or a config-driven approach.

---

## Phases

1. `bin/clean-sample.{sh,ps1}`.
2. Smoke test:
   - `--help` prints the metadata block.
   - Lister now shows the "Service lifecycle" section.
   - Missing service → usage error.
   - Unknown service → not-found error.
   - Service folder with no sample files → "already clean" exit 0.
   - Service folder with sample files but no `control-panel.js` marker → refusal.
   - Service folder with full intact sample → all six sample paths removed, platform scaffolding (Dockerfile, service.yaml, .pipelines/) intact, deletions staged in git.

---

## Validation criteria

- Pure-local: no `az`/`gh` calls anywhere in the script.
- The script refuses to delete when the safety marker is missing.
- The intact-sample case stages git deletions correctly for tracked files and removes untracked files outright.
- Portability grep stays clean (no `JKL900X016` / `ExampleOrg` / `FrontendPlatform`).

---

## Completion notes (2026-05-28)

Single-phase ship on `feature/ai-developer-bootstrap`.

**Smoke test** (against a temp git repo with 3 services: `svc-intact`, `svc-clean`, `svc-realcode`):

| # | Test | Result |
| --- | --- | --- |
| 1 | Lister shows new "Service lifecycle" section with `clean-sample` | ✅ |
| 2 | `clean-sample --help` prints metadata block | ✅ |
| 3 | No-arg call → usage error | ✅ |
| 4 | Outside any git repo → "Not inside a git repository" | ✅ |
| 5 | Unknown service → "No such service folder: services/ghost" | ✅ |
| 6 | Service with zero sample files → "is already clean" exit 0 | ✅ |
| 7 | Service with sample files but no `control-panel.js` marker → safety refusal; files **left untouched** (verified via `ls` after refusal) | ✅ |
| 8 | Intact sample folder → all 6 sample paths removed; `Dockerfile`, `service.yaml`, `.pipelines/` kept; tracked files (`components/control-panel.js`, `package.json`) staged as `D` in git index; untracked files (`app/`, `public/`, `package-lock.json`, `next.config.mjs`) removed outright | ✅ |
| 9 | Portability grep clean | ✅ |

**No bugs found during testing.**

**Tracked-vs-untracked dispatch** is the subtlest part and it's clean: `git ls-files --error-unmatch <path>` returns non-zero for untracked, so the `if` branch picks `git rm -rq` only for tracked items; untracked files take the `rm -rf` branch and never touch the git index.

**No `az`/`gh` in this script** — pure local. PLAN-005 is the smallest of the remaining commands and a good shakedown that the metadata + lib pattern works for non-cloud scripts too.
