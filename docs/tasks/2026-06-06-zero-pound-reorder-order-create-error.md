# £0 Reorders Crash with "ORDER CREATE ERROR" (private inventory classifier)

**Date**: 2026-06-06
**Project**: cubitts-sylius (old POS / `cubittsadmin.com`)
**Type**: Bug Fix
**Commit**: `d6220f0` (merge of PR #512; fix commit `5a5e28a`)
**PR**: https://github.com/Cubitts-KX/cubitts-sylius/pull/512

## Summary

£0 / NO-CHARGE reorders placed with the `reorder0` coupon (100% off) failed at
multiple stores with a generic POS **"ORDER CREATE ERROR"**. Root cause was a PHP
method-visibility bug: `LensTypeResolver::isGlassNonPrescriptionOrderItem()` was
`private` but is called cross-class by `InventoryProcessor`, raising a fatal that the
order-create controller swallowed. Fix: make the method `public` (matching its public
sibling) + regression test. Deployed via the `cubitts-admin-prod` CodePipeline.

## Problem

Spitalfields reported (via Slack) that a customer's reorder wouldn't go through — the
payment had failed on the original order, so they were reissuing it free with the
`reorder0` code, and the POS kept showing **"ORDER TAX ERROR"** then **"ORDER CREATE
ERROR"**. Stores narrowed it to "any rimless frame with the `reorder0` code" and
suspected a tax problem (the cart showed a 100%-discounted OBAN sunglasses at £0). The
customer (Henry Siu) had no address on file.

## Investigation

1. **Ruled out Stripe / tax.** The POS "ORDER TAX ERROR" comes from the `/cubitts-api/order/vat`
   preview (`pos-new/.../actions.js:1203`), which runs the external tax microservice
   (`cubitts-tax` → Stripe Tax). Replayed the exact failing shape (a £0 prescription
   frame+lens bundle, GB, store postcode) against `production.tax.cubitts.com/calculate`:
   **HTTP 200** for the £0 bundle, the full-price bundle, and a £0 standalone frame. Sentry
   `cubitts-tax` showed no errors in 26 days. Stripe dashboards (KX + Inc + Xero accounts)
   showed only old/unrelated failures (a card-decline 402, 11-May tax 400s). Stripe was a
   red herring.
2. **Reframed on the second symptom.** Stores' retest said "ORDER CREATE ERROR **not**
   ORDER TAX ERROR" — so the tax preview passes and the failure is in the **create-only**
   path (`OrderController::create` → `createFromDTO` with `isVat=false`), i.e. after the
   `vat` early-return: payments, persist, `paymentFinalized`, inventory, Shopify sync.
3. **Found the hidden error.** `OrderController::create` (`OrderController.php:84-91`)
   catches all throwables and returns **HTTP 200 with `{error, trace}` in the body**; the
   POS discards the body and shows only "ORDER CREATE ERROR" (`actions.js:917`). So the real
   exception was invisible in the UI, and Sylius Sentry had stopped reporting ~26 days prior.
4. **Recovered the stack trace from CloudWatch.** Sylius runs on ECS (account Cubitts-KX
   `658056508030`, eu-west-1); error logs go to stderr → log group
   `ProdCubittsAdminApplication-ServiceTaskDefcubittsLogGroup24B7F045-MO8R7Yz2KKcU`.
   Filtering the `api.CRITICAL` channel returned the fatal, firing every few minutes today
   across stores.

## Root Cause

```
api.CRITICAL: Call to private method
App\Service\TypeResolver\LensTypeResolver::isGlassNonPrescriptionOrderItem()
from scope App\Service\Inventory\InventoryProcessor
  OrderController::create:68
  -> OrderCreator::createFromDTO:311  (paymentFinalized)
  -> OrderCompleteStatusProcessor:158 (inventoryProcessor->process)
  -> InventoryProcessor:165
```

`InventoryProcessor::process()` calls `$this->lensTypeResolver->isGlassNonPrescriptionOrderItem($orderItem)`
at `InventoryProcessor.php:165`, but the method was declared **`private`** in
`LensTypeResolver.php:94`. A cross-class call to a private method is a fatal PHP `Error`.
Its sibling on the same path, `isSunglassNonPrescriptionOrderItem()` (`:115`), is correctly
`public`.

**Why only £0 reorders:** a £0 / "No Charge" order has nothing to pay, so
`createFromDTO` finalises it **synchronously** (`paymentFinalized`, OrderCreator line 311)
and reaches the inventory step in-request — hitting the private call. Card/terminal orders
return a payment handoff earlier and finalise later via another path, so they never reach
that line at create time.

**Why it looked "rimless":** a branch coincidence inside the inventory loop — most
item/lens setups `continue` out before line 165; the reorders' prescription-lens routing
fell through to it. "Rimless vs non-rimless" was not causal.

**No orphan orders:** the fatal is before `$orderRepository->add()` (OrderCreator line 313),
so nothing is persisted on failure.

## Solution

One-word visibility change to match the public sibling:

```diff
- private function isGlassNonPrescriptionOrderItem(OrderItem $item)
+ public  function isGlassNonPrescriptionOrderItem(OrderItem $item)
```

Plus a regression test asserting both inventory classifiers stay public.

## Files Modified

| File | Change |
|------|--------|
| `src/Service/TypeResolver/LensTypeResolver.php` | `isGlassNonPrescriptionOrderItem()` `private` → `public` |
| `tests/Service/TypeResolver/LensTypeResolverVisibilityTest.php` | New reflection regression test (data-provider over both inventory classifiers) |
| `CLAUDE.md` | "Known Issues and Fixes" entry |

## Testing

- `phpunit tests/Service/TypeResolver/LensTypeResolverVisibilityTest.php` → `OK (2 tests, 2 assertions)`.
- Proved it is a real regression test: re-introducing `private` locally makes it **fail**
  with the exact production message; restoring `public` passes.
- `php -l` clean on both PHP files; phpstan findings on the file are pre-existing (baseline).
- PR review: 3 language-agnostic agents (code-reviewer, silent-failure-hunter,
  pr-test-analyzer) — all approve, no blocking findings. The pr-test-analyzer independently
  enumerated every cross-class call from `InventoryProcessor` and confirmed only these two
  classifiers are involved, both now public (no other private landmine).
- CI: `Analyze` + `CodeQL` pass.
- Deploy: merged to `main`, shipped via `cubitts-admin-prod` CodePipeline (manual-approval
  gate approved by Dan). Post-deploy verification: place a live £0 `reorder0` order and
  confirm it completes (pending).

## Prevention / Future Reference

- **Surface swallowed create errors.** `OrderController::create` returning HTTP 200 with the
  error in the body, then the POS discarding it, turned a one-line bug into a multi-week
  mystery. Follow-up: return a non-2xx and surface `response.data.error` in the POS
  (`pos-new` JS, needs extension version bump).
- **Report caught `api.CRITICAL` create failures to Sentry**, and investigate why Sylius
  Sentry stopped reporting ~mid-May 2026 (last event ~26 days before this incident).
- **Diagnostic path when Sentry is dark:** Sylius prod errors are in CloudWatch (Cubitts-KX
  account, eu-west-1) at log group
  `ProdCubittsAdminApplication-ServiceTaskDefcubittsLogGroup24B7F045-MO8R7Yz2KKcU`, channel
  `api.CRITICAL`. Find the ECS log group from the task definition's `awslogs-group`.
- **`reorder0` = coupon `Reorder0` → promotion `ReOrder100` (id 600), `order_percentage_discount` 100%.**
- Sibling classifiers used by `InventoryProcessor` must stay `public`; the regression test
  guards both branches.

## Related Documentation

- PR: https://github.com/Cubitts-KX/cubitts-sylius/pull/512
- `cubitts-sylius/CLAUDE.md` → "Known Issues and Fixes" → "£0 Reorders Crash with ORDER CREATE ERROR (Fixed 2026-06-06)"
- Prior pay-link accounting fix (adjacent area, `paymentFinalized`): PR #508 / CLAUDE.md
