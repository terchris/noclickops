# CLAUDE.md

This repo (`noclickops`) is a **portable script suite** for developers who'd rather type a command than click through web UIs. It's installed once per developer machine and operates on whichever git repo the developer is currently in. It wraps existing pipelines / APIs; it never re-implements them.

The repo uses a structured AI-developer workflow.

**Before doing anything else, read the docs in [`website/docs/ai-developer/`](website/docs/ai-developer/).**

## Start here (in order)

1. **[website/docs/ai-developer/project-noclickops.md](website/docs/ai-developer/project-noclickops.md)** — the authoritative description of *this* repo: what `noclickops` is, the proposed repo structure, the conventions, and the non-negotiable rules and contracts. **Read this first.**
2. **[website/docs/ai-developer/README.md](website/docs/ai-developer/README.md)** — how the AI-developer system works and the full reading order.
3. Reference these as needed — **only if `project-noclickops.md` says they apply**:
   - [WORKFLOW.md](website/docs/ai-developer/WORKFLOW.md) — idea → plan → implementation flow
   - [PLANS.md](website/docs/ai-developer/PLANS.md) — plan/investigation structure and templates
   - [GIT.md](website/docs/ai-developer/GIT.md) — git safety rules; this repo is **GitHub** (use the GitHub `gh` operations section)
   - [AZURE-DEVOPS.md](website/docs/ai-developer/AZURE-DEVOPS.md) — does **not** apply to this repo (we're on GitHub). It's relevant only because `noclickops` itself *operates against* Azure DevOps repos too.
   - [TALK.md](website/docs/ai-developer/TALK.md), [WORKTREE.md](website/docs/ai-developer/WORKTREE.md), [DEVCONTAINER.md](website/docs/ai-developer/DEVCONTAINER.md) (note: there is **no** devcontainer here)

Plans live in [`website/docs/ai-developer/plans/`](website/docs/ai-developer/plans/) (`backlog/`, `active/`, `completed/`). The v1 design is in [`INVESTIGATE-noclickops.md`](website/docs/ai-developer/plans/backlog/INVESTIGATE-noclickops.md) — read it before making changes to any of the script work it covers.

## Always-critical rules (full list in `project-noclickops.md` → "Key rules and contracts")

- **Never commit directly to `main`.** Always branch → commit → push → pull request → merge — the PR is the review gate. This repo is GitHub; use `gh pr create` / `gh pr merge` (see `GIT.md`).
- **Commit per plan; PR per investigation.** Plans within an investigation accumulate commits on the branch; the PR opens when the investigation is finished.
- **Scripts must be portable.** They operate against *any* target repo the developer `cd`s into. No hard-coded repo names, org names, or other target-repo identity values — derive at runtime.
- **Wrap, never replicate.** `noclickops` triggers pipelines, GitHub APIs, ADO APIs. It does not re-implement what those systems do.
- **Multi-OS by default.** Every script ships `.sh` (Bash, for macOS/Linux/WSL/Git Bash) and `.ps1` (PowerShell, native Windows) siblings.
