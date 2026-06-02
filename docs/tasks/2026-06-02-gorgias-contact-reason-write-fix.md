# Gorgias contact-reason write fix + missing-reason finder

**Date**: 2026-06-02
**Project**: cubitts-mcp
**Type**: Bug Fix + Feature
**Commit**: `971f09d` (merge of PR #78; `442a8a1` fix, `e49e3ff` test hardening, `4cd1cfd` truncation flag)
**PR**: https://github.com/Cubitts-KX/cubitts-mcp/pull/78

## Summary

`gorgias_set_contact_reason` was broken in production — every write returned HTTP 400 — because it sent a `{"value": reason}` body to Gorgias' per-field custom-field endpoint, which expects the **bare value string**. The mock-only test suite asserted the wrong (wrapped) body, so it never caught it. Fixed the body shape, hardened the tests against the real wire contract, and added a `gorgias_tickets_missing_contact_reason` tool to find uncategorised tickets.

## Problem

Live-testing the recently-merged contact-reason MCP tools (PRs #76/#77) revealed `gorgias_set_contact_reason` failed on every real call:

```
PUT /tickets/{id}/custom-fields/625   body: {"value": "Other::CX checking order details"}
→ HTTP 400 {"error": {"data": {"0": {"value": ["Not a valid string.", ...]}}}}
```

The tools were green in CI and listed as deployed, but no write had ever succeeded against the live API.

## Investigation

1. Called the live `gorgias_contact_reasons` (read) tool — worked (field id 625, 138 choices).
2. Called `gorgias_set_contact_reason` on a real ticket — HTTP 400.
3. Pulled Gorgias creds from AWS Secrets Manager (`cubitts/mcp`, account 658056508030) and probed the live API directly:
   - Read back a ticket that already had a contact reason: stored value is a **plain string** (`"Sales::Bespoke+"`, `data_type: text`), so the body *content* was right — the *shape* was wrong.
   - Tried body shapes against `PUT /tickets/{id}/custom-fields/625`: `{"value": V}` → 400; **bare string `V` → HTTP 202** ✅.
   - Tried the whole-ticket route `PUT /tickets/{id}` with a `custom_fields` list → 202 but **destructively replaces the entire `custom_fields` set**, wiping sibling fields. It wiped the AI-managed "AI Intent" field (26515) on ticket 224227904, which then could **not** be restored (`"can only be set by Gorgias internal apps"`).
4. Confirmed the `/tickets` **list** endpoint embeds `custom_fields` keyed by field id (`{"625": {"id":625,"value":"..."}}`), so a ticket missing a contact reason simply has no `"625"` key — detectable with no per-ticket fetch.

## Root Cause

Gorgias' per-field custom-field endpoint (`PUT /tickets/{id}/custom-fields/{field_id}`) takes the **bare value** as the JSON body, not a `{"value": ...}` wrapper. The original implementation wrapped it. Because the test fake encoded the same wrong assumption (`requested = (json or {}).get("value")`), the suite asserted the broken contract and never failed.

## Solution

- **Bug fix**: send the bare `reason` string to the field-scoped endpoint. This touches only field 625 and leaves sibling custom fields intact — unlike `PUT /tickets/{id}`, which is destructive and already hard-blocked by the `_gorgias_put` transport guard (`_GORGIAS_CUSTOM_FIELD_PUT_RE`).
- **Tests**: the fake now models the real wire contract (bare string) and asserts the PUT body is **never a dict** on every write, plus an explicit `test_set_put_body_is_bare_string_not_wrapper`. Added an opt-in (`GORGIAS_LIVE=1`) read-only live contract test, since a self-authored fake can't catch wire drift.
- **New tool** `gorgias_tickets_missing_contact_reason(since, until, include_closed=False)`: lists tickets in a window with no contact reason, read free from the embedded `custom_fields`. Closed tickets excluded by default.
- **Truncation flag** (review finding): `_gorgias_paginate` silently capped at `hard_cap=200` pages. It now returns `(kept, dropped, truncated)`, logs a warning on cap-hit, and the finder surfaces `truncated` in its JSON so a partial window can't pass as complete.

## Files Modified

| File | Change |
|------|--------|
| `server/server.py` | `gorgias_set_contact_reason`: bare-string PUT body. `_gorgias_put`: signature/docstring accept verbatim JSON body. New `gorgias_tickets_missing_contact_reason` tool. `_gorgias_paginate`: returns `(kept, dropped, truncated)` + cap-hit warning; all 4 callers updated. |
| `tests/test_gorgias_contact_reason.py` | Fake serves bare-string PUT body + paged `/tickets`; bare-string regression test; finder tests (open/closed, empty/non-dict entry, date-window exclusion, multi-page cursor, truncation); opt-in live read contract test. 18 → 35 tests. |
| `README.md` | Body-shape warning, new tool section, `truncated` flag. |

## Testing

- `pytest tests/test_gorgias_contact_reason.py -q` → **35 passed, 1 skipped** (the live test).
- Bug-injection proof: reintroducing `{"value": reason}` fails 6 tests incl. the bare-string regression; restored → green.
- Live-verified: bare-string write returns 202 and reads back correctly; missing-reason classification on 40 real tickets (28 with / 12 without).
- Live contract test run with real creds (`GORGIAS_LIVE=1`) → passes.
- ruff identical to main (no new errors).

## Prevention / Future Reference

- **Mock-only tests can't catch wire-contract bugs** — the fake encodes the author's (possibly wrong) belief about the API. For external-API writes, add a creds-gated live (read-only) contract test. This is exactly how the wrapped-body bug shipped through green CI.
- **Gorgias custom-field write**: use the field-scoped endpoint `PUT /tickets/{id}/custom-fields/{field_id}` with the **bare value** string. Never use `PUT /tickets/{id}` with a `custom_fields` list — it replaces the whole set and wipes (unrecoverable) AI-managed fields.
- **The `/tickets` list embeds `custom_fields`** keyed by field id — cheap to detect missing/empty fields without N+1 fetches.
- **Production side-effect during probing**: ticket 224227904 lost its auto-generated AI-Intent value (generic `Other::Other::Other`, internal metadata, no customer data) and carries a placeholder contact reason; 224213605 carries a placeholder reason. Future live API probing should target a sandbox/throwaway ticket, not real ones.

## Related Documentation

- Prior contact-reason work: PR #76 (write tool), PR #77 (field list) — both predate and are fixed/extended by this PR.
- `cubitts-mcp/README.md` → "Gorgias contact reason (list + write + gap-find)".
