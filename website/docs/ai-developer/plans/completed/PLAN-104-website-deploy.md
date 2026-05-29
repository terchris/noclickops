# PLAN-104: Deploy the Docusaurus site to GitHub Pages

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-29

Site live at [`https://noclickops.sovereignsky.no/`](https://noclickops.sovereignsky.no/).

**Goal**: Push every commit to `main` of the `website/` site to `https://noclickops.sovereignsky.no` via a GitHub Pages deploy. Adds the CI workflow, the `CNAME`, a placeholder favicon, and the one-time repo-settings smoke-test sequence. No new content — this PLAN is plumbing only.

**Last Updated**: 2026-05-29

**Investigation**: [INVESTIGATE-docusaurus.md](../backlog/INVESTIGATE-docusaurus.md) (realises rows A4 — deploy workflow — and the [Q4a] / [Q9b] decisions)

**Prerequisites**: PLAN-103 (the site must build before there's anything to deploy).

**Blocks**: PLAN-105 can technically run in parallel, but it's easier to validate PLAN-105's homepage / `commands.md` against a live URL than against `localhost:3000` alone.

**Priority**: Medium — gates a publicly viewable docs site.

**Branch**: `feat/v1.4.0-docusaurus` — same branch as PLAN-103 (already pushed by PLAN-104's smoke test) and PLAN-105 (per "PR per investigation" rule).

---

## Problem

After PLAN-103 the site builds locally but nothing reaches the public internet. Visitors who don't `git clone && npm install && npm start` see nothing. Q4a locked the public URL as `https://noclickops.sovereignsky.no`; the work to wire that up is:

1. A GitHub Actions workflow that builds + deploys on every `main` push.
2. A `CNAME` so GitHub Pages serves at the custom domain.
3. DNS pointing `noclickops.sovereignsky.no` → `terchris.github.io` (out-of-band; you do this in your DNS provider).
4. A one-time repo-settings toggle (Pages source = "GitHub Actions") that the workflow can't do for you.

DCT's [`deploy-docs.yml`](https://github.com/helpers-no/devcontainer-toolbox/blob/main/.github/workflows/deploy-docs.yml) is the reference; strip out the DCT-specific generator steps (`dev-logos.sh`, `dev-docs.sh`, `dev-cubes.sh`) — PLAN-105's `generate-docs.sh` would slot into the same position when it lands.

---

## What it delivers

### `.github/workflows/deploy-docs.yml`

DCT's shape, slimmed. Per [Q9b], **no path filter** — every push to `main` triggers a rebuild. Cheap CI minutes, simpler workflow file, no risk of forgetting to add a new path when the surface grows.

```yaml
name: Deploy Documentation

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: website/package-lock.json

      - name: Install dependencies
        working-directory: website
        run: npm ci

      - name: Build website
        working-directory: website
        env:
          GITHUB_ORG: ${{ github.repository_owner }}
          GITHUB_REPO: ${{ github.event.repository.name }}
        run: npm run build

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: website/build

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

Differences from DCT's file:

| Line / step | DCT | Here | Why |
|---|---|---|---|
| `paths:` filter under `on.push` | restricts to `website/**` + generator paths | **removed** | Q9b: every push to main rebuilds. |
| `Install image processing tools` step | `imagemagick librsvg2-bin webp` for `dev-logos.sh` | **removed** | No image processing in PLAN-104 (deferred to a future PLAN if we ever ship per-tool logos). |
| `Process logo assets` step | `bash .devcontainer/manage/dev-logos.sh` | **removed** | Same. |
| `Generate documentation data` step | `bash .devcontainer/manage/dev-docs.sh` | **removed for now** | PLAN-105 adds `bash scripts/generate-docs.sh` in exactly this position. |
| `Generate FloatingCubes configuration` step | `bash .devcontainer/manage/dev-cubes.sh` | **removed** | FloatingCubes is a DCT visual flourish; we're not porting it (per A6 mapping). |
| Env vars (`GITHUB_ORG` / `GITHUB_REPO`) | yes | yes | Keeps fork-friendliness from PLAN-103's `docusaurus.config.ts`. |

The fork-friendliness story: any user who forks `noclickops` and pushes their fork's `main` gets a working deploy on their own GitHub Pages with zero config edits. The `${{ github.repository_owner }}` / `${{ github.event.repository.name }}` substitutions handle org+repo; the forker just needs to (a) configure their fork's Pages source = "GitHub Actions" and (b) optionally add their own CNAME.

### `website/static/CNAME`

Single-line file:

```text
noclickops.sovereignsky.no
```

When GitHub Pages serves a site that contains a `CNAME` file, it sets that as the custom domain on the Pages settings and adds the `Custom domain` HTTP-redirect. Pair with the DNS step below.

### `website/static/img/favicon.ico` — placeholder

`docusaurus.config.ts` references `img/favicon.ico` (set in PLAN-103). Without the file, every page renders fine but emits a 404 in dev tools for the favicon — ugly in production. Ship a tiny placeholder. Options:

- **[Q-PLAN104-fav-a]** Generate a 32×32 `.ico` from a text-only SVG (a green `>` prompt glyph on transparent — matches the terminal-green palette). Tools: `rsvg-convert` + `convert` (ImageMagick), or any online SVG→ICO converter.
- **[Q-PLAN104-fav-b]** Copy a generic favicon from Docusaurus's `init` template (works, looks generic).
- **[Q-PLAN104-fav-c]** Drop the `favicon` line from `docusaurus.config.ts` for now; live with no favicon at all until branding lands.

**Recommendation**: Q-PLAN104-fav-a, simplest text-only SVG ("`>_`" in `#00b347` on transparent, 32×32). 10-minute job, looks intentional. Branding-quality logo work is out of scope for this trilogy.

### DNS work — your responsibility, out of band

DNS for `noclickops.sovereignsky.no` needs:

```text
noclickops.sovereignsky.no.    CNAME    terchris.github.io.
```

Do this in your DNS provider's panel (whoever hosts `sovereignsky.no`). Propagation takes a few minutes; verify with `dig +short noclickops.sovereignsky.no` returning the GitHub Pages IPs.

**Until DNS is set up**, the deploy still works — the site is reachable at `https://terchris.github.io/noclickops/`. Internal navigation may behave oddly because `docusaurus.config.ts` has `url: https://noclickops.sovereignsky.no`, so absolute URLs in generated pages point at the custom domain. Relative links continue to work. For a clean smoke test before DNS, see Phase 4 below.

### What this PLAN does NOT do

- **No marketing homepage.** PLAN-105.
- **No `scripts/generate-docs.sh`.** PLAN-105. The workflow leaves a clean slot where it'll insert later.
- **No fancy logo / brand assets** beyond a placeholder favicon. A future PLAN can ship a real logo + social-card.jpg.
- **No version bump.** `version.txt` unchanged; PLAN-105 bumps to v1.4.0 once the site is feature-complete.
- **No new tests in `tests/`.** Same reasoning as PLAN-103 — `npm run build` in CI is the validation surface.
- **No DNS configuration.** Out-of-band; documented in the smoke-test instructions but not automated.
- **No automatic repo-settings toggle.** Pages source = "GitHub Actions" is a one-time manual click in the repo's Settings → Pages. The workflow can't bootstrap itself.

---

## Phases

### Phase 1: Workflow + static assets

#### Tasks

- [ ] 1.1 Create `.github/workflows/deploy-docs.yml` per the YAML above.
- [ ] 1.2 Create `website/static/CNAME` with `noclickops.sovereignsky.no`.
- [ ] 1.3 Ship a placeholder favicon at `website/static/img/favicon.ico` per [Q-PLAN104-fav-a]. Smoke check: open `npm start`, view source on `/`, confirm `<link rel="icon" href="/img/favicon.ico">` resolves (no 404 in browser dev-tools Network tab).

#### Validation

```bash
cd website
npm run build                      # exits 0; build/CNAME exists; build/img/favicon.ico exists
ls build/CNAME build/img/favicon.ico
```

User confirms the CNAME file is in the built artifact (it gets copied from `static/` to `build/` automatically — Docusaurus convention).

---

### Phase 2: DNS setup (out-of-band)

#### Tasks

- [ ] 2.1 In your DNS provider's panel for `sovereignsky.no`, add a CNAME record:
   - **Name**: `noclickops`
   - **Type**: `CNAME`
   - **Value**: `terchris.github.io.` (the trailing dot is the FQDN root marker; some panels add it for you)
   - **TTL**: 3600 or whatever the panel defaults to
- [ ] 2.2 Wait for propagation. Verify:

   ```bash
   dig +short noclickops.sovereignsky.no
   # Expected: a list of GitHub Pages IPv4 addresses (185.199.108.153, 185.199.109.153, 185.199.110.153, 185.199.111.153)
   ```

#### Validation

`dig +short noclickops.sovereignsky.no` returns the GitHub Pages IPs (above). If it returns nothing or returns a different address, fix the DNS record before proceeding to Phase 3 — otherwise the deploy will succeed but the custom domain won't resolve.

**This phase can run before, during, or after Phase 1/3 — it's independent.** Easiest to do it first so it has time to propagate.

---

### Phase 3: Configure GitHub Pages (one-time manual)

#### Tasks

- [ ] 3.1 Open the repo settings: `https://github.com/terchris/noclickops/settings/pages`.
- [ ] 3.2 Under **Build and deployment** → **Source**, select **GitHub Actions** (not "Deploy from a branch").
- [ ] 3.3 Leave the Custom domain field blank for now — the `CNAME` file in `website/static/` will populate it on the first deploy.

#### Validation

The page shows "GitHub Actions" as the build source. No deploy has happened yet — that's Phase 4.

---

### Phase 4: Smoke-test the deploy via `workflow_dispatch`

The workflow triggers on `push` to `main` AND on `workflow_dispatch` (manual). We don't want to merge PLAN-104's branch to main yet — PLAN-105 is still pending and the "PR per investigation" rule says PR opens after PLAN-105. So smoke-test via manual trigger on the feature branch.

#### Tasks

- [ ] 4.1 Push the feature branch (or confirm it's already pushed):

   ```bash
   git push -u origin feat/v1.4.0-docusaurus
   ```
- [ ] 4.2 Manually trigger the workflow against the feature branch:

   ```bash
   gh workflow run deploy-docs.yml --ref feat/v1.4.0-docusaurus
   ```
- [ ] 4.3 Watch the run:

   ```bash
   gh run watch
   # OR open https://github.com/terchris/noclickops/actions
   ```
- [ ] 4.4 Once both `build` and `deploy` jobs go green, visit `https://noclickops.sovereignsky.no/` (or `https://terchris.github.io/noclickops/` if DNS isn't set up yet).
- [ ] 4.5 Click into `/docs/`, `/docs/ai-developer/`, a couple of plan pages. Confirm sidebar, search, and Mermaid all render.

#### Validation

Site reachable at the chosen URL. Internal navigation works. The page footer renders correctly. Sidebar shows the friendly labels from PLAN-103's `_category_.json` files.

**If the deploy fails:**

| Failure mode | Likely cause | Fix |
|---|---|---|
| `Error: HttpError: Not Found` on `deploy-pages` step | Repo Pages source not set to "GitHub Actions" | Phase 3.2 |
| Build step fails on `npm ci` | `package-lock.json` out of sync (e.g. local edits not committed) | Re-run `npm install` locally, commit the lock file |
| Build step fails on `npm run build` | Real broken link / MDX error introduced after PLAN-103 | Fix the source markdown; reuse PLAN-103 Phase 3 procedure |
| Site loads but custom domain shows "DNS error" | DNS not propagated yet | Wait, or use the `terchris.github.io/noclickops/` URL |
| Site loads but pages 404 | `baseUrl` mismatch between `docusaurus.config.ts` and actual deploy path | Check `docusaurus.config.ts` `baseUrl` — should be `/` when serving from a custom-domain root |

---

### Phase 5: Commit on branch (don't PR yet)

#### Tasks

- [ ] 5.1 Run `bash tests/run-all.sh` to confirm no regression. (Should be a no-op — `.github/workflows/` and `website/static/` aren't covered by the test suite.)
- [ ] 5.2 Stage `.github/workflows/deploy-docs.yml` + `website/static/CNAME` + `website/static/img/favicon.ico`.
- [ ] 5.3 Commit on `feat/v1.4.0-docusaurus`. Suggested message: `feat(PLAN-104): deploy Docusaurus site to GitHub Pages`.
- [ ] 5.4 Move `PLAN-104-website-deploy.md` from `plans/backlog/` to `plans/completed/`. Update Status to `Completed YYYY-MM-DD`. Fix any self-links the move surfaces (PLAN-103 ran into this — links to sibling files in `backlog/` need `../backlog/` after the move).
- [ ] 5.5 **Do not** open a PR yet — PLAN-105 still pending.

#### Validation

```bash
git log --oneline -3       # shows PLAN-103 + PLAN-104 commits on the branch
gh pr list --head feat/v1.4.0-docusaurus  # still empty
```

The site at `https://noclickops.sovereignsky.no/` (or `terchris.github.io/noclickops/`) is live with the PLAN-103 content.

---

## Acceptance criteria

- [ ] `.github/workflows/deploy-docs.yml` exists and triggers on push-to-main + workflow_dispatch.
- [ ] Workflow uses fork-friendly `GITHUB_ORG` / `GITHUB_REPO` env vars (matches `docusaurus.config.ts` from PLAN-103).
- [ ] `website/static/CNAME` contains `noclickops.sovereignsky.no` only.
- [ ] `website/static/img/favicon.ico` exists (placeholder, ~1 KB).
- [ ] Repo settings: Pages source = "GitHub Actions" (manual, can't be automated).
- [ ] DNS: `dig +short noclickops.sovereignsky.no` resolves to GitHub Pages IPs.
- [ ] At least one successful manual `workflow_dispatch` run from `feat/v1.4.0-docusaurus`; site reachable at the URL.
- [ ] `tests/run-all.sh` still passes.
- [ ] `version.txt` unchanged (PLAN-105 bumps).
- [ ] Commit lands on `feat/v1.4.0-docusaurus`; no PR opened.
- [ ] PLAN-104 moved to `plans/completed/` with updated status.

---

## Implementation notes for whoever picks this up

- **The placeholder favicon doesn't need to be beautiful** — `>_` in terminal green at 32×32 is fine; it's a 1-cm-square icon nobody looks at carefully. Spending more than 15 minutes here is over-investment.
- **`actions/upload-pages-artifact@v3` and `actions/deploy-pages@v4`** are the versions DCT runs in production. TMP runs `@v5` and `@v5` — both work; v3/v4 are the conservative choice. Bump in a future PLAN if anything breaks.
- **Node 20 in the workflow** matches DCT and matches our `"engines": {"node": ">=20.0"}` in `package.json`. Don't bump to 22 in CI without a separate check that everything still passes — we've been running Node 22 locally only.
- **`concurrency: { group: "pages", cancel-in-progress: true }`** prevents stacked deploys if you push twice in quick succession — only the latest deploys. Inherited from DCT, recommended.
- **The DNS step is the most likely thing to bite you.** Custom domains on GitHub Pages need both (a) the `CNAME` file in the repo (we ship this) AND (b) the DNS CNAME record at your provider. The repo settings auto-populate the Custom domain field from the file, but DNS is independent. If `https://noclickops.sovereignsky.no/` shows "DNS_PROBE_FINISHED_NXDOMAIN", Phase 2 didn't propagate.
- **HTTPS-only is enabled by default** on custom domains via Let's Encrypt — GitHub provisions it automatically the first time the domain resolves. May take a few minutes after DNS goes live.
- **Pushing the feature branch is required** for `workflow_dispatch` against it to work. Without push, the branch doesn't exist on the remote and `gh workflow run --ref feat/v1.4.0-docusaurus` fails with "branch not found".
- **The first deploy from this branch** will set the Custom domain in repo settings (from the CNAME file). After PLAN-105 ships and the branch is merged to main, future deploys keep that setting. If something looks off later, check Settings → Pages → Custom domain matches `noclickops.sovereignsky.no`.

---

## Files to modify / create

**Create:**

- `.github/workflows/deploy-docs.yml`
- `website/static/CNAME`
- `website/static/img/favicon.ico` (placeholder, ~1 KB)

**Move (Phase 5):**

- `website/docs/ai-developer/plans/backlog/PLAN-104-website-deploy.md` → `plans/completed/PLAN-104-website-deploy.md`. Rewrite any `[link](PLAN-103-website-foundation.md)`-style self-references to `../completed/...` (PLAN-103 sits in the same `completed/` folder) and `[link](INVESTIGATE-docusaurus.md)` to `../backlog/INVESTIGATE-docusaurus.md` (the INVESTIGATE stays in backlog until PLAN-105).

**No modifications** to existing files — this PLAN is purely additive on the GitHub-side and static-asset side.

---

## Completion notes (2026-05-29)

Site lit up at [`https://noclickops.sovereignsky.no/`](https://noclickops.sovereignsky.no/). Five gotchas hit during the deploy bring-up that the PLAN as drafted didn't anticipate — recorded here so the next site bring-up (a fork, a new sister project) doesn't re-discover them:

1. **`workflow_dispatch` can't trigger workflows that don't exist on the default branch.** Hit immediately when trying to dispatch from `feat/v1.4.0-docusaurus` — `gh workflow run` returned 404. **Workaround**: added the feature branch to `on.push.branches` temporarily (commit `2d108c8`). Removal task lives in PLAN-105's cleanup.
2. **The `github-pages` environment has branch-protection rules** that default to "protected branches only" (i.e. main). First deploy failed with `Branch "feat/v1.4.0-docusaurus" is not allowed to deploy to github-pages due to environment protection rules.` **Workaround**: added a custom branch policy via `gh api -X POST repos/{owner}/{repo}/environments/github-pages/deployment-branch-policies -f name=feat/v1.4.0-docusaurus`. Removal task: PLAN-105 cleanup.
3. **The CNAME file in `static/` does NOT auto-register the custom domain when `build_type: workflow`.** Verified the file landed in the build artifact, but `gh api repos/.../pages` still showed `cname: null` after deploy. **Workaround**: explicitly registered via `gh api -X PUT repos/{owner}/{repo}/pages` with a JSON body containing `{"cname": "noclickops.sovereignsky.no"}`. (The same call with `-f cname=…` form returned "certificate does not exist yet" — only the JSON-body form worked for the initial registration.) After this, the cert provisioned automatically.
4. **HTTPS cert provisioning is async** — initial `https_certificate.state` was `authorization_created`; took a couple of minutes to progress to `approved`. Don't try to set `https_enforced: true` until the state is `approved` or you'll get HTTP 404 from the HTTPS endpoint even though the deploy is fine.
5. **Switched the favicon from `.ico` to `.svg`** vs the PLAN's [Q-PLAN104-fav-a] recommendation. Reason: no `rsvg-convert` / ImageMagick on the implementer's host, and modern browser support for SVG favicons is universal. Updated `docusaurus.config.ts` accordingly. Functionally equivalent; one fewer image-tool dependency.

**Per-Phase outcome**:

| Phase | Status | Notes |
|---|---|---|
| 1 — Workflow + static assets | ✓ | Favicon as SVG (see gotcha 5). |
| 2 — DNS | ✓ | User added CNAME at the DNS provider before the smoke test. `dig +short` returned all four GitHub Pages IPs. |
| 3 — GitHub Pages settings | ✓ | Pages didn't exist; created via `gh api -X POST repos/{owner}/{repo}/pages -f build_type=workflow`. |
| 4 — Smoke test | ✓ | Two failed runs (gotchas 1 + 2), one successful run (`26628658959` after the env-policy fix + rerun). Then domain register (gotcha 3) + HTTPS bootstrap (gotcha 4). |
| 5 — Commit on branch | ✓ | Three commits on `feat/v1.4.0-docusaurus`: `c618b19` (PLAN-104 local artifacts), `2d108c8` (temporary feat-branch trigger), `<this commit>` (move to completed/ + completion notes). |

**Branch state**: `feat/v1.4.0-docusaurus` ahead of `main` by 5 commits (2 from PLAN-103 + 3 from PLAN-104). No PR yet — waits for PLAN-105.

**Cleanup tasks deferred to PLAN-105 (final step before opening the PR):**

- Remove `feat/v1.4.0-docusaurus` from `on.push.branches` in `.github/workflows/deploy-docs.yml`.
- Remove the custom branch policy: `gh api -X DELETE repos/{owner}/{repo}/environments/github-pages/deployment-branch-policies/50617191`.

These don't *break* the deploy if left in — they just leave dead config that future contributors would scratch their heads over.
