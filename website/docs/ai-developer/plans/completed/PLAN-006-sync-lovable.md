# PLAN-006: `sync-lovable` + `templates/lovable/`

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-28

**Goal**: Bring a Lovable (Vite/React/PWA) project into a service folder and leave it deployable — re-runnable, with the build container + nginx config rendered from noclickops-owned templates, and `health.json` recording the source's exact commit.

**Last Updated**: 2026-05-28

**Investigations**:

- [INVESTIGATE-noclickops.md](../backlog/INVESTIGATE-noclickops.md) → "Outline of v1 PLANs" → PLAN-006

**Depends on**: PLAN-001 (`lib/` + metadata + `TEMPLATES_DIR`).

**Priority**: High — this is the bridge that lets a Lovable app become an FRT-deployable service. Without it, every new Lovable service is a hand-built integration.

---

## Problem

A Lovable repo is a fully self-contained Vite/React/PWA app: `src/`, `public/`, `package.json`, `package-lock.json`, `.env` with `VITE_*` build-time vars. It needs none of FRT's platform scaffolding to run on lovable.dev, but it can't ship as-is to Azure Container Apps — it needs:

1. A `Dockerfile` that runs `npm ci && npm run build` then serves `/dist` via nginx on port 3000.
2. An `nginx.conf` with the SPA-fallback fix (no `$uri/` to dodge the `/parties` 301 redirect from PWA service-worker territory).
3. A `/health` endpoint nginx serves out of a static `health.json` file — with the source repo URL, commit SHA, and commit date so the live `/health` doubles as a deployed-version stamp.
4. Repeatable sync — the developer pulls Lovable changes upstream, runs one command, the target service folder is up to date.

The FRT repo already has `website/scripts/sync-lovable.sh` + `templates/lovable/{Dockerfile,nginx.conf}` doing this. PLAN-006 ports it into noclickops so it works in any FRT-shaped repo.

---

## What it delivers

### `templates/lovable/Dockerfile` and `templates/lovable/nginx.conf`

Carried over from FRT — the two files PLAN-001 left `templates/.gitkeep`-shaped space for. nginx.conf includes the `/parties` SPA-redirect fix and the `/health` alias to `health.json`. Comment headers updated to reference `noclickops sync-lovable` (not FRT's stale PLAN-002 ref).

### `bin/sync-lovable.{sh,ps1}`

```text
noclickops sync-lovable <lovable-repo-path> <service>
```

Five-step flow (matches FRT's proven sequence):

1. **Validate**: source is a git repo; service folder exists and has `service.yaml`; `rsync` on PATH; source has a `package.json` containing `lovable-tagger` (the Lovable signature); source has an `origin` remote (needed for `health.json`).
2. **Pull source**: `git -C <src> pull --ff-only`. Bail on conflicts.
3. **Post-pull guards**: require `package-lock.json` (v1 builds with npm); warn (don't fail) if the source working tree is dirty — the mirror copies uncommitted edits, but `health.json` only records HEAD, so the deployed code can diverge from what `/health` claims.
4. **Mirror frontend**: `rsync -a --delete` from source into `services/<service>/`, **excluding** node_modules, .git, dist, dist-ssr, .github, supabase, scripts, .lovable, bun.lock(b), AND **the noclickops-managed paths**: `/Dockerfile`, `/service.yaml`, `/.pipelines`, `/bicep`, `/nginx.conf`, `/health.json`. The Lovable `README.md` mirrors through. After mirror, assert the platform scaffolding survived.
5. **Render templates + write health.json**: copy `$TEMPLATES_DIR/lovable/{Dockerfile,nginx.conf}` over to the service folder (overwrite every run); generate `health.json` with `{ source: { repo, commit, commit_date } }` from `git -C <src> rev-parse --short HEAD` + `log -1 --format=%cI`.

### PowerShell port

**Status: deferred (v1 limitation)**. The rsync exclusion semantics are non-trivial to reproduce in `robocopy` or `Copy-Item` without a real test surface. `bin/sync-lovable.ps1` ships as a stub that errors with: *"sync-lovable v1 requires bash — run from Git Bash or WSL"*. The Bash version works in WSL/Git Bash so Windows users aren't locked out, just steered to bash for this one command.

---

## Phases

1. Copy `templates/lovable/{Dockerfile,nginx.conf}` from FRT; rewrite comment headers.
2. `bin/sync-lovable.sh` — full port from FRT's working implementation.
3. `bin/sync-lovable.ps1` — stub.
4. Smoke test:
   - `--help` prints metadata block.
   - Lister shows it under "Service lifecycle".
   - Missing args → usage error.
   - Non-Lovable source (no `package.json` / no `lovable-tagger`) → distinct errors.
   - Source repo without `origin` remote → clear error.
   - Missing or non-service target folder → error.
   - **End-to-end against a fake source + target**: source files mirrored, `node_modules`/`.git`/`dist` excluded, platform scaffolding preserved, templates rendered with current content, `health.json` populated with the right source URL + commit SHA + commit date.

---

## Validation criteria

- After running against a fake Lovable + fake service:
  - `services/<svc>/src/`, `public/`, `package.json`, `package-lock.json`, `index.html`, `README.md` all present (from source).
  - `services/<svc>/node_modules/`, `.git/` NOT present (rsync excluded).
  - `services/<svc>/Dockerfile`, `service.yaml`, `.pipelines/`, `bicep/` preserved.
  - `services/<svc>/nginx.conf` content matches `templates/lovable/nginx.conf`.
  - `services/<svc>/health.json` is valid JSON with `source.repo` = source's origin URL (`.git` stripped), `source.commit` = short SHA, `source.commit_date` = ISO 8601 date.
- Re-running the script is idempotent: second run produces the same result (after a no-op pull).
- Portability grep stays clean.

---

## Completion notes (2026-05-28)

All four phases shipped on `feature/ai-developer-bootstrap`.

**Smoke test** (against a fake Lovable source repo + bare remote + fake target service):

| # | Test | Result |
| --- | --- | --- |
| 1 | Lister shows new "Service lifecycle" entry alongside `clean-sample` | ✅ |
| 2 | `sync-lovable --help` prints metadata block | ✅ |
| 3 | No-arg call → usage error | ✅ |
| 4 | Source path not a git repo → "Not a git repo" | ✅ |
| 5 | Source missing `package.json` → "not a Lovable repo (no package.json)" | ✅ |
| 6 | Source has `package.json` but no `lovable-tagger` → distinct error | ✅ |
| 7 | Target's `services/<name>/` missing → "No such service folder" | ✅ |
| 8 | Full end-to-end sync runs all 5 phases (pull, mirror, templates, health.json) | ✅ |
| 9 | All 7 expected source files present; `node_modules` + `.git` excluded; `Dockerfile/service.yaml/.pipelines/bicep` preserved; `Dockerfile` overwritten by template (not source's `"old dockerfile"`); `nginx.conf` carries the `/parties` SPA fix | ✅ |
| 10 | `health.json` is valid JSON: `status: ok`, `source.repo` = origin URL with `.git` stripped, `source.commit` = 7-char short SHA, `source.commit_date` = ISO 8601 with timezone | ✅ |
| 11 | Re-run is idempotent: `Already up to date` then full sync overlay | ✅ |
| 12 | Dirty source tree fires the documented `⚠` warning (uncommitted changes vs HEAD) | ✅ |
| 13 | PS stub file authored; static check confirms it errors with bash-required message | ✅ (PS execution unverified — no `pwsh` on Mac) |

**Test-infrastructure bug** found and fixed mid-run: the first attempt did `mktemp -d` for `SRC_BARE` and tried `git -C "$SRC_BARE" init -q --bare` — but `mktemp -d` returns a parent dir, so `$SRC_BARE=$(mktemp -d)/lovable.git` named a leaf that didn't exist yet. Switched to `git init --bare -q "$SRC_BARE"`, which creates the leaf itself.

**Behavioral note carried forward**: `health.json`'s `source.repo` strips the trailing `.git` from the origin URL. Matches FRT's existing behavior — produces the form a developer would paste into a browser. The test's first Python assertion expected the literal URL; it was wrong, the script is right.

**PowerShell port deferred** with explicit rationale in `bin/sync-lovable.ps1` header: rsync's exclude/delete semantics don't map cleanly to `robocopy` or `Copy-Item`, and risk silent data loss if implemented incorrectly. Windows users run the `.sh` via Git Bash or WSL. Native PS port is a future PLAN.

**Templates carried over from FRT**: `Dockerfile` (multi-stage `node:20-alpine` build → `nginx:alpine` serve) + `nginx.conf` (port 3000, `/health` alias, PWA no-cache for `sw.js`/`manifest`, hashed-assets immutable cache, SPA fallback without `$uri/` to avoid the `/parties` 301 redirect). Comment headers rewritten to reference `noclickops sync-lovable` (PLAN-006).
