# 1PRIORITY — what to work on next

> Triage view across the open work in `plans/backlog/`. Tiered by what to do **next**, what is
> deferred pending a prerequisite, and what is parked. This is a triage tool, not a roadmap —
> see [PLANS.md → "Keeping `backlog/1PRIORITY.md` current"](../../PLANS.md).

**Last Updated**: 2026-08-30
**Snapshot**: v1.7.6 · default branch `main` · plans: **0 active / 5 backlog / 29 completed** ·
open PRs: **14** (all Dependabot, `website/`) · open issues: **0**

---

## How to use this doc

Read Tier 1. If Tier 1 is empty, read Tier 2. Each row states the *evidence* for its rank and the
*one* thing that would unblock or close it. A row moves down only when its blocker is real and
named, never because it is uncomfortable.

Nothing is invented here. Every row below is something already in the tree that is either
contradictory, stale, or scoped-and-unstarted.

---

## Tier 1 — decide this first (blocks other work)

### The PowerShell surface contradicts itself, and it is shipped

The repo says three different things about PowerShell at the same time:

| Source | Claim |
|---|---|
| [`README.md`](../../../../../README.md) line 103 (v1.7.6) | "PowerShell siblings are **no longer shipped** (Bash is the supported surface)" |
| [`CLAUDE.md`](../../../../../CLAUDE.md) line 28 | "**Multi-OS by default.** Every script ships `.sh` … and `.ps1` … siblings." |
| The tree | 12 `bin/*.ps1`, `install.ps1`, and 8 `lib/*.ps1` are present and tracked |

They are not dead files. `install.sh`'s sparse-checkout set is `/bin/ /lib/ /templates/ /shell/
/version.txt`, so **every `.ps1` is checked out onto every install**, including installs whose
README says PowerShell is gone.

Worse, the three that a Windows user would actually run are on the pre-v2 code path:

- `bin/info.ps1:25`, `bin/logs.ps1:28`, `bin/shell.ps1:28` all source `lib/service.ps1` — the **v1**
  lib, which targets the old single-repo layout.
- Their Bash siblings moved to `lib/service-v2.sh` in PLAN-B / PLAN-D (both in `completed/`).
- There is **no `lib/service-v2.ps1`**. The PowerShell half of the v2 rewrite was never written.

So a Windows user running `noclickops info` today gets v1 behaviour against a layout that v2
replaced — silently, with no version guard.

**Decision needed (a human call, not a refactor):** either delete the `.ps1` surface and the
installer's Windows path, and fix `CLAUDE.md` line 28 to match `README.md` — or keep multi-OS,
write `lib/service-v2.ps1`, and port `info`/`logs`/`shell`. Both are defensible. Shipping both
claims is not.

**Blocks:** [PLAN-G](PLAN-G-v1-cleanup.md), whose scope is wrong until this is settled (below).

---

## Tier 2 — ready once Tier 1 lands

### [PLAN-G — v1 cleanup + the 2.0.0 bump](PLAN-G-v1-cleanup.md)

Two things about this plan are out of date:

1. **Its prerequisite is already met.** PLAN-G says it waits on v2 being "demonstrably verified
   working end-to-end … Currently waiting on full verification (some Reader-access constraints)".
   But [`v2-smoke-test.md`](../../../contributors/v2-smoke-test.md) → Run history records a full
   clean run on v1.6.5 across all four phases with the verdict **PASS**. The prerequisite text is
   stale and should be struck.
2. **The 2.0.0 promotion it assumes never happened.** That same run-history entry ends "promoted to
   2.0.0 in a follow-up commit". `version.txt` says **1.7.6**. Either the promotion was reverted or
   the note was aspirational; the doc and the version file disagree and one of them is wrong.

**And its scope is wrong.** PLAN-G's goal is to "remove the orphan v1 lib files (`lib/service.sh`,
`lib/service.ps1`)". `lib/service.ps1` is **not orphan** — three `bin/*.ps1` commands source it
(see Tier 1). Deleting it as written breaks the PowerShell commands outright. `lib/service.sh` is
closer to orphan: no `bin/*.sh` sources it, only `tests/test-PLAN-008-info.sh` does, which PLAN-G
already plans to retire.

**One thing that unblocks it:** the Tier 1 decision. Then rewrite PLAN-G's Prerequisites and its
`lib/service.ps1` line, and ship it as the 2.0.0 PR.

---

## Tier 3 — real maintenance, not blocked, not urgent

### 14 open Dependabot PRs, all `website/`

`#21` (launch-editor) has been open since **2026-06-19**; the newest is `#38`. None have been
triaged, merged, or closed with a reason. All are `website/` build-time dependencies — none reach
`bin/`, `lib/`, or `templates/`, which is why this is Tier 3 and not Tier 1. Some carry security
advisories (`dompurify`, `postcss`, `undici`, `body-parser`).

**One thing that closes it:** one batch pass — merge what CI passes, close what the docs build does
not need, and record the decision so the queue does not silently rebuild.

---

## Tier 4 — scoped, ready, deliberately deferred

### [INVESTIGATE-plans-and-scaffolding](INVESTIGATE-plans-and-scaffolding.md) — PLAN-B / C / D

Status line says "4 PLANs scoped, ready to ship". One of the four has shipped:
**PLAN-A → [PLAN-106-slim-install](../completed/PLAN-106-slim-install.md)** (it names itself as
that entry). Its checklist item at line 177 is still unchecked — a stale box, not stale work.

The remaining three (`scaffold-ai-developer`, `scaffold-docs`, `update-ai-developer`) are fully
scoped and unstarted. They add three new user-facing commands, which is a minor-version surface
change — landing them **before** 2.0.0 would widen the very surface PLAN-G exists to narrow.

**Deferred until:** 2.0.0 ships. Then re-rank to Tier 2.

> ⚠️ **Naming collision to fix while you are in here.** There are two unrelated `PLAN-A/B/C/D`
> letter series: this investigation's (A = slim install, B/C/D = scaffolding) and
> INVESTIGATE-new-target-structure's, which shipped as `PLAN-A-service-discovery`,
> `PLAN-B-info-rewrite`, `PLAN-C-deploy-rewrite`, `PLAN-D-logs-shell-rewrite` in `completed/`.
> "PLAN-B" is ambiguous in this repo today. Re-letter this investigation's remaining three.

---

## Tier 5 — parked

| Item | Why it is parked |
|---|---|
| [PLAN-watch-live-deploy](PLAN-watch-live-deploy.md) | Real user problem (first public-endpoint deploy is ~60 min behind a WAF registration). Needs no new prerequisite — it is parked on *value*, not blockers: nobody has asked for it since 2026-05-29. Promote on the first real request. |
| [INVESTIGATE-uis-lessons](INVESTIGATE-uis-lessons.md) | A survey of a sister project. It has no child PLANs and nothing depends on it. Its findings were meant to feed edits back into INVESTIGATE-noclickops; check whether they did before ever reopening it. |
| [INVESTIGATE-noclickops](INVESTIGATE-noclickops.md) | The parent v1 design. Substantially delivered — 12 commands ship. It stays in `backlog/` mainly because nobody has decided what "done" means for it. Closing it is a 2.0.0 housekeeping task, not investigation work. |

---

## What this file does not cover

Fleet coordination. That lives in `terchris/urb-agents` (read remotely, path-scoped), not here.
This file is the project-side triage document; `fleet/noclickops/status.md` in that repo is its
one-screen snapshot.
