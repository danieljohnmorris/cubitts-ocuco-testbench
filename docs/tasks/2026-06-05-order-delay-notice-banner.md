# My Account / Orders delay notice banner

**Date**: 2026-06-05
**Project**: shopify-account-extensions
**Type**: Feature
**Commit**: `1c9e6ad` (squash merge of PR #35 into main)
**PR**: https://github.com/Cubitts-KX/shopify-account-extensions/pull/35
**Live app version**: `cubitts-account-extensions-270`

## Summary

Added a configurable delay-notice banner to the customer account **Order status** page, mirroring the cart/checkout delay message about the workshop move. Shipped as a new customer-account UI extension with the message and an on/off toggle exposed as editable extension settings, then deployed to production with the toggle defaulting on.

## Problem

A delay message had been added to the cart/order flow (theme "Cart message" section):

> We're currently settling into a new workshop space. As a result, some orders may take up to 5 working days longer than usual.

Customers returning to **My Account → Orders** to check an existing order saw no equivalent notice. The ask was to surface the same message on the order status page, scoped to the agreed dates (5th–15th June 2026).

## Investigation

- The My Account order detail page (Orders / Prescriptions / Documents / Profile) is powered by Shopify **customer-account UI extensions** in `shopify-account-extensions`, not the theme.
- The order status page is the `customer-account.order-status.block.render` target. Existing blocks there: `order-estimate`, `order-prescription-order-status` (via shared `OrderPrescriptionBlock.tsx`), `download-invoice`.
- These blocks use a Preact render pattern (`render(<Block/>, document.body)`), read config via `shopify.settings.value`, and rely on a per-extension `shopify.d.ts` to type the injected `shopify` global. Banners use `<s-banner tone="…">`.
- The cart message is theme-editor managed; there is no theme surface for the account page, so a new extension was the right vehicle. Settings-driven copy keeps it editable without a redeploy, matching the cart message's editability.

## Solution

New extension `extensions/order-delay-notice`:
- Targets `customer-account.order-status.block.render`, renders an `<s-banner tone="warning">` at the top of the order status page.
- Two settings: `delayNoticeEnabled` (boolean) and `delayNoticeMessage` (multi-line text, default = the 5–15 June copy). Banner renders only when enabled **and** the message is non-empty (`shouldShowDelayNotice`); display text is trimmed via `delayNoticeText`.
- Render entry wrapped in try/catch so a throw is logged (`[DelayNotice]`) rather than failing the block silently; missing/wrong-type settings are warned distinctly from an intended hide (PR-review hardening).

Rollout:
- v269 deployed with the toggle **off by default** (safe — renders nothing until enabled).
- v270 deployed with `delayNoticeEnabled` `default = true`.

## Admin configuration (per store)

The block is **not** auto-rendered. Customer-account `order-status.block.render` extensions must be **placed manually** in the editor, exactly like the existing `Order Prescription – Order Status` block:

1. Shopify admin → **Settings → Customer accounts → Customize**
2. Switch the page selector to the **Order** (order status) page
3. **Add block → Order Delay Notice** (under Apps), drag to the top of Main
4. In the block settings: set **Show delay notice = True** and paste the message
5. **Save**

This must be repeated **per store** (staging and production separately) — placement does not transfer with the app deploy.

### Canonical copy (match the checkout banner)

The existing cart/checkout delay message is a **Shopify-native "Static content" block** with **content type "critical banner"** in the Checkout 3.0 editor (it is NOT a custom extension). Its live wording is:

> From the 5th to the 15th June 2026, we're settling into a new workshop space. As a result, some orders may take up to 5 working days longer than usual.

The Order Delay Notice message should be set to this exact text so the two surfaces stay consistent (note: leads with the dates and uses "As a result…", differing from the toml's placeholder default).

### Open follow-ups

- **Check for a native block on order status**: if the order-status editor's Add block list offers a native "Static content"/banner (like checkout's critical banner), it could replace the custom extension entirely and match checkout styling exactly — at which point the custom `order-delay-notice` extension should be deleted. The checkout Static content block is checkout-specific, so it likely is **not** available on the order-status surface; pending confirmation from the Add block list.
- **Tone match**: the custom banner is `tone="warning"` (amber); the checkout banner is "critical" (pink). If we keep the custom block, switch to `tone="critical"` + redeploy to match the checkout look.
- **Code default drift**: the toml `default` for `delayNoticeMessage` carries the earlier draft wording. It's cosmetic (the editor does not pre-fill from it; the merchant-entered value is authoritative), but worth aligning to the canonical copy on the next redeploy.

## Files Modified

| File | Change |
|------|--------|
| `extensions/order-delay-notice/shopify.extension.toml` | New extension config + settings (`delayNoticeEnabled` default true, `delayNoticeMessage`); CLI-assigned `uid` |
| `extensions/order-delay-notice/src/DelayNoticeBlock.tsx` | Preact block; `shouldShowDelayNotice` + `delayNoticeText` helpers; try/catch render; failure-signal logging |
| `extensions/order-delay-notice/shopify.d.ts` | Types the injected `shopify` global for the entry module |
| `extensions/order-delay-notice/tsconfig.json` | Standard per-extension TS config |
| `test/delayNotice.test.ts` | 12 unit tests for the visibility + display helpers |
| `README.md` | Documents the new extension |

## Testing

- `vitest run` — full suite green (93 tests, 12 new).
- `tsc` on the new extension — no errors in new code (remaining tsc noise is the pre-existing react/@shopify type clash shared by all extensions).
- PR review workflow: code-reviewer (no blocking issues), silent-failure-hunter + pr-test-analyzer findings actioned.
- Deployed to production: `cubitts-account-extensions-270` released successfully. Visual confirmation on a live order status page is the remaining manual check.

## Prevention / Future Reference

- **Order-status blocks are NOT auto-placed.** Customer-account `order-status.block.render` extensions must be manually added in the customer account editor (Add block) per store; releasing the app version is not enough to make them appear. (Initial assumption that they auto-render was wrong — corrected during the admin walkthrough.)
- **`default` does not pre-fill the editor.** A settings field `default` in the toml does not populate the customer-account editor field — it shows the stored/unset value (boolean → False, text → empty). The merchant must explicitly set values; the entered value is authoritative. So `default = true`/default message are effectively cosmetic for this surface.
- **The cart/checkout delay banner is a native block, not code.** It is a Shopify "Static content" block (content type "critical banner") in the Checkout 3.0 editor — no extension involved. Before building a custom extension for a banner, check whether the target surface offers a native Static content/banner block.
- **Empty default locale fails deploy.** A `locales/en.default.json` of `{}` fails `shopify app deploy` with `localization: Locale data for 'en' is empty`. Extensions with no i18n strings should ship **no** locales dir (matches `order-estimate`), not an empty file.
- **Single app, single release.** This repo has one app config (`Cubitts Account Extensions`, client_id `f33c34f5…`); there is no separate staging app/toml. `shopify app deploy` creates one version released to whatever store(s) the app is installed on — there is no staging-only release. The true non-prod preview path is `shopify app dev` against a dev store (dev store was "Not yet configured").
- **`uid` placement.** The Shopify CLI may write the CLI-assigned `uid` at the top level of the toml; the repo convention keeps it **inside** the `[[extensions]]` block (matches siblings).
- **Turn it off after the window.** The notice is time-bounded (5–15 June 2026). After 15 June, untick **Show delay notice** in the customer account editor settings, or ship a config change setting `delayNoticeEnabled` `default = false` / clearing the message.
- Deploy command (per README): `shopify app deploy --force --message "…"`.

## Related Documentation

- `shopify-account-extensions/README.md` — Order Delay Notice section + project structure.
- Cart delay message is the theme "Cart message" section (separate, theme-editor managed).
