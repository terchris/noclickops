---
title: Contributors
sidebar_position: 0
---

# Contributors

Internal docs for people working **on** noClickOps — not just using it. If you're using noClickOps as a developer in your daily flow, start with [the docs landing page](../) instead.

## What lives here

| Doc | When to read it |
|---|---|
| [Target layout reference](./target-layout-reference.md) | Before changing any command that touches an Azure DevOps repo. Documents the Red Cross ADO + Azure layout noclickops targets, as observed in the wild. Re-verify after every Azure-engineer-side change. |
| [`lib/service-v2.sh`](./lib-service-v2.md) | When writing or modifying v2 commands. Documents the v2 discovery library — public API, discovery-vs-derivation-vs-override pattern, test shims, and the manual smoke procedure. |

## What's not here yet (but will be, as the questions come up)

- **How to add a new command** — copy `bin/<existing>.sh`, fill in the `SCRIPT_*` metadata block, add tests, commit per the PLAN workflow.
- **Release flow** — semver bumps in `version.txt`, branch + PR + merge, deploy-via-CI.
- **Slim install internals** — the sparse-checkout + shallow-clone rationale, sparse-set evolution (v1.5.1 → v1.5.4).
- **Testing** — what `tests/run-all.sh` covers, when to add a new test file.
- **Docs generator (`scripts/generate-docs.sh`)** — how SCRIPT_* metadata becomes per-command pages + how to extend it.

These will land here when someone needs them. Open an issue (or just ask) if you hit a contributor question this section doesn't answer.

## Related reading

- [AI Developer Workflow](../ai-developer/) — the plan-based development convention this repo uses (`INVESTIGATE-*` → `PLAN-*` → implement → ship). Contributor docs *describe* the noclickops codebase; AI-developer docs describe *how we change* it.
- The repo-root [README](https://github.com/terchris/noclickops/blob/main/README.md), [CLAUDE.md](https://github.com/terchris/noclickops/blob/main/CLAUDE.md), and [AGENTS.md](https://github.com/terchris/noclickops/blob/main/AGENTS.md) — entry points for AI tooling that auto-loads project context.
