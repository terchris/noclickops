# PLAN-003: `create-pr` + `merge-pr`

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-28

**Goal**: First real workflow commands. Wrap `az repos pr create` / `az repos pr update` so the developer never has to click through the Azure DevOps web UI to open or complete a PR.

**Last Updated**: 2026-05-28

**Investigations**:

- [INVESTIGATE-noclickops.md](../backlog/INVESTIGATE-noclickops.md) → "Outline of v1 PLANs" → PLAN-003

**Depends on**: PLAN-001, PLAN-002.

**Priority**: High — this is the most-used command in the suite. Branch → commit → push → PR → merge is the daily flow.

---

## Problem

Today, developers either (a) click around the Azure DevOps web UI to open and complete PRs, or (b) copy-paste an `az repos pr create` invocation with the project's specific repo/org names hardcoded. The FRT repo has its own `website/scripts/create-pr.sh` + `merge-pr.sh` which hardcode `JKL900X016-NerdMeet` — useful inside that repo, useless anywhere else.

noclickops's promise is "same command works in every repo you `cd` into." For PRs that means **deriving the ADO context from the target repo's git remote** rather than hardcoding it.

---

## What it delivers

### New `lib/` helper

**`lib/azdo.{sh,ps1}`** — the Azure DevOps target-context derivation, shared by every ADO-touching script (PLAN-003 / PLAN-004 / PLAN-007 / …).

Exports:

- `AZDO_ORG` — e.g. `ExampleOrg`
- `AZDO_ORG_URL` — e.g. `https://dev.azure.com/ExampleOrg`
- `AZDO_PROJECT` — e.g. `FrontendPlatform`
- `AZDO_REPO` — e.g. `JKL900X016-NerdMeet`

Derived by parsing `git remote get-url origin` for the target repo. Supports:

- `https://[user@]dev.azure.com/<org>/<project>/_git/<repo>` (with or without `.git` suffix)
- `git@ssh.dev.azure.com:v3/<org>/<project>/<repo>` (with or without `.git` suffix)

Dies with a clear error if the remote URL doesn't look like Azure DevOps. **No fallback to a specific repo name** — portability is non-negotiable.

Also provides `require_az`: ensures `az` is installed, logged in, the `azure-devops` extension is present, and `az devops configure --defaults` is set to the derived org+project.

### `bin/create-pr.{sh,ps1}`

```text
noclickops create-pr "<title>" ["<description>"]
```

- Refuses to run on `main` ("create a feature branch first").
- Pushes the branch + sets upstream if no tracking branch yet.
- `az repos pr create` against the derived repo.
- Prints PR id, PR URL, and the next-step `noclickops merge-pr <id>` hint.

### `bin/merge-pr.{sh,ps1}`

```text
noclickops merge-pr <pr-id>
```

- `az repos pr update --status completed --squash true --delete-source-branch true` (squash is mandatory in the target repo's branch policy).
- Polls `az repos pr show --query status` until `completed` or `abandoned` (max ~2 minutes).
- Switches back to `main`, fetches, fast-forwards, deletes the local feature branch on clean ff.
- On non-ff (local main diverged): warns clearly, suggests `git reset --hard origin/main` only if local main has nothing worth keeping. Does **not** auto-reset.

---

## Phases

1. `lib/azdo.{sh,ps1}` — derivation + `require_az`.
2. `bin/create-pr.{sh,ps1}`.
3. `bin/merge-pr.{sh,ps1}`.
4. Smoke test:
   - URL derivation across 3 URL formats (https + auth, https plain, ssh).
   - Error message when remote isn't ADO.
   - `--help` for both new commands prints metadata-driven block.
   - Lister now shows the "Git / pull requests" section with both commands.
   - `create-pr` with no args / on `main` fails with the right error (no `az` call).

End-to-end PR creation/merge against a real ADO repo is **deferred** — it would require pushing actual PRs and isn't something a smoke test should do automatically.

---

## Validation criteria

- `lib/azdo.sh` derives the right org/project/repo for all three URL forms.
- `lib/azdo.sh` errors with a clear hint when the remote isn't recognised.
- `noclickops` lister shows the "Git / pull requests" section with `create-pr`, `merge-pr`.
- `noclickops create-pr --help` and `noclickops merge-pr --help` print uniform help blocks.
- `noclickops create-pr` (no title) errors cleanly with usage; does not invoke `az`.
- `noclickops create-pr "title"` on `main` errors with the feature-branch hint; does not invoke `az`.
- No hardcoded repo / org / project names anywhere in `bin/` or `lib/` (grep check).

---

## Completion notes (2026-05-28)

All four phases shipped on `feature/ai-developer-bootstrap`.

**Smoke test results**:

| # | Test | Result |
| --- | --- | --- |
| 1 | Lister shows new "Git / pull requests" section with both commands | ✅ |
| 2 | `create-pr --help` prints metadata block (quote handling for embedded `"`) | ✅ |
| 3 | `merge-pr --help` likewise | ✅ |
| 4 | `create-pr` (no title) errors with usage; no `az` call | ✅ |
| 5 | `merge-pr` (no id) errors with usage | ✅ |
| 6 | URL derivation works for `https-plain`, `https-with-user`, `https-with-dotgit`, `ssh-form`, and an unrelated org | ✅ |
| 7 | GitHub URL rejected with the documented error and exit code | ✅ |
| 8 | `grep -E 'ExampleOrg\|FrontendPlatform\|JKL900X016' bin/ lib/` returns nothing | ✅ |
| 9 | `create-pr` on `main` errors with the feature-branch hint before any `az` call | ✅ |

**Bugs found and fixed during the smoke test**:

1. **`lib/metadata.sh::parse_metadata` mangled values containing embedded quotes**.
   `SCRIPT_USAGE='noclickops create-pr "<title>" ["<description>"]'` got truncated at the first `"`. The old regex (`"?([^"]*)"?`) assumed double-quoted values with no embedded double quotes. Replaced with `_extract_field`: strips the `FIELD=` prefix, then strips the outermost matching quote pair (single OR double). Now handles both quote styles freely. Retroactively improves PLAN-001/002 scripts (they used double quotes only, so weren't affected, but the fix is forward-compatible).
2. **Hardcoded example names in `lib/azdo.{sh,ps1}` docstrings**.
   Comments mentioned `ExampleOrg` / `FrontendPlatform` / `JKL900X016-NerdMeet` as illustrative examples. Not logic — but a strict portability grep flagged them. Swapped for generic `AcmeCorp` / `Platform` / `some-app` so the grep guard stays clean and the docstrings stop implying a specific tenant.

**Test-infrastructure gotcha (not a code bug)**: the first run had `(...)` subshell tests source `lib/azdo.sh` directly from a zsh-driven harness; `BASH_SOURCE` is bash-only, so the path resolution collapsed. Re-running tests under `bash -c '...'` resolved this. Real-world usage never hits this path — bin/ scripts have `#!/usr/bin/env bash` so the kernel runs them in bash, and lib/ sourcing happens from inside bash.

**End-to-end PR creation/merge against a real ADO repo is deferred** — out of scope for an automated smoke test.
