# iris CodePipeline pulls canonical skills from cubitts-claude-skills

**Date**: 2026-06-03
**Project**: iris (Cubitts-KX/iris)
**Type**: Feature
**Commit**: `f8747b1` (merge of PR #41; `816b576` feat, `ff9b12c` review hardening)
**PR**: https://github.com/Cubitts-KX/iris/pull/41

## Summary

iris bundled a hand-copied snapshot of the agent skills under `lambda/skills/`, which drifts from the source of truth (`cubitts-claude-skills`). Added a build-time sync so the CodePipeline clones canonical `main` and overlays it into a generated `skills/` dir before bundling — iris now ships the latest canonical skills automatically, with a safe degrade to the committed snapshot on any failure.

## Problem

There was no automated link between `cubitts-claude-skills` (the canonical skills repo) and iris. iris carried its own committed copy at `lambda/skills/<name>/`, kept in sync **by hand** (as in this session, where the cubitts-cx contact-reason update had to be manually copied across in PR #40). The two repos had already diverged (different skill sets, different folder layout), so the snapshot was guaranteed to rot. The fix had to work inside the iris CodePipeline, which only checks out the iris repo.

## Investigation

- `infra/pipeline_stack.py`: the pipeline is Source (GitHub `Cubitts-KX/iris` main, via a `github-token` Secrets Manager secret) → CodeBuild (`npm ci && node src/build.mjs` → frontend → api → `cdk deploy`). The build env only has the iris repo; canonical isn't present.
- `src/build.mjs`: already **prefers a top-level `skills/` dir** over `lambda/skills/` (a planned-cutover hook). So a pre-build step that materialises `skills/` is picked up with no build.mjs change.
- No `.gitmodules`, no npm dependency, `lambda/skills` is a plain committed dir — confirming the link was purely manual.
- Canonical layout: most skills are plugin-wrapped at `skills/<name>/skills/<name>/`, a few are flat (`cubitts-zeiss`). Digests/routines live under `routines/` and are **DB-backed** (Dan: the repo only backs them up), so they must not be pulled from the repo.
- Skill-set divergence: iris-only = `cubitts-wholesale-digest`, `yard-press-digest`; canonical-only = `cubitts-finance`, `cubitts-optom`, `cubitts-retail`.

## Root Cause

N/A (a process/architecture gap, not a bug): skills were vendored into iris with no sync mechanism.

## Solution

A build-time sync script wired into the pipeline. Design decisions confirmed with Dan: **latest canonical `main` at build**, and **overlay (not replace)** so iris-only skills are never dropped.

`src/sync-skills.mjs`:
1. Seed a fresh top-level `skills/` from the committed `lambda/skills/` snapshot.
2. If no `GITHUB_TOKEN`/override → no-op snapshot (local dev); in CI a missing token logs `::error::` (it's a misconfiguration, not benign).
3. Shallow-clone canonical `main`, **validate** (non-empty, every skill has a `SKILL.md`), then overlay: shared skills updated, canonical-only added, iris-only preserved. Handles plugin-wrapper vs flat layout; copies whole folders incl. `recipes/`.
4. All-or-nothing: a bad/partial/empty clone degrades to the full snapshot and logs `::error:: CANONICAL_SYNC_FAILED` (still exits 0 so deploys don't break). Overlay-stage filesystem errors propagate and fail the build (non-transient).

`infra/pipeline_stack.py`: wire `GITHUB_TOKEN` from the existing `github-token` secret into both deploy projects (CodeBuild `SECRETS_MANAGER` env var `github-token:token`) and run `node src/sync-skills.mjs` before `node src/build.mjs`.

Security: the token is passed via `git -c http.extraheader=Authorization: Basic <base64>` (a config arg git doesn't echo), **not** embedded in the clone URL — so it never lands in CodeBuild logs or error messages.

## Files Modified

| File | Change |
|------|--------|
| `src/sync-skills.mjs` | New build-time sync: seed → validate → overlay canonical; degrade-to-snapshot; token via extraheader; exported fns + guarded direct-run |
| `src/sync-skills.d.mts` | Type declarations so the TS suite typechecks the `.mjs` import |
| `src/__tests__/sync-skills.test.ts` | 11 vitest tests (resolution, no-token, CI loud-error, overlay/add/preserve/recipes, upstream deletion, both degrade paths) |
| `infra/pipeline_stack.py` | `GITHUB_TOKEN` env from `github-token` secret on both deploy projects; run sync before build |
| `.gitignore` | Ignore the generated `/skills/` (build artifact; `lambda/skills/` stays the snapshot) |

## Testing

- `cdk synth IrisPipelineStack` → template carries `GITHUB_TOKEN` (`SECRETS_MANAGER`, `github-token:token`) + `npm ci && node src/sync-skills.mjs && node src/build.mjs` on **both** staging and prod deploy projects.
- Local overlay against a `cubitts-claude-skills` checkout (`CLAUDE_SKILLS_URL=`) → 21 skills (16 updated, 3 added, 2 iris-only preserved); `node src/build.mjs` bundled all 21 into receiver/processor/admin.
- `vitest run` → 163 passed (incl. 11 new); `tsc --noEmit` clean.
- 3-agent PR review; two critical findings fixed (token-in-URL leak; silent partial-clone shipping stale/mixed skills).

## Prevention / Future Reference

- **Skills are no longer hand-synced into iris** — canonical `cubitts-claude-skills` is the source of truth, pulled at build. `lambda/skills/` remains the committed fallback/snapshot (and the seed base that preserves iris-only skills).
- **Not live until `IrisPipelineStack` is deployed** (`cd infra && cdk deploy IrisPipelineStack`) — the change is to the pipeline definition itself.
- **First-run checks**: the `github-token` secret must have read access to `cubitts-claude-skills`; the tokenised `http.extraheader` clone can only be verified in CI (local tests use the override path). On the first build, check the CodeBuild log for `[sync-skills] canonical … N skills ready` (success) vs `::error:: CANONICAL_SYNC_FAILED` (degraded to snapshot).
- **`routines/` is intentionally not synced** — digests/routines are DB-backed; the skills repo only backs them up. iris-only digest skills survive via the snapshot seed.
- **Local dev**: `CLAUDE_SKILLS_URL=/path/to/cubitts-claude-skills node src/sync-skills.mjs` previews the overlay without a token.

## Related Documentation

- Manual precursor this replaces: `docs/tasks/2026-06-03-cubitts-cx-skill-contact-reason-tools.md` (iris PR #40 hand-copied the cubitts-cx update).
- Upstream change that motivated it: `docs/tasks/2026-06-02-gorgias-contact-reason-write-fix.md` (cubitts-mcp PR #78).
