# PLAN-E — `clean-sample` rewrite for v2

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Completed

**Goal**: Rewrite `bin/clean-sample.sh` to work against the new layout's Express + Okta OIDC starter template. Detect the unmodified template, replace `app/server.js` + `app/package.json` with a minimal "Hello World" Express stub that still passes Container Apps health probes. v1's Next.js detection logic is dropped along with FRT support.

**Last Updated**: 2026-05-29

**Completed**: 2026-05-29

### Completion notes

- `bin/clean-sample.sh` rewritten. v1's Next.js logic + `sample=(...)` deletion list gone. v2 uses a content marker (`"OKTA_CLIENT_SECRET are injected from Azure Key Vault at container"`) to detect the unmodified Express+OIDC template.
- Strip behaviour: replaces `app/server.js` with a ~10-line Express stub serving `/health`, replaces `app/package.json` with just the `express` dep. Service still deploys + passes Container Apps health probes.
- Idempotent: re-running on an already-minimal service (no marker AND < 30 lines) exits 0 with "already minimal".
- Safety: substantially-modified `app/server.js` (no marker AND ≥ 30 lines) triggers a clear refusal. Files untouched.
- Engineer-owned scaffolding (`Dockerfile`, `config.<env>.yaml`, `.pipelines/`, `README.md`) never touched.
- `tests/_fixtures.sh`: added `scaffold_v2_oidc_sample` helper that writes the real OIDC template content (matches what `copier-add-service` produces).
- `tests/test-PLAN-005-clean-sample.sh` deleted. `tests/test-PLAN-E-clean-sample.sh` added (32 asserts): help / no-args / outside-repo / missing-service / no-app / happy path (incl. specific assertions for OIDC removed + express retained + scaffolding preserved + git staging) / idempotency / modified-file refusal.
- Total tests: 430 → 434 passing, 0 failed.
- Branch stays `feat/v2-new-target-structure`. Per CLAUDE.md PR-per-investigation rule.

**Investigation**: [INVESTIGATE-new-target-structure.md](INVESTIGATE-new-target-structure.md) (see § "Per-command impact → clean-sample" and § "PLAN sequence → PLAN-E")

**Prerequisites**: none — `clean-sample` is a pure file-manipulation command, no lib/service-v2.sh dependency.

**Branch**: same as PLAN-A/B/C/D — `feat/v2-new-target-structure`.

---

## Overview

v1's `clean-sample` stripped a Next.js demo (`components/control-panel.js`, `app/page.js`, etc.) — a throwaway sample that nobody wants to keep.

The new layout's template (per the engineer's `services/<svc>/README.md`) is fundamentally different: it's a **useful starting point** with Express + express-session + openid-client wired up for Okta OIDC. The README explicitly says "Add your application routes and logic to `app/server.js`" — the template is designed to be edited in place, not stripped.

But many services aren't OIDC-protected (postgrest, internal APIs, public landing pages). For those, the OIDC scaffolding is dead weight + extra deps. `clean-sample` v2's job is to give those services a clean slate:

- **Detect** the unmodified Express+OIDC template via a content marker.
- **Replace** `app/server.js` with a minimal Express app that exposes `/health` on `PORT` (or 3000) — preserves Dockerfile compatibility, deploy still works.
- **Replace** `app/package.json` with just `express` (drop `express-session` + `openid-client`).
- **Refuse** if the template has been modified — don't risk overwriting real code.

Everything else in the service folder (`Dockerfile`, `config.{test,prod}.yaml`, `.pipelines/`, `README.md`) is platform scaffolding owned by the engineer — `clean-sample` does NOT touch any of it.

---

## What the v2 stub looks like

After `noclickops clean-sample <svc>`, the service folder is:

```text
services/<svc>/
  Dockerfile               # unchanged — still copies app/package.json + app/server.js
  config.test.yaml         # unchanged
  config.prod.yaml         # unchanged
  README.md                # unchanged
  .pipelines/              # unchanged
    service.yaml
    deploy_service.yaml
  app/
    server.js              # REPLACED — minimal Express + /health
    package.json           # REPLACED — only `express` dep
```

### New `app/server.js` (~15 lines)

```js
const express = require('express');

const app = express();
const port = process.env.PORT || 3000;

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.listen(port, () => {
  console.log(`Listening on port ${port}`);
});
```

### New `app/package.json`

```json
{
  "name": "service",
  "version": "1.0.0",
  "scripts": { "start": "node server.js" },
  "dependencies": { "express": "^4.18.3" }
}
```

Result: service is the smallest possible thing that deploys + passes health probes. User adds their real code from there.

---

## Detection: content marker

v1 used a marker file (`components/control-panel.js`). The new template has no such throwaway file — every file is meant to be edited.

Content marker approach: `app/server.js` is considered unmodified if it contains the unique comment string:

```text
OKTA_CLIENT_SECRET are injected from Azure Key Vault at container
```

This comment is generated by the template and not something a developer would write after editing. If a developer has replaced or significantly altered `server.js`, this marker will be gone.

Edge cases:
- **Already stripped** (`server.js` doesn't contain the marker AND is short): print "Already minimal — nothing to do" + exit 0.
- **Marker missing but file is substantially different**: refuse with "Looks modified — refusing to overwrite. Edit `app/server.js` directly or remove it manually."
- **`app/` directory missing entirely**: error — this isn't a v2-layout service.

---

## Phase 1: Rewrite `bin/clean-sample.sh` — DONE

### Tasks

- [x] 1.1 Rewrite `bin/clean-sample.sh`:
  - Drop v1's `sample=(app components public package.json package-lock.json next.config.mjs)` list and the `components/control-panel.js` marker check.
  - Validate service folder exists: `services/<svc>/`. Error with a clear message if not.
  - Validate v2 layout: `services/<svc>/app/server.js` and `services/<svc>/app/package.json` exist. Error otherwise ("not a v2-layout service — does this repo use the new copier-add-service template?").
  - Check `app/server.js` for the OIDC content marker. If absent and the file is short (< 30 lines), print "Already minimal" and exit 0. If absent and the file is substantial, refuse with the modified-file message.
  - If marker present:
    - Replace `app/server.js` with the minimal Express stub.
    - Replace `app/package.json` with the minimal dependency set.
    - Stage both replacements in git (`git add` — they're modifications of tracked files).
    - Print summary: which files changed + "next: deploy with `noclickops deploy <svc> test`".
- [x] 1.2 Update metadata block:
  - `SCRIPT_DESCRIPTION`: "Replace the Express+OIDC sample with a minimal Hello-World stub."
  - `SCRIPT_DETAILS`: describe the v2 behavior (detection by content marker, what gets replaced, what stays).
  - `SCRIPT_TAGS`: drop "nextjs", add "express oidc minimal".
  - `SCRIPT_AUTH`: still "None."

### Validation

```bash
bash bin/clean-sample.sh --help
bash tests/run-all.sh
```

User confirms phase is complete.

---

## Phase 2: Tests — DONE

### Tasks

- [x] 2.1 Delete `tests/test-PLAN-005-clean-sample.sh` (v1 test).
- [x] 2.2 Update `tests/_fixtures.sh`: extend `make_v2_service` (or add `make_v2_service_with_oidc_sample`) to write the full OIDC template — `app/server.js` with the content marker, `app/package.json` with express/express-session/openid-client deps. Keep the existing minimal `make_v2_service` for tests that don't need the sample shape.
- [x] 2.3 Create `tests/test-PLAN-E-clean-sample.sh`. Cover:
  - `--help` renders v2 metadata.
  - No args → exit 1 + usage.
  - Missing service folder → clear error.
  - Service folder exists but no `app/` → "not a v2-layout service" error.
  - **Happy path**: unmodified OIDC template → both files replaced; new `server.js` contains "app.get('/health'"; new `package.json` has only the `express` dep; git status shows both files modified.
  - **Already-minimal path**: run twice in a row → second run exits 0 with "Already minimal".
  - **Modified-file refusal**: write a substantial custom `app/server.js` (no marker, > 30 lines) → exit 1 with the "modified" refusal message; files unchanged.
  - **Engineer scaffolding untouched**: assert `Dockerfile`, `config.test.yaml`, `config.prod.yaml`, `README.md`, `.pipelines/service.yaml` are unchanged after a strip.

### Validation

```bash
bash tests/run-all.sh
```

User confirms phase is complete.

---

## Phase 3: Docs sync — DONE

### Tasks

- [x] 3.1 Update `website/docs/getting-started.md`:
  - In the compatibility matrix, `clean-sample` flips from "Different sample shape; v2 refactor needed." to "**v2** — replaces the Express+OIDC template with a minimal Hello-World stub for services that don't need OIDC."
  - If there's a clean-sample example snippet, update to show the v2 behavior.
- [x] 3.2 Update `bin/clean-sample.sh`'s `SCRIPT_SEE_ALSO`: drop `sync-lovable` (PLAN-G if it ever happens). Reference `add-service` + `deploy` instead.

### Validation

```bash
cd website && npm run build
```

Build clean.

User confirms phase is complete.

---

## Acceptance Criteria

- [ ] `bin/clean-sample.sh` detects the v2 OIDC template via content marker
- [ ] Happy path: stripped service has minimal `app/server.js` + `app/package.json`, ready to deploy
- [ ] Platform scaffolding (`Dockerfile`, configs, `.pipelines/`, `README.md`) is untouched
- [ ] Refusal: modified `app/server.js` triggers a clear error; files unchanged
- [ ] Already-minimal idempotency: running twice doesn't break anything
- [ ] `tests/test-PLAN-E-clean-sample.sh` exists and passes; `tests/test-PLAN-005-clean-sample.sh` deleted
- [ ] `tests/run-all.sh` green
- [ ] `website/docs/getting-started.md` reflects v2-ready status for `clean-sample`

---

## Files to Modify

- `bin/clean-sample.sh` (rewrite)
- `tests/test-PLAN-005-clean-sample.sh` (delete)
- `tests/_fixtures.sh` (extend to include OIDC sample variant)
- `tests/test-PLAN-E-clean-sample.sh` (new)
- `website/docs/getting-started.md`

---

## Implementation Notes

### Why content marker over file hash

A SHA-256 of `app/server.js` would be precise but fragile — if the engineer updates the template (e.g. bumps express-session version, tweaks a comment), the hash changes and `clean-sample` stops recognizing valid samples. A long comment string is much more stable across template edits: as long as the OIDC-related comments stay roughly intact, detection works. If detection ever breaks because the template changes, the fix is a one-line marker update.

### Why the stub still uses Express (not just `http`)

The Dockerfile does `npm install --omit=dev` + `node server.js`. Stripping all deps would mean `npm install` does nothing and the Express require fails. Keeping `express` as the single dep gives the user a working app to deploy + iterate from. If they want pure-`http`, they can edit the two files manually — clean-sample isn't trying to be a templating engine.

### Why only the two files

`Dockerfile`, `config.*.yaml`, `.pipelines/`, `README.md` are platform scaffolding the Azure engineer owns. Stripping them would break the deploy contract. `clean-sample`'s job is to clear out the app code only — exactly the files the user is supposed to replace.

### Why not delete `app/` and let user start fresh

The Dockerfile expects `app/package.json` + `app/server.js` to exist. Deleting them breaks the build. Replacing them with minimal versions keeps the deploy chain working through to "Hello from your service" while removing all OIDC machinery.

### Out of scope for PLAN-E

- A `--minimal` flag (current default IS minimal).
- A `--keep-oidc` flag (just don't run clean-sample if you want to keep OIDC).
- Multi-service strip (`noclickops clean-sample --all`) — explicit per-service is safer.
- A separate command for stripping ONLY package.json deps (use the OIDC template + clean-sample, then add real deps back).
- Stripping inside a non-Express template (none exists yet in the new layout).
