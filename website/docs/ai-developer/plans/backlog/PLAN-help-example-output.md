# PLAN — `--help` and docs pages show captured example output per command

> **IMPLEMENTATION RULES:** Before implementing this plan, read and follow:
> - [WORKFLOW.md](../../WORKFLOW.md) — the implementation process
> - [PLANS.md](../../PLANS.md) — plan structure and best practices

## Status: Backlog

**Goal**: Every command's `--help` output and generated docs page shows a real captured example of what the command's successful output looks like. Captured during release-gate smoke runs, redacted via `terchris/redaction-map.md`, stored in a `SCRIPT_EXAMPLE_OUTPUT` field in each `bin/<cmd>.sh`.

**Last Updated**: 2026-05-29

**Driver**: User feedback from the v1.6.x live smoke session (2026-05-29). New users reading `--help` or the docs site can't picture what a command actually does — they have to run it to find out. For multi-step commands (`add-service`, `deploy`), that's costly: a failed run leaves them uncertain about what success even looks like. Captured examples fix this.

**Prerequisites**:
- v2 is demonstrably working end-to-end (so the captured examples reflect reality, not a half-working v2 state). Gated on the same verification PLAN-G is gated on.
- The release-gate smoke procedure (`website/docs/contributors/v2-smoke-test.md`) is the natural capture point.

**Branch**: standalone — `feat/help-example-output`. Single PR. Version bump 2.0.x → 2.1.0 (minor feature add) at the end.

---

## What changes

### 1. New metadata field: `SCRIPT_EXAMPLE_OUTPUT`

Add to the `--- noclickops metadata ---` block at the top of each `bin/<cmd>.sh`, alongside `SCRIPT_DESCRIPTION` / `SCRIPT_USAGE` / `SCRIPT_FLAGS`:

```bash
SCRIPT_EXAMPLE_OUTPUT='
Service: frontend (test)
────────────────────────────────────────
  Folder:             /path/to/repo/services/frontend

IaC repo (engineer-owned):
  App name (IaC):     abc100001
  ...
  Public URL:         https://frontend.example.cloud

Live state (Azure):
  Container app:      ca-abc100001-frontend
  Status:             Running
  ...
'
```

Multi-line bash string. Values use the public/redacted placeholders from `terchris/redaction-map.md`, not real customer identifiers.

### 2. `--help` renders the captured example

`lib/metadata.sh`'s `show_help` function adds a new section after the existing ones:

```
Example output:
  Service: frontend (test)
  ────────────────────────────────────────
    Folder:             /path/to/repo/services/frontend
  ...
```

Skip the section when `SCRIPT_EXAMPLE_OUTPUT` is empty (e.g. for commands that have no meaningful output — the lister, maybe `update`).

### 3. Docs generator includes the example

`scripts/generate-docs.sh` adds an "Example output" section to each command's MDX page (`website/docs/commands/<cmd>.mdx`), rendered as a fenced code block. Same content as `--help` but with markdown styling.

### 4. Smoke-test capture step

Update `website/docs/contributors/v2-smoke-test.md` to add a per-command capture step:

```bash
# For each command exercised during the smoke:
COMMAND_OUTPUT=$(noclickops <cmd> <args> 2>&1)
# Apply redaction substitutions from terchris/redaction-map.md
REDACTED=$(printf '%s' "$COMMAND_OUTPUT" | <perl/sed pipeline matching the redaction map>)
# Compare REDACTED against the current SCRIPT_EXAMPLE_OUTPUT in bin/<cmd>.sh.
# If different: update bin/<cmd>.sh's SCRIPT_EXAMPLE_OUTPUT.
```

A small helper script `scripts/refresh-example-output.sh` automates this:

```bash
scripts/refresh-example-output.sh info frontend test
# Captures `noclickops info frontend test`, redacts, prints a diff against current SCRIPT_EXAMPLE_OUTPUT.
# With --apply: also writes the new value into bin/info.sh.
```

The smoke procedure documents which commands to refresh per release.

---

## Phase 1: Schema + render

### Tasks

- [ ] 1.1 In `lib/metadata.sh`, extend the metadata parser to recognize `SCRIPT_EXAMPLE_OUTPUT`. Multi-line bash strings are read at-source-time (the bash interpreter handles them); the parser just needs to know the field name + render it.
- [ ] 1.2 Update `show_help` to render the new section. Order:
  1. Header (`noclickops <cmd> v<ver>`)
  2. Description
  3. Details
  4. Category + tags
  5. Usage
  6. Flags
  7. Example invocation (`SCRIPT_EXAMPLE` — existing)
  8. **Example output (`SCRIPT_EXAMPLE_OUTPUT` — NEW)**
  9. Auth
  10. Depends on
  11. See also
  12. Exit codes
- [ ] 1.3 Add a placeholder `SCRIPT_EXAMPLE_OUTPUT=''` to every `bin/<cmd>.sh` (12 files). Empty is fine for v1 of this plan — values get filled by Phase 3.
- [ ] 1.4 Tests in tests/test-PLAN-101-version-check.sh (or wherever the metadata-block tests live): `--help` renders an empty Example output section when the field is empty (or omits the section entirely — decide).

### Validation

`noclickops info --help` shows the new (empty) section in the right position. `bash tests/run-all.sh` green.

User confirms phase is complete.

---

## Phase 2: Docs generator

### Tasks

- [ ] 2.1 In `scripts/generate-docs.sh`, add parsing for `SCRIPT_EXAMPLE_OUTPUT` (multi-line string extraction from the bash source).
- [ ] 2.2 Emit a `## Example output` section in each `website/docs/commands/<cmd>.mdx`, fenced as `text` or `bash` depending on content. Use `text` to avoid MDX trying to interpret characters inside the output.
- [ ] 2.3 Verify in the `commands.json` data file (used by the homepage's CommandCategoryGrid) that the new field is exported so future homepage tweaks can use it.
- [ ] 2.4 `cd website && npm run build` clean. Visit `/docs/commands/info` (or any command) in a local serve, confirm the Example output section renders.

### Validation

User confirms phase is complete.

---

## Phase 3: Capture helper + first batch

### Tasks

- [ ] 3.1 Create `scripts/refresh-example-output.sh`:
  - Args: `<cmd> [<args>...]`
  - Runs `noclickops <cmd> <args>` capturing stdout+stderr.
  - Pipes through `perl -i -pe '...'` with the redaction-map substitutions (load from `terchris/redaction-map.md`'s table).
  - Diffs the result against the current `SCRIPT_EXAMPLE_OUTPUT` in `bin/<cmd>.sh`.
  - With `--apply`: writes the new value (replacing the existing `SCRIPT_EXAMPLE_OUTPUT=...` block in the source).
- [ ] 3.2 Run the helper for each of the 10-ish commands that have meaningful output (lister + update may be exceptions; verify):
  - info / logs / shell / status / deploy / add-service / clean-sample / create-pr / merge-pr / sync-lovable
  - Use real-but-redacted captures from the most recent smoke run.
- [ ] 3.3 Commit each `bin/<cmd>.sh` with the new `SCRIPT_EXAMPLE_OUTPUT` value populated.

### Validation

`noclickops <cmd> --help` for each command shows a meaningful Example output section. Docs site renders the same. User confirms phase is complete.

---

## Phase 4: Smoke procedure update + version bump

### Tasks

- [ ] 4.1 Update `website/docs/contributors/v2-smoke-test.md`:
  - Add a "Refresh captured examples" sub-step at the end of Phase 1 (read-only commands) and Phase 4 (deploy commands).
  - Reference `scripts/refresh-example-output.sh` as the refresh tool.
  - Note: this is part of the release-gate; outputs that change unexpectedly are a regression signal.
- [ ] 4.2 Bump `version.txt` → `2.1.0` (or whatever's current + 0.1.0 — minor feature add).

### Validation

User confirms phase is complete.

---

## Acceptance Criteria

- [ ] Every `bin/<cmd>.sh` has a `SCRIPT_EXAMPLE_OUTPUT` field (10-12 of them populated, rest may be empty if no useful output)
- [ ] `noclickops <cmd> --help` for each populated command shows the new Example output section
- [ ] The docs site renders the Example output section in each command's page
- [ ] `scripts/refresh-example-output.sh <cmd>` exists, works, and is documented in `v2-smoke-test.md`
- [ ] `tests/run-all.sh` green
- [ ] `version.txt` shows the bumped value

## Files to Modify

- `lib/metadata.sh` (parse + render new field)
- `scripts/generate-docs.sh` (emit MDX section)
- `scripts/refresh-example-output.sh` (new)
- `bin/info.sh`, `logs.sh`, `shell.sh`, `status.sh`, `deploy.sh`, `add-service.sh`, `clean-sample.sh`, `create-pr.sh`, `merge-pr.sh`, `sync-lovable.sh`, `update.sh` (add field + values)
- `bin/noclickops.sh` (the lister — may be a special case)
- `tests/test-PLAN-101-version-check.sh` or equivalent (metadata-block tests)
- `website/docs/contributors/v2-smoke-test.md` (capture step)
- `version.txt`

## Implementation Notes

### Multi-line bash string handling

Bash single-quoted multi-line strings work cleanly (`'...'`), with the caveat that they can't contain a literal `'`. For outputs that contain quotes, use a heredoc-style alternative or escape:

```bash
SCRIPT_EXAMPLE_OUTPUT=$(cat <<'EOF'
Service: frontend (test)
...
EOF
)
```

Decision during implementation: heredoc style is cleaner for multi-line + may contain quotes.

### Output drift detection

The natural way to catch drift: a CI check that runs `scripts/refresh-example-output.sh --check <cmd>` against canned fixtures and fails if the formatted output doesn't match the stored `SCRIPT_EXAMPLE_OUTPUT`. Out of scope for v1 of this plan (manual smoke is the check); file as a follow-up if drift becomes a real problem.

### Why redact

Captured output from a real smoke against the live Red Cross repo contains real subscription IDs, RG names, etc. The redaction-map (`terchris/redaction-map.md`) defines the canonical real↔placeholder substitutions. Applying them before storing in `SCRIPT_EXAMPLE_OUTPUT` keeps customer identifiers out of the public docs/--help while preserving the realistic shape.

### Smoke-as-source-of-truth

This plan tightens the link between the smoke procedure and the published docs. Every release-gate smoke run becomes both a verification AND a doc-refresh trigger. That's the whole point — keep the user-facing artifacts honest by tying them to the validation procedure.

### Out of scope

- Per-flag example outputs (`info --quiet` vs `info --verbose` etc.) — the v1 shows one canonical example per command.
- Tracking historical changes in examples (just overwrite; git history captures the diff).
- Auto-generated examples from a runtime simulation (overkill; capture from real runs is simpler).
- A drift CI check (file as follow-up if needed).
