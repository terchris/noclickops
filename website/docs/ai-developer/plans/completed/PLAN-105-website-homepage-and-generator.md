# PLAN-105: Marketing homepage + metadata-driven docs generator

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-29

INVESTIGATE-docusaurus trilogy shipped. Site at https://noclickops.sovereignsky.no/ is the v1.4.0 release.

**Goal**: Replace PLAN-103's stub homepage and stub `/docs/` index with a real marketing homepage + a generated `/docs/commands` reference page driven by the `SCRIPT_*` metadata already present in `bin/*.sh`. Clean up PLAN-104's temporary deploy scaffolding. Bump `version.txt` to v1.4.0. Open the PR that carries the full INVESTIGATE-docusaurus trilogy as one cohesive review unit.

**Last Updated**: 2026-05-29

**Investigation**: [INVESTIGATE-docusaurus.md](../completed/INVESTIGATE-docusaurus.md) (realises rows A6 — homepage with category browsing — and A7 — metadata generator; closes the investigation)

**Prerequisites**: PLAN-103 (foundation), PLAN-104 (deploy + live site). Both on `feat/v1.4.0-docusaurus`.

**Blocks**: nothing — this is the last PLAN in the trilogy.

**Priority**: High — the trilogy isn't shippable without this; the placeholder homepage from PLAN-103 isn't a real product surface.

**Branch**: `feat/v1.4.0-docusaurus` — same branch as PLAN-103/104. PR opens at the end of this PLAN (per "PR per investigation" rule).

---

## Problem

After PLAN-104 the site is live but pointless. Visitors see:

- A one-line placeholder homepage ("Site under construction. Marketing homepage lands in PLAN-105.")
- A stub `/docs/` index ("This is a stub… read the README on GitHub instead.")
- Beautiful `_category_.json`-labelled sidebar tree of `ai-developer/` plans nobody but the maintainer cares about.

What it SHOULD show, per the locked-in answers (Q2a, Q7c, Q18a, Q19a):

- **`/`**: hero + 3–4 marketing cards + install one-liner. DCT shape.
- **`/docs/`**: the repo `README.md`, rendered as the docs root (Q7c). Single source of truth — when the README changes, the site updates.
- **`/docs/commands`**: a generated reference page. At the top, a clickable category grid; below, every command grouped by category, with synopsis + example + collapsible `--help` block. All driven by `SCRIPT_*` metadata in `bin/*.sh` via `lib/metadata.sh::parse_metadata()` (A7). DCT's `dev-docs.sh::generate_commands_md()` is the line-by-line reference.

Plus the loose ends from PLAN-104 to close:

- Remove `feat/v1.4.0-docusaurus` from `on.push.branches` in `.github/workflows/deploy-docs.yml` (so the workflow goes back to the design — main-only triggers).
- Delete the custom env branch policy (`gh api -X DELETE …/deployment-branch-policies/50617191`).
- Bump `version.txt` to v1.4.0 — first user-visible release with a docs site.
- Move `INVESTIGATE-docusaurus.md` from `backlog/` to `completed/` (it stayed in `backlog/` through PLAN-103/104 per the PLANS.md rule; this PLAN is the last child, so the INVESTIGATE ships now).
- **Open the PR.**

---

## What it delivers

### `scripts/generate-docs.sh` — Bash generator (~200 lines)

The single source of truth for "what's on the docs site that isn't hand-written". Sources `lib/metadata.sh`. Walks `bin/*.sh`, calls `parse_metadata` per script, emits four files:

| Output | Purpose | Consumed by |
|---|---|---|
| `website/docs/commands.mdx` | Per-command reference page. Frontmatter + imported `<CommandCategoryGrid />` at top + H2-per-category / H3-per-command body | Docusaurus build (becomes `/docs/commands` route) |
| `website/src/data/commands.json` | One row per command: `{name, description, usage, example, category}` | React components (`CommandCategoryGrid`, future widgets) |
| `website/src/data/categories.json` | One row per category: `{id, label, description, count}`; labels match the lister's display strings in `bin/noclickops.sh` lines 90–94 | React components |
| `website/docs/index.md` | Copy of repo-root `README.md` with Docusaurus frontmatter + repo-root link rewrites (Q7c) | Docusaurus build (becomes `/docs/` route) |

**Link rewriter for `README.md` → `index.md`** (the Q7c implementation note from the investigation):

```bash
# Pseudocode for the sed pipeline:
1. Prepend frontmatter: "---\nslug: /\ntitle: noclickops\nsidebar_position: 1\n---\n\n"
2. Rewrite ](CLAUDE.md)       → ](https://github.com/${ORG}/${REPO}/blob/main/CLAUDE.md)
3. Rewrite ](AGENTS.md)       → ](https://github.com/${ORG}/${REPO}/blob/main/AGENTS.md)
4. Rewrite ](LICENSE)         → ](https://github.com/${ORG}/${REPO}/blob/main/LICENSE)
5. Rewrite ](website/docs/ai-developer/...) → ](/docs/ai-developer/...)
6. Smoke check: grep -E "\]\(website/" output; fail loudly if any match
```

ORG / REPO derived from `GITHUB_ORG` / `GITHUB_REPO` env vars (set in CI; default `terchris` / `noclickops` locally — same convention as `docusaurus.config.ts`).

**`commands.mdx` template** (one rendered example, with placeholder substitution):

```mdx
---
title: Commands
sidebar_position: 2
---

import CommandCategoryGrid from '@site/src/components/CommandCategoryGrid';

# Commands

Every noclickops command, grouped by category. Click a category card to jump to its section, or scan the full reference below.

<CommandCategoryGrid />

## Meta

### noclickops

List all noclickops commands, or dispatch to a subcommand.

```bash
noclickops [<subcommand> [args...]]
```

**Example:**

```bash
noclickops merge-pr 4810
```

<details>
<summary>Full --help</summary>

```text
{output of `bin/noclickops.sh --help`}
```

</details>

### update
...
```

**Smoke checks** the generator runs before exit:

1. `count of bin/*.sh files == rows in commands.json` — catches a script without metadata.
2. `grep -E "\]\(website/" website/docs/index.md` returns nothing — catches link-rewriter misses.
3. Every `SCRIPT_CATEGORY` value is in `_NCO_VALID_CATEGORIES` — catches typos.

**No PowerShell sibling.** `scripts/generate-docs.sh` is internal repo tooling (runs in CI on Ubuntu, runs locally on macOS/Linux/WSL/Git Bash). The "every script ships `.sh` + `.ps1` siblings" rule covers user-facing `bin/*` scripts, not internal tooling — verified by `tests/test-portability.sh` only scanning `bin|lib|templates|shell`. Document this exception in the script header.

### React components (5 files, ~50–100 lines each)

DCT-shape, renamed:

| Component | Reads from | Renders |
|---|---|---|
| `src/components/HomepageFeatures/{index.tsx, styles.module.css}` | static (no JSON) | 4 marketing cards on the homepage |
| `src/components/QuickInstall/{index.tsx, styles.module.css}` | static | The `curl … install.sh` one-liner in a copy-able block |
| `src/components/CommandCategoryGrid/index.tsx` | `categories.json` + `commands.json` (counts) | Category cards, one per row in `categories.json` |
| `src/components/CommandCategoryCard/{index.tsx, styles.module.css}` | props | Single category card: label, description, command count, link to `/docs/commands#<category-slug>` |
| *(no `CommandCard` / `CommandGrid`)* | n/a | Per-command rendering on `/docs/commands` is markdown (H3 + code blocks), not React — Q19a's single-page reference doesn't need card components for individual commands. |

### Homepage features (4 cards in `HomepageFeatures`)

Copy adapted from `README.md` line 5 and the "Service lifecycle" / "Inspect / observe" categories:

1. **One command per task** — install, scaffold, deploy, observe; no clicking through ADO or Azure portals.
2. **Works in any repo** — derives identity from `git remote get-url origin` at call time; same commands work across every supported repo.
3. **Wraps existing pipelines** — triggers Azure DevOps pipelines and Azure CLI commands; never re-implements them. New pipeline steps land for every user automatically.
4. **Multi-OS by default** — `.sh` for macOS/Linux/WSL/Git Bash; `.ps1` for native Windows; single command via shell function or `PATH`.

Each card: emoji or simple SVG icon + title + 2-line description. No images required.

### Updated `.github/workflows/deploy-docs.yml`

Two changes:

1. **Remove the temporary feat-branch trigger** (PLAN-104 gotcha 1 cleanup):

   ```diff
    on:
      push:
        branches:
          - main
   -    # Temporary: lets PLAN-104/105 smoke-test...
   -    - feat/v1.4.0-docusaurus
      workflow_dispatch:
   ```

2. **Add the generator step** before `npm run build`:

   ```yaml
   - name: Generate docs (commands.mdx, index.md, JSON data)
     working-directory: .
     env:
       GITHUB_ORG: ${{ github.repository_owner }}
       GITHUB_REPO: ${{ github.event.repository.name }}
     run: bash scripts/generate-docs.sh
   ```

### `.gitignore` additions

Generated files are NOT committed (avoids stale-output drift if a contributor forgets to regenerate):

```text
# Generated by scripts/generate-docs.sh
website/docs/index.md
website/docs/commands.mdx
website/src/data/commands.json
website/src/data/categories.json
```

This means: local dev requires `bash scripts/generate-docs.sh && cd website && npm start`. Documented in `project-noclickops.md` (the "Working on the docs site" section gets a line added).

The stub `website/docs/index.md` from PLAN-103 is `git rm`'d as part of this PLAN. The build job regenerates it from `README.md` every time.

### Replaced `website/src/pages/index.tsx`

Hero (logo + tagline + Get Started/GitHub buttons) → `<HomepageFeatures />` → `<QuickInstall />`. Direct DCT-port minus `<FloatingCubes />` and `<AiDemo />`.

### `version.txt` → `1.4.0`

Semver minor — first release with a public docs site. Existing CLI surface unchanged.

### Cleanup of PLAN-104's env branch policy

Outside-the-repo cleanup, runs via `gh api`:

```bash
gh api -X DELETE repos/terchris/noclickops/environments/github-pages/deployment-branch-policies/50617191
```

After this, only `main` can deploy to `github-pages`. The next deploy happens when the PR merges and `main` advances.

### `INVESTIGATE-docusaurus.md` moves to `completed/`

The investigation that drove PLAN-103/104/105 ships with the trilogy. Move + update Status to `Completed 2026-05-29`.

### The PR

Per "PR per investigation": opens at the end of this PLAN with the full trilogy as one cohesive review unit. Body summarises the three PLANs, links to live site, lists the bring-up gotchas surfaced in PLAN-104's completion notes (so the reviewer sees them without digging).

### What this PLAN does NOT do

- **No per-command pages** (`/docs/commands/create-pr/` etc.). Q19a chose single-page reference; per-command pages wait for [Q21] (extended metadata: `SCRIPT_DETAILS`, `SCRIPT_FLAGS`, `SCRIPT_AUTH`, etc.).
- **No logo / favicon improvements** beyond PLAN-104's placeholder SVG. Branding-quality assets are a future PLAN.
- **No blog enablement** (Q3b deferred).
- **No Algolia DocSearch** (Q6a chose local search — already wired in PLAN-103).
- **No analytics** (Q17 deferred).
- **No `_category_.json` for `/docs/commands`** — it sits at the docs root level, not in a category folder.

---

## Phases

### Phase 1: Generator (`scripts/generate-docs.sh`) — DONE 2026-05-29

#### Tasks

- [x] 1.1 Create `scripts/` folder. (`project-noclickops.md` addition deferred to Phase 3.4 — folded with the rest of project-noclickops.md edits.)
- [x] 1.2 Write `scripts/generate-docs.sh`. All 6 sub-functions implemented. Generator ran clean: 12 commands parsed, 5 categories, 4 files emitted (commands.json 12 rows; categories.json 5 rows; commands.mdx 453 lines; index.md 150 lines). All smoke checks passed.
- [x] 1.3 Script header notes the "no .ps1 sibling" exception.
- [x] 1.4 `chmod +x scripts/generate-docs.sh`.

#### Validation

```bash
bash scripts/generate-docs.sh
# Expected output (stderr): smoke checks pass; 4 files written
ls website/docs/index.md website/docs/commands.mdx \
   website/src/data/commands.json website/src/data/categories.json
# All 4 exist; commands.json has 12 rows (1 per bin/*.sh — count from PLAN-103 implementation).
```

User confirms (visually): `cat website/docs/commands.mdx | head -30` looks right; `cat website/docs/index.md | head -20` shows the README with the new frontmatter and rewritten links.

---

### Phase 2: React components — DONE 2026-05-29

#### Tasks

- [x] 2.1 Created `HomepageFeatures/{index.tsx, styles.module.css}` — 4 emoji cards (no images).
- [x] 2.2 Created `QuickInstall/{index.tsx, styles.module.css}` — single Bash install (Windows hint links to README; PowerShell stub not advertised).
- [x] 2.3 Created `CommandCategoryGrid/{index.tsx, styles.module.css}` — reads `categories.json` (count baked in by generator; no need to derive from commands.json), filters empty categories.
- [x] 2.4 Created `CommandCategoryCard/{index.tsx, styles.module.css}` — props match the generator's category shape `{id, label, description, count}`. Anchor derived from `label` (not `id`) because Docusaurus generates auto-anchors from heading text. `npm run typecheck` clean.

#### Validation

```bash
cd website && npm run typecheck
# Exits 0; no errors on JSX or imports
```

---

### Phase 3: Wire generator into CI + gitignore — DONE 2026-05-29

#### Tasks

- [x] 3.1 Added 4 generated paths to `.gitignore`.
- [x] 3.2 `git rm --cached website/docs/index.md` (kept the generated copy in working tree).
- [x] 3.3 Workflow: removed `feat/v1.4.0-docusaurus` trigger, added generator step before build (working-directory `.` so `bash scripts/generate-docs.sh` resolves from repo root).
- [x] 3.4 Expanded "Working on the docs site" section in `project-noclickops.md` with full generator description (purpose, outputs, when-to-run, Bash-only rationale).
- [x] *Bonus*: surfaced and fixed two issues during validation:
   - `README.md` line 128 pointed at `website/docs/.../completed/` (a folder with no index page) → rewrote to absolute GitHub URL.
   - Category H2 anchors were mismatched between generator and React component (Docusaurus's github-slugger turns `Git / pull requests` into `git--pull-requests` with double dash). Aligned `CommandCategoryCard.anchorFor()` to mimic the slugger; build now anchor-clean.

#### Validation

```bash
bash scripts/generate-docs.sh
cd website && npm run build
# Exits 0; build/docs/commands/index.html and build/docs/index.html both exist
```

---

### Phase 4: Replace homepage — DONE 2026-05-29

#### Tasks

- [x] 4.1 New `index.tsx` — hero (favicon as logo + title + tagline from `siteConfig` + 3 buttons: Get Started / Commands / GitHub) → `<HomepageFeatures />` → `<QuickInstall />`.
- [x] 4.2 New `index.module.css` — dark green-tinged gradient hero (matches the terminal-green brand); buttons use `--outline` variant with white border for contrast against the dark hero. Mobile breakpoint at 720px shrinks the title.
- [ ] 4.3 Visual confirmation — `npm start` started in Phase 7, user confirms then.

#### Validation

User opens the local site and confirms:
- Homepage shows hero + 4 feature cards + install snippet. No "Site under construction" anywhere.
- `/docs/` shows the README content with the right frontmatter and working links.
- `/docs/commands` shows the category grid at top + the full H2/H3 reference below. Anchors work (`/docs/commands#git` jumps to the Git section).
- Sidebar still shows `ai-developer/` tree from PLAN-103.

---

### Phase 5: Clean up PLAN-104 scaffolding — DONE 2026-05-29

#### Tasks

- [x] 5.1 Confirmed in Phase 3 — workflow no longer references feat branch.
- [x] 5.2 Deleted env branch policy id `50617191`.
- [x] 5.3 Verified — only the `main` policy remains.

#### Validation

After merging the PR (Phase 7) and the next push to main triggers a deploy, the workflow runs cleanly and the deploy succeeds (because we're back on main, which is protected by default).

---

### Phase 6: Version bump + INVESTIGATE move + tests — DONE 2026-05-29

#### Tasks

- [x] 6.1 `version.txt` → `1.4.0`.
- [x] 6.2 INVESTIGATE-docusaurus moved to `completed/`, status updated. Three stale `../backlog/` link refs fixed in PLAN-103/104/105.
- [x] 6.3 PLAN-105 moved to `active/` at Phase 1 start; moves to `completed/` in Phase 7's commit (deferred so the final commit captures the file in its terminal location).
- [x] 6.4 `bash tests/run-all.sh` → 308 pass, 0 fail, 0 skip.
- [x] 6.5 `npm run build` clean.

#### Validation

```bash
cat version.txt              # 1.4.0
ls website/docs/ai-developer/plans/completed/INVESTIGATE-docusaurus.md  # exists
ls website/docs/ai-developer/plans/completed/PLAN-105-*.md  # exists
bash tests/run-all.sh        # 308 pass
cd website && npm run build  # clean
```

---

### Phase 7: Commit, push, open the PR — DONE 2026-05-29

#### Tasks

- [x] 7.1 Split into 4 commits per the suggested chunks (generator / homepage+components / CI+cleanup / v1.4.0 ship).
- [x] 7.2 `git push` — 4 commits to `origin/feat/v1.4.0-docusaurus`.
- [x] 7.3 No new CI deploy from this push (the temporary feat-branch trigger was removed in commit 3). Live site reflects PLAN-104's last deploy until the PR merges to main.
- [x] 7.4 PR opened: [#11](https://github.com/terchris/noclickops/pull/11)

Original draft of Phase 7 sub-tasks (kept for the record):

   ```bash
   gh pr create --title "feat(v1.4.0): Docusaurus site (INVESTIGATE-docusaurus trilogy: PLAN-103/104/105)" \
                --body-file <(cat <<'EOF'
   ## Summary
   - PLAN-103: scaffolds the Docusaurus app — site builds locally with existing ai-developer/ docs rendering, terminal-green palette, mermaid + local search.
   - PLAN-104: GitHub Pages deploy at https://noclickops.sovereignsky.no/ — CI workflow, CNAME, placeholder SVG favicon.
   - PLAN-105: marketing homepage (Hero + features + install) + generated /docs/commands reference + README rendered as /docs/ index. All driven by SCRIPT_* metadata in bin/*.sh via lib/metadata.sh::parse_metadata.

   Closes INVESTIGATE-docusaurus.

   ## Live
   - https://noclickops.sovereignsky.no/
   - https://noclickops.sovereignsky.no/docs/
   - https://noclickops.sovereignsky.no/docs/commands

   ## Test plan
   - [x] `cd website && npm install && npm run build` clean (onBrokenLinks: 'throw')
   - [x] `bash tests/run-all.sh` — 308 pass, 0 fail
   - [x] Manual: homepage, docs index, commands page, category card anchors, sidebar friendly labels — all visually correct
   - [x] CI deploy succeeded (live URL above)

   ## Notes for reviewer
   Five deploy bring-up gotchas surfaced in PLAN-104 (workflow_dispatch on non-default branch, env branch protection, CNAME not auto-registering for build_type:workflow, async cert provisioning, favicon format) are recorded in `plans/completed/PLAN-104-website-deploy.md` for future site bring-ups.

   Generated outputs (commands.mdx, index.md, commands.json, categories.json) are gitignored — local dev requires `bash scripts/generate-docs.sh` before `npm start`. Documented in project-noclickops.md.

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )
   ```
- [ ] 7.5 Once the PR is reviewed and merged, the deploy fires from main automatically (workflow's `on: push: branches: [main]`).

#### Validation

PR opens. Last CI run on the feat branch is green. After merge, the next deploy from main goes green and the site at `https://noclickops.sovereignsky.no/` reflects the merged state. Sidebar shows `INVESTIGATE-docusaurus` and `PLAN-105-...` under `completed/`.

---

## Acceptance criteria

- [ ] `scripts/generate-docs.sh` exists, executable, walks `bin/*.sh`, emits 4 files cleanly, smoke checks pass.
- [ ] `website/src/components/{HomepageFeatures,QuickInstall,CommandCategoryGrid,CommandCategoryCard}/` exist and typecheck.
- [ ] `website/src/pages/index.tsx` is the real homepage (no "Site under construction").
- [ ] `website/docs/commands.mdx`, `website/docs/index.md`, `website/src/data/*.json` all in `.gitignore`; not in `git ls-files`.
- [ ] `.github/workflows/deploy-docs.yml` no longer references `feat/v1.4.0-docusaurus`; runs the generator before build.
- [ ] Env branch policy for `feat/v1.4.0-docusaurus` deleted.
- [ ] `version.txt` = `1.4.0`.
- [ ] `INVESTIGATE-docusaurus.md` + `PLAN-105-...md` both in `plans/completed/`.
- [ ] `bash tests/run-all.sh` → 308 pass.
- [ ] `cd website && npm run build` clean.
- [ ] CI deploy from the feat branch green; live site at `https://noclickops.sovereignsky.no/` shows the real homepage.
- [ ] PR opened with the body above; carries all 3 PLAN deliverables.

---

## Implementation notes for whoever picks this up

- **DCT's `dev-docs.sh::generate_commands_md()`** (`/Users/terje.christensen/learn/helpers/devcontainer-toolbox/.devcontainer/manage/dev-docs.sh` lines 1100–1229) is the line-by-line reference for `emit_commands_mdx`. Their script emits to `commands.md` (plain markdown); we emit to `commands.mdx` because we need `<CommandCategoryGrid />` at the top.
- **`lib/metadata.sh::parse_metadata`** sets `parsed_name`, `parsed_description`, `parsed_usage`, `parsed_example`, `parsed_category` as globals after parsing one file. To accumulate rows, the generator either:
  - Calls `parse_metadata` in a subshell per file and captures output, OR
  - Calls in the parent shell, copies the globals into local vars per iteration, then `unset` before the next file.
  The subshell approach is cleaner; matches DCT's pattern.
- **JSON emission in Bash** — use `jq -n` with `--arg` flags rather than hand-rolling `printf`. Handles quoting / escaping correctly. `jq` is already a noclickops runtime dep (used by `bin/info.sh`); fine to use here too. Example: `jq -n --arg name "$parsed_name" --arg desc "$parsed_description" '{name: $name, description: $desc}'`.
- **Category slugification** for anchors: `meta` → `#meta`; `git` → `#git`; `service-lifecycle` → `#service-lifecycle`; `inspect` → `#inspect`. The Docusaurus auto-heading-anchor for `## Service lifecycle` is `#service-lifecycle` — confirm by checking the rendered page.
- **`--help` output capture**: `bash bin/<cmd>.sh --help 2>&1`. Wrap in a `<details>` block in the MDX. DCT does this; their `format_help_output()` (lines 663–689) is the reference. Trim ANSI escape codes if present (`sed 's/\x1b\[[0-9;]*m//g'`).
- **Don't lose the `noclickops` dispatcher**. `bin/noclickops.sh` is in the `meta` category — make sure it's in the reference page, just like every other command. PLAN-103 found 12 `bin/*.sh` files (11 commands + 1 dispatcher).
- **Header in `commands.mdx`**: keep it short. DCT's commands page works because every command gets ~80 words of context per H3. With our 5 fields per command (name, description, usage, example, category), expect ~40 words per H3. That's fine for a single-page reference.
- **The README link rewriter** is the highest-risk part of the generator. Write tests for each rewrite rule (small bash fixture files). Add the smoke check (`grep -E "]\(website/" output | fail` if any match) as belt-and-suspenders.
- **Local dev ergonomics**: contributors who forget to run `bash scripts/generate-docs.sh` before `npm start` will see "Module not found: src/data/commands.json" errors in the Docusaurus terminal output. Consider a `npm-script` wrapper: `"start": "bash ../scripts/generate-docs.sh && docusaurus start"` in `website/package.json`. Trades a few hundred ms on every start for never-having-to-remember.
- **The PR title** should land on `feat(v1.4.0):` to match the existing release-tagged commits in `git log` (`feat(v1.3.0): add-service auto-merges...`).
- **Cherry-pick reviewer attention** to the homepage hero copy, the 4 HomepageFeatures cards, and the QuickInstall snippet — these are the user-facing surface words. Everything else is plumbing.

---

## Files to modify / create

**Create:**

- `scripts/generate-docs.sh` (+ `scripts/` folder, first script here)
- `website/src/components/HomepageFeatures/index.tsx`
- `website/src/components/HomepageFeatures/styles.module.css`
- `website/src/components/QuickInstall/index.tsx`
- `website/src/components/QuickInstall/styles.module.css`
- `website/src/components/CommandCategoryGrid/index.tsx`
- `website/src/components/CommandCategoryCard/index.tsx`
- `website/src/components/CommandCategoryCard/styles.module.css`
- `website/src/pages/index.module.css`

**Modify:**

- `website/src/pages/index.tsx` — replace placeholder with real homepage.
- `.github/workflows/deploy-docs.yml` — remove temp trigger, add generator step.
- `.gitignore` — add 4 generated-output paths.
- `website/docs/ai-developer/project-noclickops.md` — add `scripts/` folder description + the "run generator before npm start" line.
- `version.txt` — `1.4.0`.

**Delete from git tracking (`git rm`):**

- `website/docs/index.md` (stub from PLAN-103; now generated)

**Move:**

- `website/docs/ai-developer/plans/backlog/INVESTIGATE-docusaurus.md` → `plans/completed/`
- `website/docs/ai-developer/plans/backlog/PLAN-105-website-homepage-and-generator.md` → `plans/active/` (while implementing) → `plans/completed/` (when done)
