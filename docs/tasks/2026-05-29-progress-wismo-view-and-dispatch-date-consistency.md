# /progress ?view=wismo slim projection + dispatch-date consistency

**Date**: 2026-05-29
**Project**: shopify-order-state-api
**Type**: Feature + Bug Fix
**Commit**: 4fcff3f (merge of PR #142)
**PR**: https://github.com/Cubitts-KX/shopify-order-data-api/pull/142

## Summary

Added a slim `?view=wismo` projection to `GET /orders/:id/progress` for the DigitalGenius WISMO flow, and fixed two dispatch-date inconsistencies in the stage-first estimate folding.

## Problem

1. **Redundant WISMO payload**: `/progress` exposes item statuses in four overlapping shapes (items → itemActions, timeline, orderActions, estimates → items) plus per-item phase fields (`customerEstimatedDays`/P75/P90/`progress`/`daysElapsed`) that the DigitalGenius "where is my order" consumer never reads.
2. **Headline date past its range**: `applyStageWalkToItem` set the per-item headline `estimatedDispatchDate` from `addBusinessDays(now, total)` (a fractional ceil) while the range max used `round`, so the point date could land a day beyond `estimatedDispatchDateMax`.
3. **Stale order rollup**: the order-level `estimatedDispatchDate` came from the pre-fold phase rollup, not the slowest folded item, so the order headline could disagree with the per-item view.

## Solution

- **`toWismoView` (new `services/wismoView.ts`)**: a pure projection returning order lifecycle (`orderState`, `lifecycleSegment`, `isPreLab/isAtLab/isPostLab`, `estimatesStatus`, `isOverdue`, `dispatchDate {earliest, latest}`) + per-item stage view (`currentStage {stage,label,daysInStage,alarm}`, `dispatchDate` range, `forwardStages` breadcrumb, `confidence`, `isOverdue`) + `excludedItems`. Behind `?view=wismo` on the route; default payload unchanged. Pure projection => the slim and full views can't disagree.
- **Date pin**: `applyStageWalkToItem` now sets `estimatedDispatchDate = estimatedDispatchDateMax` (the fraction still drives ordering/overdue).
- **Order rollup recompute**: after the enrichment loop, `orderProgressService` recomputes `estimates.estimatedDispatchDate`/`isOverdue` from folded items.
- **Overdue guard** (from review): when an item is overdue *with no date* (an overdue stage walk nulls its date), the order headline is nulled rather than promoting a faster item's date next to `isOverdue: true`. Applied in both `computeOrderEstimates` and the recompute.
- **`estimatesStatus` in WISMO** (from review): lets a consumer tell an honest empty `items` from a computation failure.

## Files Modified

| File | Change |
|------|--------|
| packages/api/src/services/wismoView.ts | New `toWismoView` projection + types |
| packages/api/src/routes/orders.ts | `?view=wismo` handling on `/progress` |
| packages/api/src/services/orderEstimateService.ts | Pin headline date to range max |
| packages/api/src/services/orderProgressService.ts | Order-level rollup recompute + overdue guard |
| packages/api/src/services/leadTimeEstimateService.ts | Overdue guard in `computeOrderEstimates` rollup |
| packages/api/src/services/__tests__/wismoView.test.ts | New unit suite |
| packages/api/src/services/__tests__/orderProgressService.test.ts | Rollup + overdue-null tests |
| packages/api/src/services/__tests__/orderEstimateService.test.ts | Date-pin test |
| packages/api/src/routes/__tests__/progress.test.ts | `?view=wismo` route test |
| CLAUDE.md | Endpoint list, WISMO section, code structure |

## Testing

- `npx tsc --noEmit` clean; full unit suite green; `npm run build:lambda` succeeds.
- CI (Analyze + CodeQL) passed; merged via `--merge`.
- Three review agents (code-reviewer, silent-failure-hunter, pr-test-analyzer) run on the diff; the consensus overdue-rollup finding was fixed with regression tests.

## Prevention / Future Reference

- The WISMO view is a *pure projection* — keep new fields derived from the full response, never recomputed, so the two views can't drift.
- Stage-folded overdue items have a null date by design; any rollup over item dates must treat "overdue with null date" as unrepresentable (null the headline), not filter it out.

## Related Documentation

- docs/tasks/2026-05-28-at-lab-stage-first-estimate-plan.md (design)
- docs/tasks/2026-05-28-per-item-stage-estimates.md
