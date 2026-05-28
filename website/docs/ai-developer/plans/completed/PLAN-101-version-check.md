# PLAN-101: version check — tell the user when their noclickops is stale

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
>
> - [WORKFLOW.md](../../WORKFLOW.md)
> - [PLANS.md](../../PLANS.md)

## Status: Completed 2026-05-28

**Goal**: Add a "you have v1.0.0, latest is v1.0.1 — run `noclickops update`" hint to the lister, plus the `version.txt` file the hint reads from. Adopts the [DCT (devcontainer-toolbox) pattern](https://github.com/helpers-no/devcontainer-toolbox) from `.devcontainer/manage/lib/version-utils.sh`, with one addition: a 1-hour cache so the lister stays snappy.

**Last Updated**: 2026-05-28

**Investigations**: none — direct response to user feedback after v1 ship.

**Depends on**: PLAN-002 (the lister is what shows the hint), PLAN-001 (`lib/` + sourcing-guards pattern).

**Priority**: Medium — the v1 surface works without it; this is polish.

---

## Problem

After v1 ships, users running an old `noclickops` have no way to know they're behind. There's no announce channel, no auto-update, no version awareness. The only way to know is to read GitHub or notice that `noclickops update` produces commits.

DCT solved this for its `dev-*` commands. Adopting the pattern keeps noclickops feeling alive without becoming nagware.

---

## What it delivers

### `version.txt` at repo root

One line, no newline tricks. The maintainer bumps it on each release (semver). Initial value: `1.0.0` (the v1 we just merged).

### `lib/version.{sh,ps1}` — the version helpers

```text
nco_load_version           # → sets NCO_VERSION from version.txt
nco_check_remote           # → sets NCO_REMOTE_VERSION if cache says newer
nco_show_update_hint       # → prints '⬆ Update available: vX' if applicable
```

Behaviour:

- **Local version** read from `$NOCLICKOPS_DIR/version.txt`. Falls back to `"unknown"` if missing (so a malformed install doesn't crash the lister).
- **Remote check** hits `https://raw.githubusercontent.com/<user>/<repo>/main/version.txt` — where `<user>/<repo>` is **derived from `$NOCLICKOPS_DIR`'s `origin` remote**, the same way `lib/azdo.sh` derives target-repo identity. A fork at `alice/noclickops` checks alice's main, not the original maintainer's. No hardcoded identity in any noclickops code. Curl with `--connect-timeout 2 --max-time 4`. Failure (network down, no origin remote, non-GitHub upstream) is silent — no warning, no hint.
- **Cache** at `$NOCLICKOPS_DIR/.version-cache`: one line, `<unix-ts> <version>`. TTL 1 hour. Eliminates the 2s-on-every-call latency DCT pays.
- **Cache invalidation**: `bin/update.sh` `rm -f`s the cache after pulling, so the next `noclickops` call sees fresh state.
- **Env override** `NCO_VERSION_CHECK_URL` lets tests point at a local `file://` URL instead of github.com.

### Lister change

`bin/noclickops.sh`:

```text
noclickops v1.0.0 — portable script suite for developers
Install: /Users/.../.noclickops

Meta
  ...
```

If a newer version is detected, an extra line at the end:

```text
Run 'noclickops <cmd> --help' for usage details, e.g.:
  noclickops update --help

⬆ Update available: v1.0.1 — run 'noclickops update'
```

The hint goes at the bottom (most visible — last thing scrolled past). The version in the header confirms the **current** state regardless of update status.

### `.gitignore`

`.version-cache` is per-install state; never committed. Add a `.gitignore` at the repo root (currently absent).

---

## Phases

1. `version.txt` (= `1.0.0`).
2. `.gitignore`.
3. `lib/version.{sh,ps1}` with the three helpers + cache logic.
4. `bin/noclickops.{sh,ps1}` — source `version.sh`, emit version in header, emit hint at bottom.
5. `bin/update.{sh,ps1}` — clear `.version-cache` after pull.
6. `tests/test-PLAN-101-version-check.sh` — uses `NCO_VERSION_CHECK_URL=file://…` to stub the remote check.

---

## Validation criteria

- `noclickops` (no args) shows `noclickops vX.Y.Z` in the header line.
- With a stubbed remote URL pointing at a `version.txt` containing a different version, the lister shows the `⬆ Update available` hint at the bottom.
- With a stubbed remote that matches the local version, no hint.
- Cache file is written after a fetch; subsequent calls within 1h skip the network (verifiable by stubbing a URL that doesn't exist — the second call still shows the cached hint).
- `bin/update.sh` removes the cache file after a successful pull.
- Network failure path: lister still runs; no hint, no warning.
- Portability grep stays clean.

---

## Out of scope

- **Auto-update.** The hint nudges; doesn't auto-pull. User-initiated update keeps things explicit.
- **Background check.** No daemon, no `&`. Synchronous fetch with a 2s timeout + 4s max; cache makes the amortised cost negligible.
- **Multiple-channel** (stable / beta / nightly). One channel: `main`. Bumping version.txt is a release.
- **Notification on `update` command.** `update` already does what's needed; the hint shows during the next lister call.

---

## Completion notes (2026-05-28)

Six-phase ship on `feat/version-check`.

**Tests** — `tests/test-PLAN-101-version-check.sh`, 18 tests:

| Group | Count | Highlights |
| --- | --- | --- |
| `nco_load_version` | 2 | Reads `version.txt`; falls back to `"unknown"` |
| `nco_check_remote` with stubbed URL | 7 | newer-than-local → set; cache written; cache hit within TTL; cache cleared + URL gone → empty; equal → empty; expired cache → refetch; malformed cache → falls through |
| `nco_show_update_hint` | 3 | Prints when set; tells user the command; silent when unset |
| Lister + `update.sh` integration | 2 | Header shows `vX.Y.Z`; `update.sh` has cache-busting `rm` |
| `_nco_derive_check_url` (fork-friendly URL derivation) | 3 | https origin → raw URL; ssh origin → raw URL; non-GitHub origin → non-zero (silent skip) |
| Anti-regression sweep | 1 | No literal `terchris/noclickops` in `lib/version.{sh,ps1}` |

**`tests/test-portability.sh` expanded** to guard against **both kinds of identity leak**, not just target-tenant. Same shape, two greps now:

```text
✓ no target-tenant identity (ExampleOrg/FrontendPlatform/JKL900X016) in bin|lib|templates|shell
✓ no hardcoded noclickops-own-repo identity (terchris/noclickops) in bin|lib|templates|shell
```

**Aggregate**: `tests/run-all.sh` is now **285 tests, 0 failed, 0 skipped** (was 266 after PLAN-010).

**Bugs caught mid-test (good ones)**:

1. **User-flagged: hardcoded `terchris/noclickops` in `lib/version.{sh,ps1}`.** The first draft had `NCO_VERSION_CHECK_URL` default to that URL — same bad pattern that PLAN-003 fixed for target-tenant identity, repeated for noclickops's OWN identity. Replaced with `_nco_derive_check_url` that parses `git -C $NOCLICKOPS_DIR remote get-url origin`. Forks now self-check correctly: alice/noclickops checks alice's main, not the original maintainer's.

2. **`templates/welcome.txt` had the same leak** — `Source: https://github.com/terchris/noclickops`. The expanded portability test caught it. Reworded to `Source: see  git -C ~/.noclickops remote get-url origin` so the user discovers their own upstream from their own install.

3. **Test infrastructure bug**: my first attempt at the derivation tests did `export NOCLICKOPS_DIR=<fixture>` BEFORE sourcing `paths.sh`, but `paths.sh` resolves `NOCLICKOPS_DIR` from `BASH_SOURCE` and overrides any pre-set value (by design — bin/ scripts need a fixed answer). Fix: assign `NOCLICKOPS_DIR` AFTER sourcing `paths.sh`; `version.sh`'s `_NCO_PATHS_LOADED` guard prevents re-sourcing and clobbering.

**Visual confirmation**:

```text
noclickops v1.0.0 — portable script suite for developers
Install: /Users/.../.noclickops
...
```

When a stub remote URL points at a different version, an extra trailing line:

```text
⬆ Update available: v1.0.5 — run 'noclickops update'
```

**version.txt = `1.0.0`** — declares the just-merged v1 as the baseline. Future bumps from here: patch → 1.0.1, feature → 1.1.0.

**PowerShell port unverified on Mac** as usual; the derivation logic mirrors bash via PowerShell regex matching.

**Pending separate PR**: `fix/install-sh-silent-prompt` (the `2>/dev/null` swallowing the prompt during `curl | bash`). Not bundled with this PR — user chose to keep them separate.
