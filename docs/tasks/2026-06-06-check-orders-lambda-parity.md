# checkOrdersSweep Lambda brought to full parity with /check-orders + --fix

**Date**: 2026-06-06
**Project**: operations-management-system (`apps/innovationsSync`)
**Type**: Feature (parity hardening)
**PR**: [#341](https://github.com/Cubitts-KX/operations-management-system/pull/341) (MERGED, commit on `main` `bbc937e`)

## Summary

Step D (#338, already merged) made `/check-orders` able to invoke the cloud `checkOrdersSweep` Lambda instead of running its ~2,300-line battery locally. Before trusting that thin-client path as the default, we verified the Lambda actually covers **everything** the script + `--fix` do. A parity audit found 6 gaps; this PR closes all 6 plus a pre-existing latent bug.

## Why this came up

A live comparison run showed the script and Lambda diverging: the Lambda's Sylius scan had silently failed (`Received packet in the wrong sequence` → false `syliusNeverPosted:0`) while the script found 9 real never-posted lenses, and the Lambda's untagged scan hit its page cap every run. That triggered the "does the Lambda cover ALL of the script + fix?" audit.

## The 6 gaps closed

1. **LAB_SEND_FAILED reset+retry** — the script's `--fix` resets stuck `lab_send_failed` orders to `ready_to_process` (Order State API PATCH `force:true`) + clears MEI `errorMessage` + re-queues to the Innovations SQS; the Lambda only escalated. Implemented as a new testable `domains/labSendFailedReset.ts` (injected deps, `runPrintBatch.ts` precedent). Gated behind `SHOPIFY_AUTOFIX_ENABLED`, shares the `SHOPIFY_AUTOFIX_MAX_PER_CYCLE`=25 cap, **never** acts on the `LAB_SEND_FAILED_RX_INCOMPLETE` bucket, idempotency re-read, SQS-only failure counted as `requeueFailed` (poller fallback) not `failed`.
2. **Untagged scan page cap** 50 → 150 (was hitting the cap and degrading to empty every run).
3. **Sylius MySQL scan** now retries up to 3× with a fresh connection + backoff before degrading (fixes the intermittent `wrong sequence` false zero).
4. **IGNORED_ORDERS / IGNORED_CUSTOMERS** applied to every scan (orphan, lab_send_failed, posted_no_status, Shopify) — previously only BFLIP + untagged.
5. **Loud degraded flags** on the `take:200` lab_send_failed / posted_no_status caps, threaded into `buildActionableReport` (🚨 banner + post-on-degraded) and the `scanDegraded` aggregate.
6. **Supervisor-approval hold-back** reproduced in `classifyLensItem` — a `ready_to_process` RX order awaiting supervisor is no longer falsely escalated.

## Pre-existing bug also fixed

The handler early-returned when there were zero orphan jobs, silently skipping **every other scan + all auto-fixes** on the common no-orphan cycle. Removed; the orphan order-load is skipped but all other scans run.

## Files modified

- `apps/innovationsSync/entrypoints/checkOrdersSweep.ts` — wiring of all 6 gaps + early-exit fix
- `apps/innovationsSync/domains/labSendFailedReset.ts` (NEW) + `.test.ts` — the production write path, fully unit-tested
- `apps/innovationsSync/domains/actionableIssues.ts` (+`.test.ts`) — degraded-flag fields/banners, `selectLabSendFailedResets`
- `apps/innovationsSync/domains/shopifyOrderChecks.ts` (+`.test.ts`) — `isIgnoredOrder`, supervisor hold-back
- `apps/innovationsSync/deployment/lib/constructs/orphanReconcile.ts`, `innovationsSync-stack.ts` — Order State API URL + key secret env wiring
- `CLAUDE.md` — documented the new lab_send_failed auto-fix

## Testing

- `tsc --noEmit`: no new errors in changed files
- `eslint`: changed files clean
- vitest: full innovationsSync suite **917 pass** (+14 new tests)
- "pr review" workflow: types/lint/build + 3 language-agnostic agents (×2 rounds) + typescript-code-review + docs. Two final-round findings (IAM grant, GID-vs-numeric idempotency) verified as **false alarms** against the real construct + live DB.

## Safety

The lab_send_failed reset is the only new production write and ships **OFF** (`SHOPIFY_AUTOFIX_ENABLED` not `'true'` on the construct). Merging deployed it dormant.

## Deploy + live verification

Deployed via CodePipeline (`InnovationsSyncCDPipeline`), Lambda updated 2026-06-06 12:26 UTC. **Correction to an earlier mischaracterisation:** the auto-fix was NOT dormant — the stack already has `autoFixEnabled: true` (`innovationsSync-stack.ts:362`), so the new lab_send_failed reset went live with this deploy.

First live cycle (13:01 UTC) confirmed clean:
- `labSendFailedReset: { sent: 6, failed: 0, requeueFailed: 0, skippedOverCap: 0, skippedNotStuck: 0 }` — all 6 generic lab_send_failed orders reset cleanly.
- `untaggedScanDegraded: false` (was `true` every run before — gap 2 fix confirmed).
- `scanDegraded: null` — no scan errored.

**Shared-cap note:** lab_send_failed reset budget = `25 − (noMei.sent + noOms.sent)`. On a high no-MEI/no-OMS backlog cycle the reset can get 0 budget and defer (orders stay Slack-escalated and drain later). Observed once (saturated at 25) before the backlog drained to 10. Acceptable; revisit (raise cap / dedicated budget) only if resets are seen starving for many consecutive cycles.

## Follow-ups

- **Handler-level orchestration test** — DONE in [#342](https://github.com/Cubitts-KX/operations-management-system/pull/342) (MERGED): `checkOrdersSweep.test.ts` locks the early-exit-removed path + `usedSlots` shared-cap wiring (+ flag-off no-write). Also made `SYLIUS_SCAN_RETRY_BACKOFF_MS` env-overridable so the test doesn't sleep.
- **Step D end-state (not done)**: flip `/check-orders` default to invoke the Lambda and retire the `--local` battery, once this has soaked over a few more clean cycles.
