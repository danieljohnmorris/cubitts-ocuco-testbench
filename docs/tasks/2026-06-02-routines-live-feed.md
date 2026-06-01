# Routines Live Feed + Skills/Tools Toggles

**Date:** 2026-06-02
**Projects:** `iris` (Cubitts-KX/iris), `cubitts-mcp` (Cubitts-KX/cubitts-mcp)
**PRs:** iris [#33](https://github.com/Cubitts-KX/iris/pull/33), [#34](https://github.com/Cubitts-KX/iris/pull/34), [#35](https://github.com/Cubitts-KX/iris/pull/35) · cubitts-mcp [#75](https://github.com/Cubitts-KX/cubitts-mcp/pull/75)
**Merge commits:** iris `b3e577d` (#35) · cubitts-mcp `eb1e60f` (#75)

## Summary

Added a **Live feed** tab to the Iris admin showing what's running right now plus recent runs and errors across *all* routines, polling every 8s. Backed by a new cross-routine endpoint in cubitts-mcp. Also shipped earlier in the same session: skills/tools on-off toggles (#33) and a blank-button fix (#34).

## Problem

The Routines tab only showed runs *per routine* — there was no single view of overall routine activity ("what's in the queue, running, recent runs and errors"). Operators had to open each routine to see its state.

## Solution

### cubitts-mcp (#75) — the data
- `GET /routine-activity?limit=N` → `{running, recent, counts}` from a single `agents.agent_runs` query ordered `started_at DESC`, split in Python into in-flight (`status='running'`) vs terminal, with `running`/`errors`/`returned` counts.
- Distinct top-level path so it never collides with the `/routines/{name}` matcher.
- **No fake "queued" state:** a run row is inserted as `running` the moment it's picked up, so "Running now" *is* the live view.
- `counts.returned` (not `total`) — it's the page size, not a grand total.

### iris (#35) — the page
- New `frontend/src/pages/LiveFeed.tsx` (Running-now + Recent tables, relative timestamps, elapsed/duration, animated running dot, error highlighting).
- Pure date helpers extracted to `frontend/src/lib/time.ts` + a new frontend **vitest** harness (11 boundary tests).
- `getRoutineActivity` client + `RoutineActivity`/`ActivityRun` types, with a response-shape guard.
- Plumbing: BFF `/api/routine-activity` (`api/src/handler.ts`) → backend `/routine-activity` (`src/admin.ts`) → cubitts-mcp. Route registered explicitly in `infra/stack.py` (the HTTP API has no catch-all — a missing route 404s).
- Nav link + `/live` route in `App.tsx`; styles in `index.css`.

### Resilience (from review)
After the first successful poll, a later failure no longer silently freezes the view: it keeps the last data but shows a **"Live updates paused"** banner, stops the running pulse, and dims the tables so frozen rows aren't read as live.

## Files modified

- **cubitts-mcp:** `server/server.py` (`_routine_activity_impl`, `rest_routine_activity`, route), `tests/test_routines_rest.py`, `README.md`
- **iris:** `frontend/src/pages/LiveFeed.tsx` (new), `frontend/src/lib/time.ts` (new), `frontend/src/lib/__tests__/time.test.ts` (new), `frontend/src/lib/api.ts`, `frontend/src/App.tsx`, `frontend/src/index.css`, `frontend/package.json` (vitest), `src/admin.ts`, `api/src/handler.ts`, `infra/stack.py`, `README.md`

## Testing

- cubitts-mcp: `pytest tests/test_routines_rest.py` — 34 passed (added activity split/counts + empty-case tests; dropped a stale test referencing the removed `_routine_delete_impl`).
- iris backend/BFF: `tsc --noEmit` clean, `npm test` — 128 passed.
- iris frontend: `npm run build` clean, `npm test` — 11 passed.
- 4-agent review (code-reviewer, silent-failure-hunter, pr-test-analyzer ×iris, code-reviewer ×mcp); all material findings actioned.

## Learnings / prevention

- **Register every API Gateway route explicitly** — the iris admin HTTP API has no catch-all, so an unregistered path returns `{"message":"Not Found"}` (same lesson as PR #30).
- **Be honest about state names** — there is no queued state, and `total` would have misrepresented a page count; named them truthfully (`Running now`, `returned`).
- **Don't let a polling UI freeze silently** — surface a staleness banner rather than `console.error`-only on post-load poll failures.
</content>
