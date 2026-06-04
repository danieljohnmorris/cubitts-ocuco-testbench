# Iris: URL permalinks for routines + Live feed under /routines

**Date:** 2026-06-04
**Project:** iris (Cubitts-KX/iris)
**PR:** https://github.com/Cubitts-KX/iris/pull/50 (merged)
**Branch:** `feature/iris-routines-permalinks` -> `main`

## Summary

The Iris admin Routines page kept its entire view state in local React state, so
nothing was linkable. You could not share a link to a specific routine, its edit
form, its version history, or an individual run. The Live feed also sat at the
top-level `/live`, outside the routines section it belongs to.

This made the page fully URL-driven so every view is a shareable permalink, and
moved Live feed under `/routines`.

## Problem

- Selecting a routine, switching the Runs/Edit/Versions tab, and expanding a run
  were all `useState` - none reflected in the URL, so none were deep-linkable.
- Live feed lived at `/live`, a sibling of the whole app rather than of Routines.

## Solution

URL scheme (React Router v6 ranks static segments above `:name`, so `new`/`live`
can't be shadowed by a routine of that name - reserved by convention):

| URL | Shows |
|---|---|
| `/routines` | list (auto-selects the first routine) |
| `/routines/new` | create form |
| `/routines/live` | Live feed (moved from `/live`) |
| `/live` | redirect -> `/routines/live` (back-compat) |
| `/routines/:name` | Runs tab |
| `/routines/:name/edit` | Edit tab |
| `/routines/:name/versions` | Versions tab |
| `/routines/:name/runs/:runId` | Runs tab with one run expanded |

- List rows, `+ New` and the detail tabs are now `<Link>`s (button styling
  preserved in CSS); run rows toggle the run permalink.
- Sub-nav highlights Routines on every routine sub-page but hands the highlight
  to Live feed on `/routines/live`.
- No infra change: the existing CloudFront SPA-router function already rewrites
  any non-asset path to `/index.html`, so the new deep links survive a hard
  refresh (the old `/live` already did).

## Review fixes (from the PR review)

1. **Loading flash on every navigation** - `load()` depended on `selected`/
   `creating`, so every click reset the 15s poll and re-fired `setLoading(true)`,
   flashing "Loading routines..." over the content. Split the fetch (depends only
   on the Active/Archived filter) from URL reconciliation (its own effect off the
   loaded list), so a valid selection is never yanked by a background poll either.
2. **Out-of-window run permalink rendered nothing silently** - a shared link to a
   run aged out of the latest 20 showed nothing. Now detects the unmatched
   `runId`, shows a notice and loads the run directly (the detail panel fetches by
   id, so it stands alone).
3. **Stale/unknown routine permalink bounced silently** - now flashes
   `routine "X" not found` (hinting at Archived when on the Active filter).

Also extracted the pure helpers (`tabForPath`, `nextRoutinePath`,
`routinesNavActive`) into `frontend/src/lib/routines-nav.ts` with 11 unit tests,
mirroring the `lib/section.ts` pattern.

## Files modified

- `frontend/src/App.tsx` - routes (new routine sub-routes, `/routines/live`,
  `/live` redirect), sub-nav links, nav-active helper.
- `frontend/src/pages/Routines.tsx` - URL-driven selection/tab/run; fetch vs
  reconcile split; out-of-window run handling.
- `frontend/src/lib/routines-nav.ts` (new) - pure routing helpers.
- `frontend/src/lib/__tests__/routines-nav.test.ts` (new) - 11 tests.
- `frontend/src/lib/__tests__/section.test.ts` - new sub-path classification cases.
- `frontend/src/index.css` - anchor styling for the converted rows/tabs/`+ New`,
  out-of-window notice styles.

## Testing

- `tsc --noEmit` clean
- `vitest run` - 34 tests pass (11 new in routines-nav)
- `npm run build` succeeds
- PR review: feature-dev:code-reviewer, silent-failure-hunter, pr-test-analyzer -
  all findings actioned.

## Deployment

Merged to `main`, deployed via the `iris-pipeline` CodePipeline (Source ->
DeployStaging -> ApproveProduction manual gate -> DeployProduction) in account
658056508030, eu-west-1. Production approved after staging deploy.

## Learnings

- When converting React local state to URL-driven routing, keep the data fetch
  and the URL-reconciliation in separate effects. Folding the redirect into the
  fetch callback ties the poll's identity to the selected route and reflashes the
  loading state on every navigation.
- Externally-supplied route params (`:runId`) can reference data not in the
  current page (runs aged out of the latest-N); always render an explicit
  not-found/standalone path rather than assuming the id matches a fetched row.
