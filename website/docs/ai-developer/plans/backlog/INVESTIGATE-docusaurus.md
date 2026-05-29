# Investigate: Add Docusaurus to noclickops

> **IMPLEMENTATION RULES:** Before implementing the plans that come out of this investigation, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Backlog — decisions locked, ready to draft child PLANs

**Goal**: Decide *what* Docusaurus setup `noclickops` needs and *how much* of an existing sister project's Docusaurus setup to copy. Land a v1 that publishes the existing `website/docs/` markdown to a browsable site AND renders a marketing homepage that shows what noclickops does — without dragging in template-catalogue machinery that has no equivalent here.

**Last Updated**: 2026-05-29

## Locked-in decisions (2026-05-29)

User answered the decision-points; outcomes below feed directly into PLAN-A/B/C. The full reasoning behind each option lives in the [Q] sections further down.

| ID | Answer | Outcome |
|---|---|---|
| **[Q1a]** | yes | Brand color: terminal green (`#00ff66`-ish, neon-on-black accent). Set in `website/src/css/custom.css`. |
| **[Q2a]** | yes | Pure DCT homepage shape: Hero → HomepageFeatures → QuickInstall. Category browsing lives on `/docs/commands` (the generated reference page), NOT the homepage. |
| **[Q3b]** | defer | No blog in v1. Release notes stay in `CHANGELOG.md` / git tag messages. Easy to enable later. |
| **[Q4a]** | yes | Public URL: `noclickops.sovereignsky.no`. `static/CNAME` carries the domain; DNS work happens out-of-band. |
| **[Q5a]** | add | Mermaid enabled via `@docusaurus/theme-mermaid` + `markdown.mermaid: true`. |
| **[Q6a]** | yes | Local search via `@easyops-cn/docusaurus-search-local`. |
| **[Q7c]** | yes for now | Docs index = repo root `README.md`, copied into `website/docs/index.md` at build time by the same generator that produces `commands.md`. **Path-rewriter is mandatory** (see note below). |
| **[Q8a]** | yes | Add `_category_.json` to `website/docs/ai-developer/`, `.../plans/`, `.../plans/{backlog,active,completed}/` for labeled sidebar entries. |
| **[Q9b]** | yes | Workflow rebuilds on every push to `main` (no path filter). Cheap CI minutes; simpler workflow. |
| **[Q18a]** | yes | Generator is Bash (`scripts/generate-docs.sh`). Sources `lib/metadata.sh` for `parse_metadata()`. |
| **[Q19a]** | yes | Single generated `website/docs/commands.md` (H2 per category, H3 per command, anchored). DCT pattern. |

**Defaults adopted for unanswered Q's (user said "not sure" or didn't specify):**

| ID | Default | Why |
|---|---|---|
| **[Q10]** | **Mooted by Q7c.** | If README is the docs index (Q7c), there's no second copy to drift. The "single source of truth" version of Q10 is the answer — Q10b/Q10c don't apply. |
| **[Q11a]** | Document `cd website && npm install && npm start` in `project-noclickops.md`. | DCT's own README does this verbatim. No wrapper script; no `noclickops` subcommand (would violate "wrap, never replicate"). |
| **[Q18b'-a]** | Generator runs as an explicit CI step before `npm run build`. | Matches DCT's workflow exactly. Local devs run `bash scripts/generate-docs.sh` manually before `npm start` (documented in `project-noclickops.md` alongside Q11a). |

**Q7c implementation note (the risky bit, now scoped):**

`scripts/generate-docs.sh` gets a third output: copy `README.md` → `website/docs/index.md` with these transformations (small sed pipeline, all build-time):

1. **Prepend Docusaurus frontmatter**: `---\nslug: /\ntitle: noclickops\nsidebar_position: 1\n---`
2. **Rewrite relative repo-root links** so they resolve in the rendered site:
   - `](CLAUDE.md)` / `](AGENTS.md)` → absolute GitHub URL (these are tooling files, not docs pages)
   - `](LICENSE)` → absolute GitHub URL
   - `](website/docs/ai-developer/...)` → `](/docs/ai-developer/...)`
   - `](website/docs/ai-developer/plans/completed/)` → `](/docs/ai-developer/plans/completed/)`
3. **Strip / rewrite the GitHub Actions badge** — it points at an `actions/workflows/...` URL; either leave it (renders fine in Docusaurus) or drop it (cleaner). Default: leave it.
4. **Smoke check**: after copy, grep the result for any remaining `](website/` patterns and fail the build if any are found (catches new README links that need a rule).

`website/docs/index.md` becomes a generated file (gitignored or committed-but-don't-edit, like DCT's `commands.md`). The existing `website/docs/ai-developer/README.md` keeps its current role — sidebar entry for the AI-developer tree, not the site root.

**Still open (non-blocking for PLAN drafting):**

- **[Q15]** Separate `CONTRIBUTING.md` — defer; revisit after site is live.
- **[Q16]** `editUrl` for "Edit this page" links — recommend yes (DCT enables it; free). Will fold into PLAN-A.
- **[Q17]** Analytics — defer until [Q4a] domain is live and there's an audience to measure.
- **[Q21]** Extended `SCRIPT_*` metadata fields (`SCRIPT_DETAILS` / `SCRIPT_FLAGS` / `SCRIPT_AUTH` / etc.) — separate backlog INVESTIGATE/PLAN, triggered after the v1 site exposes the gap.

---

**Sources surveyed**:
- `/Users/terje.christensen/learn/helpers/dev-templates/website/` (TMP) — Docusaurus 3.10, deployed to `tmp.sovereignsky.no` via GitHub Pages.
- `/Users/terje.christensen/learn/helpers/devcontainer-toolbox/website/` (DCT) — Docusaurus 3.9.2, deployed to `dct.sovereignsky.no`. **The closer model** (2026-05-29 user steer): same `SCRIPT_*` metadata pattern noclickops already uses; generator is Bash, not TypeScript; outputs a single `commands.md` reference page exactly equivalent to what noclickops's "v1.0.0 surface" table in `README.md` is today.

---

## Why now

The repo already keeps documentation under `website/docs/ai-developer/` *as if* Docusaurus were going to render it — the folder layout, the relative `[link](./WORKFLOW.md)` style, even the `_category_.json`-shaped subfolders all point at that. But there's no Docusaurus app present. Two consequences:

1. Anyone who lands at the GitHub repo reads the docs as raw markdown in the GitHub UI. Cross-references work, but there's no search, no sidebar, no rendered Mermaid, no shareable section URLs.
2. The `noclickops` brand promise (`README.md` line 5: "no clickops") deserves a small, fast docs site that matches the product's vibe — terminal-y, low-friction. TMP already pays the tooling cost for the same Docusaurus stack we'd use; the marginal cost of adopting here is small.

Constraint: the *file paths* under `website/docs/ai-developer/` are referenced from `CLAUDE.md`, `AGENTS.md`, and every plan file via relative links (e.g. `website/docs/ai-developer/project-noclickops.md`). Docusaurus must render those files **without moving them**. (Same constraint TMP lives with — confirmed by inspecting their layout.)

---

## What DCT's Docusaurus setup actually is (the model we follow)

Anatomy of `devcontainer-toolbox/website/` + the generator at `.devcontainer/manage/dev-docs.sh`:

| Piece | What it is | Relevant to noclickops? |
|---|---|---|
| `docusaurus.config.ts` | site config: title, URL, navbar (with version badge), footer, mermaid theme, local search, image-zoom, `editUrl` | **Yes** — copy and adapt; drop image-zoom if [Q5] says so |
| `sidebars.ts` | one autogenerated sidebar | **Yes** — copy verbatim |
| `package.json` | Docusaurus 3.9.2 + classic preset + mermaid theme + local search + image-zoom | **Yes** — copy and trim per [Q5]/[Q6] |
| `tsconfig.json` | extends `@docusaurus/tsconfig` | **Yes** — copy verbatim |
| `docs/` | markdown content; one `commands.md` is generated, the rest hand-written | **Yes** — point at existing `website/docs/`; add a generated `commands.md` |
| `blog/` | release notes / blog posts | **Per [Q3]** |
| `src/pages/index.tsx` | hero (with logo + tagline) + `<HomepageFeatures>` (3-4 cards) + `<QuickInstall>` + `<AiDemo>` | **Yes** — copy the *shape*, swap copy and drop AiDemo |
| `src/components/CategoryCard`, `CategoryGrid` | category-overview cards used on a docs page (not the homepage) | **Yes** — adapt for noclickops categories |
| `src/components/ToolCard`, `ToolGrid` | per-item cards used inside category pages | **Yes** — adapt to "CommandCard" / "CommandGrid" |
| `src/components/HomepageFeatures`, `QuickInstall` | static React for homepage marketing | **Yes** — adapt |
| `src/components/FloatingCubes`, `AiDemo` | DCT-specific visual flourishes | **No** — drop |
| `src/components/RelatedTools` | "see also" widget for per-item pages | **Defer** — needs `SCRIPT_RELATED` metadata extension first |
| `src/data/categories.json`, `tools.json` | generated by `dev-docs.sh`, consumed by React components | **Yes** — same pattern; we generate `commands.json` + `categories.json` |
| `src/css/custom.css` | brand colors, hero styling, card styling | **Partial** — adapt brand color per [Q1] |
| `static/img/` | logo, favicon, social card, per-category logos, per-tool logos | **Yes** — but we need our own (no `noclickops` logo yet) |
| `static/CNAME` | `dct.sovereignsky.no` | **Yes** — needs noclickops's domain per [Q4] |
| `.github/workflows/deploy-docs.yml` | builds + deploys; runs the generator (`dev-docs.sh`) before `npm run build` | **Yes** — copy; replace the dev-* generator calls with our `generate-docs.sh` |
| `.devcontainer/manage/dev-docs.sh` | **Bash generator (~1400 lines)** — walks `additions/install-*.sh`, extracts `SCRIPT_*` metadata via `grep` + `sed`, emits per-tool MDX pages, `commands.md`, `tools.json`, `categories.json`, and updates `README.md` between HTML-comment markers (`TOOLS_START` / `TOOLS_END`) | **Yes — this is the reference implementation** for our `scripts/generate-docs.sh` (which will be much smaller — ~150 lines for 11 commands) |

The clean separation: **everything in `website/docs/`, `website/src/components/`, and the generator pattern is directly applicable**; **DCT's marketing-specific bits (FloatingCubes, AiDemo) are drop-only**; **DCT's container-context (the generator lives in `.devcontainer/manage/` because DCT itself ships a devcontainer) doesn't apply** — our generator lives at `scripts/generate-docs.sh` at the repo root.

## What TMP offered (and what we're explicitly *not* taking)

Surveyed first; superseded by DCT as the closer model. Kept for the record so future readers don't repeat the survey:

- **TMP's `src/pages/index.tsx` is too heavy** for a CLI tool's homepage — it's `<HeroAnimation>` + `<CategoryGrid>` + `<TemplateGrid>` for ~50 templates. DCT's simpler hero + features + install pattern is the better fit.
- **TMP's `scripts/generate-registry.ts` is TypeScript** because TMP's source data is `template-info.yaml` files (Node has YAML libs; Bash needs `yq`). noclickops's source data is `SCRIPT_*=` shell assignments — Bash already parses them via `lib/metadata.sh::parse_metadata()`. DCT's Bash generator is the right shape.
- **TMP's `src/pages/templates.tsx` catalogue page** has no analogue here (noclickops's "catalogue" is 11 commands; DCT's `commands.md` single-page pattern fits better than a dedicated `/commands` route).
- TMP's mermaid theme, local search, image-zoom plugin, and `static/CNAME` deploy pattern are all things DCT also has — so no loss in switching the primary reference to DCT.

---

## Patterns to ADOPT (for v1)

### A1 — Docusaurus 3.10 + classic preset + faster preset

Same versions TMP runs in production. Stable, well-supported by upstream. `@docusaurus/faster` cuts cold-start build time meaningfully (Rspack-based bundler). No reason to diverge.

**Apply**: copy `package.json` dependency block, drop `@easyops-cn/docusaurus-search-local`, `docusaurus-plugin-image-zoom`, `js-yaml`, `@types/js-yaml` (TMP-only) and consider mermaid + search ([Q5], [Q6]).

### A2 — `docs/` lives in place; sidebar autogenerated

TMP's `sidebars.ts` is a single line: `docsSidebar: [{type: 'autogenerated', dirName: '.'}]`. Docusaurus walks the tree and uses folder structure + `_category_.json` files to build the sidebar. Means we keep `website/docs/ai-developer/` as is and just add the Docusaurus app *around* it. `CLAUDE.md` / `AGENTS.md` paths keep working.

**Apply**: copy `sidebars.ts` verbatim. Add `_category_.json` files where we want labeled folders (e.g. `website/docs/ai-developer/`, `website/docs/ai-developer/plans/`).

### A3 — `tsconfig.json` extends `@docusaurus/tsconfig`

Two-line config, nothing to customize.

**Apply**: copy verbatim.

### A4 — GitHub Pages deploy on push to `main`

TMP's workflow: install deps, build, upload artifact, deploy via `actions/deploy-pages@v5`. Path filter `website/**` means non-docs changes don't trigger a rebuild.

**Apply**: copy a slimmed version — drop the template-registry / metadata / generate-docs steps; keep only `npm ci` → `npm run build` → upload → deploy. Add `.github/workflows/deploy-docs.yml`. Path filter becomes `website/**` + `.github/workflows/deploy-docs.yml`.

### A5 — `.gitignore` entries for build artifacts

TMP gitignores `website/build/` and `website/.docusaurus/`. Standard hygiene.

**Apply**: add both lines (plus `node_modules/`) to root `.gitignore`.

### A6 — Marketing homepage + category-grouped command reference (DCT pattern)

**Decision (user, 2026-05-29): YES, we want this.** The homepage is the marketing surface — first-time visitors should see what noclickops actually does, not a docs sidebar. DCT's pattern fits perfectly because noclickops already has the same shape: a small set of commands that naturally bucket into categories. The README's "v1.0.0 surface" table groups all 11 commands across 5 categories (Meta / Git / Deployment / Service lifecycle / Inspect & observe). That table becomes a docs page (`/docs/commands`), and the homepage links to it from a category grid.

The DCT→noclickops mapping is essentially identical (same metadata pattern, same Bash generator approach):

| DCT concept | noclickops equivalent |
|---|---|
| Install script (e.g. `.devcontainer/additions/install-dev-python.sh`) | Command script (e.g. `bin/create-pr.sh`) |
| `SCRIPT_ID` / `SCRIPT_NAME` / `SCRIPT_DESCRIPTION` / `SCRIPT_CATEGORY` (+ extended fields) | Same; noclickops already has `SCRIPT_NAME` / `SCRIPT_DESCRIPTION` / `SCRIPT_USAGE` / `SCRIPT_EXAMPLE` / `SCRIPT_CATEGORY` (see A7) |
| `LANGUAGE_DEV`, `AI_TOOLS`, etc. (in `lib/categories.sh`) | `meta`, `git`, `deploy`, `service-lifecycle`, `inspect` (already in [`lib/metadata.sh`](../../../../../lib/metadata.sh) as `_NCO_VALID_CATEGORIES`) |
| `.devcontainer/manage/dev-docs.sh` (~1400 lines, Bash) | `scripts/generate-docs.sh` (~150 lines for 11 commands, Bash; reuses `lib/metadata.sh::parse_metadata`) |
| `website/docs/commands.md` (generated, single page, anchored H3s per command) | `website/docs/commands.md` (generated, same shape) |
| `website/docs/tools/<category>/<tool>.mdx` (per-tool pages) | Defer — wait for extended `SCRIPT_*` fields ([Q21]). v1 has only the single page. |
| `website/src/data/tools.json` + `categories.json` (generated, consumed by `<ToolGrid>` etc.) | `website/src/data/commands.json` + `categories.json` (generated, consumed by `<CommandGrid>` etc.) |
| `<CategoryGrid>` + `<CategoryCard>` (rendered on `/docs/tools` index page) | `<CommandCategoryGrid>` + `<CommandCategoryCard>` (rendered on homepage and/or `/docs/commands` per [Q2]) |
| `<ToolGrid>` + `<ToolCard>` (rendered on per-category pages) | `<CommandGrid>` + `<CommandCard>` (rendered on homepage per [Q2]) |
| `<HomepageFeatures>` (3-4 marketing cards on `index.tsx`) | Same — adapt copy from `README.md` ("Installed once", "Works in any repo", "Wraps existing pipelines", "No clickops") |
| `<QuickInstall>` (install one-liner card on `index.tsx`) | Same — adapt to noclickops's `curl … install.sh` line |
| `<FloatingCubes>`, `<AiDemo>` | Drop — DCT-specific marketing flourishes |
| `<RelatedTools>` | Defer — needs `SCRIPT_RELATED` from [Q21] |

**Apply**: copy the *shape* of DCT's `src/components/CategoryGrid` + `CategoryCard` + `ToolGrid` + `ToolCard` + `HomepageFeatures` + `QuickInstall` and rewrite them against the noclickops data model. Skip FloatingCubes / AiDemo / RelatedTools. The homepage hero + features + install pattern is direct; the category grid placement (homepage vs docs page) is [Q2].

This **supersedes** the original B1/B2 "defer" stance.

### A7 — Drive the homepage and `commands.md` from existing `SCRIPT_*` metadata, generator in Bash

**Decision (user, 2026-05-29): YES, and use Bash.** noclickops already has the `SCRIPT_*` metadata; DCT proves the Bash-generator pattern in production. If a richer doc page needs fields that don't exist yet, capture those as a separate metadata-extension PLAN — don't block v1 on them.

**The metadata is already in place across all 12 scripts.** From [`lib/metadata.sh`](../../../../../lib/metadata.sh) (line 4–9) and confirmed by inspecting `bin/create-pr.sh`, `bin/deploy.sh`, `bin/add-service.sh`, `bin/noclickops.sh`:

```bash
# --- noclickops metadata ---
SCRIPT_NAME="create-pr"
SCRIPT_DESCRIPTION="Open an Azure DevOps PR from the current branch to main."
SCRIPT_USAGE='noclickops create-pr "<title>" ["<description>"]'
SCRIPT_EXAMPLE='noclickops create-pr "feat: add login flow"'
SCRIPT_CATEGORY="git"
# --- end metadata ---
```

That's enough for both surfaces:

- **Homepage card** uses: `SCRIPT_NAME` (card title), `SCRIPT_DESCRIPTION` (card body), `SCRIPT_CATEGORY` (which bucket it sits in).
- **`commands.md` H3 section** uses all five: `SCRIPT_NAME` (H3 anchor + title), `SCRIPT_DESCRIPTION` (tagline), `SCRIPT_USAGE` (synopsis code block), `SCRIPT_EXAMPLE` (cookbook code block), `SCRIPT_CATEGORY` (which H2 group it goes under), plus `--help` body in a collapsible (per DCT's `commands.md` pattern, lines 1064–1226 of `dev-docs.sh`).

**Bash generator pattern is already proven by DCT.** `lib/metadata.sh::parse_metadata()` already does the extraction; the new generator at `scripts/generate-docs.sh` would source `lib/metadata.sh`, walk `bin/*.sh`, and emit:

1. `website/docs/commands.md` — single page, H2 per category, H3 per command with anchors. Direct port of DCT's `generate_commands_md()` (`dev-docs.sh` lines 1100–1229).
2. `website/src/data/commands.json` — one row per command (name, description, usage, example, category). Consumed by `<CommandGrid>` / `<CommandCard>` React components.
3. `website/src/data/categories.json` — one row per category (id, label, description). Consumed by `<CommandCategoryGrid>` / `<CommandCategoryCard>`. Source for category labels: the lister's display strings in `bin/noclickops.sh` lines 90–94 (`"Meta"`, `"Git / pull requests"`, `"Deployment"`, `"Service lifecycle"`, `"Inspect / observe"`).
4. *Optional v1.x:* update `README.md`'s "v1.0.0 surface" table between HTML-comment markers (`COMMANDS_START` / `COMMANDS_END`), so the README never drifts from `bin/`. Direct port of DCT's `update_readme()` (`dev-docs.sh` lines 617–660).

Generator size estimate: **~150 lines of Bash** for noclickops's 11 commands and 5 categories (DCT's 1400 lines handle 50+ tools with package arrays, logos, extensions, multi-output orchestration — most of that is *not* relevant here).

**Apply**: PLAN-C adds `scripts/generate-docs.sh`. Generator runs per [Q18b'] (recommended: explicit step in CI workflow, same as DCT). See [Q19] for the question of *additional* per-command pages beyond the single `commands.md`.

**What's missing for richer pages (recorded as [Q21] follow-up, not blocking v1):**

DCT extends `SCRIPT_*` with: `SCRIPT_ID`, `SCRIPT_VER`, `SCRIPT_TAGS`, `SCRIPT_ABSTRACT`, `SCRIPT_LOGO`, `SCRIPT_WEBSITE`, `SCRIPT_SUMMARY`, `SCRIPT_RELATED` (see `dev-docs.sh` line 141). That extended set is what enables DCT's rich per-tool MDX pages. For noclickops the analogous extensions would be:

- **`SCRIPT_DETAILS`** — multi-line "what this actually does" paragraph (beyond the one-line `SCRIPT_DESCRIPTION`). Some scripts already have this as a comment header (`bin/add-service.sh` lines 1–18 explain the pipeline contract); not structured yet. DCT's `SCRIPT_SUMMARY` is the precedent.
- **`SCRIPT_FLAGS`** — structured flag reference. Today flag handling lives in each script's `case "$a" in …` block; nothing parses it.
- **`SCRIPT_AUTH`** — auth prerequisites per command (the README has this at category level: `create-pr/merge-pr/deploy/add-service/status` need `az login`; `info/logs/shell` additionally need Reader on a subscription). Per-command would be cleaner.
- **`SCRIPT_EXIT_CODES`** — documented non-zero exit conditions. Several scripts `die "..."` in distinct failure modes; not currently classified.
- **`SCRIPT_SEE_ALSO`** — related commands. Obvious pairs: `create-pr` ↔ `merge-pr`, `add-service` ↔ `status`, `info` ↔ `logs` ↔ `shell`. DCT's `SCRIPT_RELATED` is the precedent.
- **`SCRIPT_DEPENDS_ON`** — required tools (`az`, `gh`, `jq`, `rsync` for sync-lovable). The `require_*` helpers in `lib/` know this implicitly; surfacing per-command would help.

These are **decisions for [Q21]'s follow-up PLAN**, not this investigation. v1's `commands.md` renders only the existing five fields plus the `--help` body in a collapsible (the DCT pattern).

---

## Patterns to DEFER

### B1 — `mermaid-zoom.ts` client module

Nice quality-of-life for big diagrams. Mermaid itself is the prerequisite ([Q5]). Defer the zoom — easy to add later, not worth the surface area for v1.

**Verdict**: defer. Revisit if Mermaid lands and the rendered diagrams are too small to read.

### B2 — Image-zoom plugin (`docusaurus-plugin-image-zoom`)

Same reasoning as B1 but for `.markdown img`. We have no screenshots in the current docs.

**Verdict**: defer.

---

## Patterns to DIVERGE on

### C1 — Brand color

TMP's `--ifm-color-primary: #2d6a4f` (forest green) ties to the dev-templates / SovereignSky family. noclickops needs its own. Suggested palette options in [Q1].

### C2 — Domain

TMP uses `tmp.sovereignsky.no` on a SovereignSky-controlled DNS. noclickops's hosting decision is a separate question ([Q4]). Reasonable choices: SovereignSky subdomain, plain GitHub Pages URL, custom domain — picks below.

### C3 — Homepage content (not structure)

We're keeping TMP's homepage *structure* (hero + category grid + item grid — see A6) but every word of copy is noclickops-specific: tagline reflects "no clickops" not "instant-start templates", the hero CTAs go to install + first commands not "Browse Templates", category labels match the README table (Meta / Git / Deployment / Service lifecycle / Inspect & observe). See [Q2] for hero-copy options.

### C4 — Footer / navbar links

TMP's navbar includes "Templates" and footer links to DevContainer Toolbox + Infrastructure Stack (the sister projects in the SovereignSky family). For noclickops: probably just "Docs" + "Blog" (if [Q3] = yes) + "GitHub". Footer can be minimal.

---

## Decision-points for the maintainer

These are the calls that need to be made before drafting child PLANs. Use the `[Q<N>]` IDs to give feedback.

### Branding & hosting

1. **[Q1]** Brand color. Options:
   - **[Q1a]** Terminal green (`#00ff66`-ish, dark accent in light mode, neon on black). Matches the "no clickops" CLI vibe.
   - **[Q1b]** Slate / charcoal (`#374151` primary with a single accent color). Neutral, ages well, less theme-y.
   - **[Q1c]** Reuse TMP's forest green for visual kinship with the sister project.
   - **[Q1d]** Some other color you have in mind — name it.

2. **[Q2]** Homepage structure (the *layout*, not the copy — copy is locked to noclickops). DCT's reference layout is **Hero → HomepageFeatures (3-4 cards) → QuickInstall → AiDemo**; category browsing lives on a separate `/docs/tools` page, not the homepage. Pick what shape noclickops's homepage should have:
   - **[Q2a]** Pure DCT shape: **Hero → HomepageFeatures → QuickInstall**. The category grid lives on `/docs/commands` (the generated reference page). Homepage is purely marketing; visitors click "Get Started" or "Browse Commands" to drill in. **Recommended** — matches the production sister project; lightest React surface.
   - **[Q2b]** DCT shape + category teaser on home: **Hero → HomepageFeatures → QuickInstall → CommandCategoryGrid (5 cards)**. Each category card links to its anchor on `/docs/commands`. Adds discoverability above the fold without flattening the whole 11-command grid.
   - **[Q2c]** Category-first home: **Hero → CommandCategoryGrid → CommandGrid (flat, alphabetical) → QuickInstall**. Heaviest above the fold but no hidden surface — first-time visitors see every command without scrolling past marketing copy.
   - **[Q2d]** Grouped grid home: **Hero → QuickInstall → CommandGrid grouped by category (5 H2 sections, commands as cards within each)**. One screen-scroll covers everything; no category-card layer at all. Closest to "the README, but pretty".

3. **[Q3]** Blog / changelog. Options:
   - **[Q3a]** Enable the Docusaurus blog and use it for release notes (one post per `vX.Y.Z` tag). Gives RSS, dated archive, "Recent posts" sidebar.
   - **[Q3b]** No blog; keep release notes in `CHANGELOG.md` (or in git tag messages) and don't carry the extra Docusaurus surface.

4. **[Q4]** Public URL. Options:
   - **[Q4a]** `noclickops.sovereignsky.no` (matches TMP's family; needs DNS work on your end).
   - **[Q4b]** `terchris.github.io/noclickops` (zero DNS; Docusaurus needs `baseUrl: '/noclickops/'`).
   - **[Q4c]** Different custom domain you'd want — name it.

### Plugins

5. **[Q5]** Mermaid. Options:
   - **[Q5a]** Yes — add `@docusaurus/theme-mermaid`, enable `markdown.mermaid: true`. Useful for architecture / flow diagrams in plans and `WORKFLOW.md`.
   - **[Q5b]** No — defer until we have diagrams to render.

6. **[Q6]** Search. Options:
   - **[Q6a]** Local search (`@easyops-cn/docusaurus-search-local`, same as TMP). Free, no Algolia signup, builds at deploy time.
   - **[Q6b]** No search in v1 — small docset, sidebar + browser find is enough. Add later if the docset grows.

### Existing-docs handling

7. **[Q7]** Docs entry point. The `website/docs/` folder currently contains only `ai-developer/` — there's no top-level `index.md`. Options:
   - **[Q7a]** Add `website/docs/index.md` with the README intro + a one-paragraph "where to look" pointing into `ai-developer/` and the plans tree. Becomes the URL slug `/docs/`.
   - **[Q7b]** Promote `website/docs/ai-developer/README.md` to the docs root by setting `slug: /` in its frontmatter. Avoids a new file; reuses the existing entry point.
   - **[Q7c]** Use the repo root `README.md` as the docs index via a symlink or a build-time copy step. Risky (Docusaurus + symlinks across repo boundaries get fiddly); probably skip.

8. **[Q8]** `_category_.json` files. Should we add them now to label the sidebar nicely, or let the autogenerated sidebar use raw folder names?
   - **[Q8a]** Add `_category_.json` to `website/docs/ai-developer/`, `.../plans/`, `.../plans/backlog/`, `.../plans/active/`, `.../plans/completed/` — pretty labels, controlled ordering.
   - **[Q8b]** Skip for v1; sidebar shows folder names verbatim ("ai-developer", "plans", etc.). Add later if the auto-labels look ugly.

### CI & deploy

9. **[Q9]** When does the docs site rebuild?
   - **[Q9a]** Only on changes under `website/**` and the workflow file itself (TMP's pattern, minus their template-metadata paths).
   - **[Q9b]** On every push to `main` (simpler workflow file; trivially more CI minutes).

10. **[Q10]** README + docs index drift. The current `README.md` describes install + first commands; if [Q7a] is picked, the same content lives in `website/docs/index.md`. Risk: drift.
    - **[Q10a]** Accept the drift — README is for GitHub readers, docs index is for site readers; they overlap and that's fine.
    - **[Q10b]** Add a contributor note in `PLANS.md` / `project-noclickops.md` saying "when you change install instructions, change both."
    - **[Q10c]** Build-time copy of `README.md` into `website/docs/index.md` (CI step). Cleaner but adds a moving part.

### Local dev

11. **[Q11]** Local dev workflow. TMP runs `cd website && npm install && npm start`. Options:
    - **[Q11a]** Same — document `cd website && npm install && npm start` in `CONTRIBUTING.md` (or `project-noclickops.md`); no wrapper.
    - **[Q11b]** Add a `noclickops` subcommand like `docs` that runs the dev server. Tempting but breaks the "wrap existing automation, never replicate it" rule — npm already wraps it.
    - **[Q11c]** Add a `scripts/docs-dev.sh` thin wrapper in this repo (sister of TMP's `scripts/`). Mild ergonomics for "I forgot the npm command."

### Command-grouping data model (opened by A6 + A7)

The big decisions are resolved by A7 (data source = `bin/*.sh` `SCRIPT_*`; generator = Bash, like DCT's `dev-docs.sh`). These sub-questions remain.

18. **[Q18]** Generator language. (DCT uses Bash; TMP uses TypeScript. Pick one.)
    - **[Q18a]** **Bash** (`scripts/generate-docs.sh`). Sources `lib/metadata.sh` and reuses `parse_metadata()` — single source of truth for parsing, no duplicated regex. Output JSON via `jq` (already a noclickops runtime dep). Matches DCT verbatim; matches the repo's "Bash + PowerShell siblings" idiom; matches the existing `lib/` library style. **Recommended.**
    - **[Q18b]** **TypeScript** (`scripts/generate-docs.ts`, run via `npx tsx`). Matches TMP. Re-implements the same five-field regex in TS — small (~30 lines for the parser). Downside: parsing logic now lives in two places (`lib/metadata.sh` + the TS generator); they can drift. Upside: stays inside the Node/Docusaurus toolchain, no shell-out from CI.
    - **[Q18c]** **Docusaurus plugin** (`website/plugins/load-commands/index.ts`). The plugin's `loadContent` lifecycle runs the same scanning logic and exposes the result as a Docusaurus "global data" blob the components consume directly. No on-disk JSON file. Most idiomatic for Docusaurus; downside: harder to inspect (no committed JSON to diff in PRs); doesn't write `commands.md`.

18b. **[Q18b']** When does the generator run? (Independent of [Q18] language choice.)
    - **[Q18b'-a]** Explicit CI step before `npm run build` in `deploy-docs.yml` — **DCT's pattern** (lines 56–60 of their workflow: `- name: Generate documentation data` → `run: bash .devcontainer/manage/dev-docs.sh`). Visible in CI logs; local devs run it manually before previewing. **Recommended** (matches DCT).
    - **[Q18b'-b]** `prebuild` / `prestart` npm hook in `website/package.json` — runs automatically on every local `npm start` and every CI `npm run build`. Zero new CI steps. Better local DX; slightly less visible in CI.
    - **[Q18b'-c]** Commit-time pre-commit hook that regenerates and adds the JSON + `commands.md` to the commit. Keeps the generated files always in sync on disk; adds setup burden.

19. **[Q19]** Per-command page granularity. Each card on the homepage needs *a* destination URL — pick the shape.
    - **[Q19a]** **Single generated page** `website/docs/commands.md` listing every command grouped by category (H2 per category, H3 per command, anchored). **DCT's pattern** (their `dev-docs.sh::generate_commands_md()`, ~130 lines, produces a page like [DCT's live commands.md](https://dct.sovereignsky.no/docs/commands)). One file, deep links (`#create-pr`). Cheapest to generate; renders the existing five `SCRIPT_*` fields + a collapsible `--help` block per command. **Recommended for v1**; matches what the README's "v1.0.0 surface" table already implies. Per-command sub-pages can be added later when extended metadata lands ([Q21]).
    - **[Q19b]** **One generated page per command** at `website/docs/commands/<name>.md`. Cleanest URLs, sidebar entry per command. DCT does this for *tools* (`docs/tools/<category>/<tool>.mdx`) but only because their extended metadata (logos, package arrays, related-tools) justifies the per-page real estate. With only five fields per command, 11 separate pages mostly duplicate the H3-anchor layout of Q19a — overkill for v1. Revisit after [Q21] lands extended fields.
    - **[Q19c]** **Dynamic route** (`<CommandPage>` mounted on a catch-all `/commands/[name]` via a custom Docusaurus theme component). No generated `.md` files. Most TS-heavy, hardest for a doc contributor to extend, but no codegen-output committed. Not worth the complexity for v1.

Note: all three options use the same metadata. The choice is about file layout and where rendering happens. Q19a is the strong recommendation because it matches DCT, fits 11 commands cleanly on one page, and leaves room to add Q19b-style per-command pages as a follow-up if extended metadata makes them worth the surface area.

### Out of scope (state explicitly so we don't drift later)

- Metadata-driven docs generation pipeline (deferred per B1 — revisit when the SCRIPT_CATEGORY metadata from `INVESTIGATE-uis-lessons.md` A3 lands).
- Image-zoom and Mermaid-zoom (defer; reopen if/when diagrams land).
- Multi-language i18n (single locale `en` is fine; matches TMP).
- Versioned docs (Docusaurus supports `npx docusaurus docs:version`; we don't yet have multiple shipping versions of the docs surface — release notes via [Q3] cover the "what changed" need).

---

## Risks / things that could bite us

1. **Existing relative links assume raw markdown viewing.** Most `[link](../WORKFLOW.md)` references work in Docusaurus too (it strips `.md` automatically), but some files link to *plans* files using paths like `plans/backlog/INVESTIGATE-noclickops.md` from `project-noclickops.md`. After Docusaurus renders, those resolve to `/ai-developer/plans/backlog/INVESTIGATE-noclickops` — fine, but worth a smoke test in the foundation PLAN.

2. **`CLAUDE.md` deep-links from the repo root** (e.g. `website/docs/ai-developer/project-noclickops.md`) keep working on the GitHub web UI because they're real file paths. They do **not** become hyperlinks in the rendered Docusaurus site (since `CLAUDE.md` isn't a docs file). Acceptable — `CLAUDE.md` is for tooling, not site visitors.

3. **`onBrokenLinks: 'throw'`** (TMP's setting) will fail the build if any relative link inside `docs/` resolves to nothing. The first Docusaurus build is going to find broken links — that's actually a feature for cleaning up the existing docset, but allocate time in the foundation PLAN to fix them rather than weakening to `'warn'`.

4. **`README.md` at repo root vs `docs/index.md`.** See [Q10]. Whichever option wins needs to be written down somewhere; otherwise next quarter we have two stale README-like documents.

5. **GitHub Pages settings need a manual one-time toggle.** Source = "GitHub Actions" rather than "Deploy from a branch." Easy to miss; the foundation PLAN should call it out explicitly.

6. **No `noclickops` logo or social card exists yet.** TMP ships `logo.svg`, `logo-dark.svg`, `social-card.jpg`, `favicon.ico`. v1 can use Docusaurus defaults + a 5-minute text-only SVG; better assets are a follow-up.

---

## Recommendation — phased PLAN proposal

Three child PLANs, sequenced. Each delivers something useful on its own; each commits at the end (per `project-noclickops.md` "commit per plan; PR per investigation").

### **[Q12]** PLAN-A — `website/` foundation (Docusaurus boots, existing docs render)

- Add `website/package.json`, `website/docusaurus.config.ts`, `website/sidebars.ts`, `website/tsconfig.json` (TMP-shape, slimmed per [Q5]/[Q6]).
- Add `website/src/css/custom.css` with the brand color block only (per [Q1]).
- Resolve docs entry point per [Q7] (`website/docs/index.md` or repurpose `ai-developer/README.md`).
- Add `_category_.json` files per [Q8].
- Add `node_modules/`, `website/build/`, `website/.docusaurus/` to `.gitignore`.
- Fix any broken intra-docs links surfaced by the first `npm run build` (the `onBrokenLinks: 'throw'` will flush them out).
- **Validation**: `cd website && npm install && npm run build && npm run start` shows the site locally with the full `ai-developer/` tree in the sidebar. User confirms.

### **[Q13]** PLAN-B — Public deploy (GitHub Pages + domain + CI)

- Add `.github/workflows/deploy-docs.yml` (slimmed-down TMP shape per A4).
- Add `website/static/CNAME` if [Q4a]/[Q4c] picked.
- Set `url` / `baseUrl` / `organizationName` / `projectName` in `docusaurus.config.ts` to match [Q4].
- Document the one-time GitHub Pages → "GitHub Actions" toggle in the PLAN's smoke-test instructions.
- **Validation**: push to a `docs-deploy` branch, run workflow via `workflow_dispatch`, confirm the site is reachable. Merge to `main`, confirm path-filtered rebuild fires only on `website/**` changes.

### **[Q14]** PLAN-C — Marketing homepage + generated `commands.md` (always runs)

This is the work A6 + A7 / [Q2] / [Q18] / [Q19] commit us to. Sequencing: after PLAN-A (so the site builds), parallel with or after PLAN-B (deploy). Reference implementation: DCT's `dev-docs.sh` + `src/components/{CategoryCard,CategoryGrid,ToolCard,ToolGrid,HomepageFeatures,QuickInstall}` + `src/pages/index.tsx`.

- Add `scripts/generate-docs.sh` per [Q18] (Bash recommended). The generator sources `lib/metadata.sh`, walks `bin/*.sh`, and emits:
  - `website/docs/commands.md` — single page per [Q19a]: H2 per category, H3 per command (anchored), synopsis from `SCRIPT_USAGE`, example from `SCRIPT_EXAMPLE`, collapsible `--help` block. Direct port of DCT's `generate_commands_md()` (`dev-docs.sh` lines 1100–1229), scoped down.
  - `website/src/data/commands.json` — one row per command (name, description, usage, example, category).
  - `website/src/data/categories.json` — one row per category (id, label, description) derived from `_NCO_VALID_CATEGORIES` + the lister display strings in `bin/noclickops.sh` lines 90–94.
- Wire the generator to run per [Q18b'] (CI step recommended, matching DCT).
- Build React components (`website/src/components/`), copying the *shape* of DCT's equivalents:
  - `CommandCategoryCard/` + `CommandCategoryGrid/` (rename of DCT's `CategoryCard` / `CategoryGrid`).
  - `CommandCard/` + `CommandGrid/` (rename of DCT's `ToolCard` / `ToolGrid`).
  - `HomepageFeatures/` (3-4 marketing cards: "One command per task", "Works in any repo", "Wraps existing pipelines", "No clickops") — copy adapted from `README.md` line 5.
  - `QuickInstall/` (the `curl … install.sh` one-liner in a copy-able block).
- Build `website/src/pages/index.tsx` per [Q2] layout choice. Hero copy mirrors `README.md` lines 5–7. If [Q2a] picked, only `HomepageFeatures` + `QuickInstall` appear on the homepage (lightest path).
- **Skip** these DCT pieces: `FloatingCubes`, `AiDemo`, `RelatedTools` (RelatedTools needs `SCRIPT_RELATED` from [Q21]).
- Provide a minimal placeholder logo + favicon if branding isn't ready yet (text-only SVG is fine; DCT's `cube-code-green.svg` is 5kb).
- Add a smoke check at the end of `generate-docs.sh`: count of rows in `commands.json` == count of `bin/*.sh` files (catches drift if a script slips through without metadata). Matches DCT's `count_total_scripts()` pattern (`dev-docs.sh` line 477).
- Add `scripts/` to the gitignore-untouched paths in the deploy workflow's path filter, so changes to the generator trigger a docs rebuild.
- **Validation**: run `bash scripts/generate-docs.sh` locally → `commands.md` + JSON files appear → `cd website && npm start` → confirm hero / features / install render, confirm `/docs/commands` lists all 11 commands grouped by category with anchors working. Touch a script's `SCRIPT_DESCRIPTION`, re-run the generator, confirm the change shows up. `npm run build` succeeds with `onBrokenLinks: 'throw'`.

### **[Q20]** PLAN-D — Optional polish (only if [Q3a] / [Q5a] / [Q6a] selected)

- Enable Mermaid theme + `markdown.mermaid: true` per [Q5].
- Enable local search theme per [Q6].
- Enable blog with one starter post per [Q3].
- **Validation**: each enabled feature works against the live site.

If [Q3b] + [Q5b] + [Q6b] are all picked (the maximally-minimal path), **PLAN-D is dropped entirely** and the investigation completes after PLAN-C.

---

## Open questions (track separately from the [Q] decision-points above)

1. **[Q15]** Does `noclickops` need a separate `CONTRIBUTING.md` once docs are on the website? Right now contributor info is spread across `README.md`, `CLAUDE.md`, `AGENTS.md`, and the `ai-developer/` tree. Probably out of scope for this investigation; flag for a follow-up if site structure makes the gap obvious.

2. **[Q16]** Should the docs site link back to each plan file's source on GitHub (an "Edit this page" link)? Docusaurus supports `editUrl` in the docs preset — basically free if we want it.

3. **[Q17]** Does `noclickops` want analytics on the docs site (e.g. Plausible, Umami, Google Analytics)? Easy to add later, but worth deciding before [Q4] domain is announced.

4. **[Q21]** Filed by A7: a follow-up INVESTIGATE or PLAN to extend `SCRIPT_*` metadata with the six fields listed under A7's "What's missing" — `SCRIPT_DETAILS`, `SCRIPT_FLAGS`, `SCRIPT_AUTH`, `SCRIPT_EXIT_CODES`, `SCRIPT_SEE_ALSO`, `SCRIPT_DEPENDS_ON`. Out of scope here; tracked so it doesn't get lost. Trigger: once the v1 docs site is live, the gap between what the per-command pages render and what they *should* render will be obvious.

---

## Next steps

- [ ] User reviews this investigation and marks up `[Q1]`–`[Q20]` (one-line answers per ID). After the 2026-05-29 DCT pivot, the recommended-path answers (matching DCT) are: **[Q2a]** (DCT homepage shape) · **[Q18a]** (Bash generator) · **[Q18b'-a]** (CI step) · **[Q19a]** (single `commands.md`). The other [Q]s (Q1 brand color, Q3 blog, Q4 domain, Q5 mermaid, Q6 search, Q7 docs entry, Q8 _category_.json, Q9 path filter, Q10 README drift, Q11 local-dev wrapper) are still open.
- [ ] Open questions resolved, child PLANs drafted in `plans/backlog/PLAN-A-…`, `PLAN-B-…`, `PLAN-C-…`, optionally `PLAN-D-…`. The metadata-extension work from A7 / [Q21] is filed as a separate backlog INVESTIGATE/PLAN, not a child of this one.
- [ ] PR opens when the last child PLAN of this investigation merges (per the "PR per investigation" rule in [`project-noclickops.md`](../../project-noclickops.md)).
