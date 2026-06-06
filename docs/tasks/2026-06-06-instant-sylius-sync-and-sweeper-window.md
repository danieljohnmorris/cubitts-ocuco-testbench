# Instant Sylius sync on orders/create + sweeper window fix

**Date**: 2026-06-06
**Project**: shopify-webhook-order-create
**Type**: Bug Fix
**Commits**: `8d517b7` (PR #34), `3ffd52b` (PR #35) on `master`

## Summary

Order **SH729510** (an unpaid Heru "Made to Measure" order) never synced into Sylius on its own and had to be synced by hand. Fixed by adding an instant by-ID Sylius sync on the `orders/create` webhook and correcting the scheduled sweeper's window (which had drifted to a non-overlapping 5 minutes).

## Problem

A Shopify order (`gid://shopify/Order/13327000207741`, SH729510) created at 14:17:53Z was not present in Sylius. A manual `GET /sync/order/shopify/13327000207741` created it (Sylius order `006281538`).

## Investigation

- Confirmed the order was absent from Sylius (`sylius_order.shopify` stores the GID form, e.g. `gid://shopify/Order/...`, which is why a bare-numeric lookup missed it).
- The order was created via the **"Heru Heads API - Production"** app, `displayFinancialStatus: PENDING`.
- CloudWatch logs for `shopify-webhook-order-prod-sync-unsynced`: runs at 14:17/14:22/14:27 each returned **0 orders**; the 14:32 run synced a *different* order (SH729520). SH729510 never appeared in the sweeper logs.
- The `orders/create` webhook **did** fire (14:17:58Z, stored to S3 `order/created/pending/`) and the s3-processor ran — but that path only copies metafields / fires Klaviyo / tags. **It never told Sylius about the order.** The *only* path into Sylius was the polling sweeper.

## Root Cause

Two compounding gaps:

1. **No instant path to Sylius.** Everything relied on the scheduled `sync-unsynced` sweeper, which discovers orders via Shopify's order **search** — and Shopify's search index lags several minutes for API/draft-converted orders (e.g. Heru).
2. **The sweeper window had drifted to a contiguous, non-overlapping 5 minutes.** Source intended `rate(1 minute)` + 5-min lookback (PR #20, 2026-04-02), but production was running `rate(5 minutes)` + 5-min lookback — someone had reverted the EventBridge rate in the console. SH729510, created 3s before a run and not yet searchable, was missed by that run and then sat 3s *before* the next window's start. It fell through forever.

## Solution

**PR #34 — instant sync + window fix**
- New shared module `packages/webhook/src/services/sylius-sync.ts`: `shouldSyncOrderToSylius` (eligibility predicate) + `syncOrderToSylius` (by-ID HTTP call), reused by both the sweeper and the s3-processor.
- `s3-processor.ts` `maybeSyncOrderToSylius(order)` runs after `processOrder` on every eligible `orders/create` webhook and syncs Sylius **by order ID** (immune to search-index lag). Non-fatal: failure logs + `Sentry.captureMessage('...', 'warning')`, never fails the webhook; the sweeper backstops.
- `webhook-stack.ts`: wire `SYLIUS_SYNC_URL` into the s3-processor Lambda; restore `rate(1 minute)` and widen the sweeper lookback `5 -> 15` min (~15 overlapping attempts per order).

**PR #35 — review follow-ups**
- Machine-readable exclusion `code` on the eligibility result; sweeper tallies via a `Record<SyliusSyncExclusionCode, number>` (fixes a store-tag-counted-as-admin-channel miscount and removes the prose-coupling).
- Only a missing-variant 500 (`Variant with code … not found`) is `permanent: true` (tagged `Sylius-Sync-Failed`, stops retrying); generic/transient 500s stay retryable.
- `AbortSignal.timeout(25s)` on the Sylius fetch so the instant path fails fast.
- Sweeper escalates to Sentry (`warning`) when a run finishes with failed orders.

## Files Modified

| File | Change |
|------|--------|
| `packages/webhook/src/services/sylius-sync.ts` | New shared module: predicate + by-ID sync call, `code`/`permanent` discriminants, login-redirect guard, fetch timeout |
| `packages/webhook/src/s3-processor.ts` | `maybeSyncOrderToSylius` after `processOrder` (instant, non-fatal) |
| `packages/webhook/src/sync-unsynced-orders.ts` | Delegate filter to shared predicate; Record-based tally; `permanent`-flag tagging; Sentry escalation on failed runs |
| `infrastructure/webhook-stack.ts` | `SYLIUS_SYNC_URL` on s3-processor Lambda; `rate(1 minute)`; lookback `5 -> 15` min |
| `CLAUDE.md` | Document the two-path Sylius sync architecture |

## Testing

- 227 unit tests pass (vitest), incl. the SH729510 regression (Heru-shaped order is eligible and synced by ID), exclusion codes, transient-vs-permanent 500, timeout, login-redirect, Sentry warning-on-failure.
- `tsc --noEmit` + `npm run build` clean; `cdk synth` confirms `rate(1 minute)`, `{"minutes":15}`, `SYLIUS_SYNC_URL` on both lambdas.

## Prevention / Future Reference

- The EventBridge rate drifted via a console edit and went unnoticed for ~2 months. Consider periodic `cdk diff` / drift detection so manual console edits can't silently revert IaC.
- Shopify order **search** is not a reliable real-time index for freshly created (esp. API/draft) orders — prefer by-ID fetches for time-sensitive paths.

## Follow-ups

- CloudWatch error alarm on the sweeper Lambda (`createLambdaAlarms` is not called for `syncUnsyncedOrders`).
- Age-based permanent cutoff (tag-out an order still failing N hours after creation) to bound the now-retryable non-variant-500 loop.

## Related Documentation

- PR #34: https://github.com/Cubitts-KX/shopify-webhook-order-create/pull/34
- PR #35: https://github.com/Cubitts-KX/shopify-webhook-order-create/pull/35
