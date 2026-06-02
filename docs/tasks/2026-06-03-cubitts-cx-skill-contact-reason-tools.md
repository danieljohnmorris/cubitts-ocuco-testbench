# cubitts-cx skill: document Gorgias contact-reason tools

**Date**: 2026-06-03
**Project**: cubitts-claude-skills (cubitts-cx skill)
**Type**: Feature (docs)
**Commit**: `17144bd` (merge of PR #53; `ed3e2ec` the change)
**PR**: https://github.com/Cubitts-KX/cubitts-claude-skills/pull/53

## Summary

Updated the `cubitts-cx` skill so the CX agent knows about the three Gorgias contact-reason MCP tools that landed in cubitts-mcp PR #78 — and understands that the CX-set "Contact reason" custom field is a different taxonomy from the `dg-*` machine-intent tags.

## Problem

cubitts-mcp PR #78 fixed the broken `gorgias_set_contact_reason` write tool and added `gorgias_tickets_missing_contact_reason`. The `cubitts-cx` skill — the agent that reads Gorgias for CX reporting — listed only `gorgias_freshness/tickets/drivers/surveys` and had no mention of the contact-reason field at all. Without the update the agent wouldn't know it can read valid reasons, set them, or find uncategorised tickets, and could conflate the CX-set field with the `dg-*` drivers.

## Investigation

- Located the canonical skill at `cubitts-claude-skills/skills/cubitts-cx/skills/cubitts-cx/` (a Claude plugin; the `iris-frontend/.../skills/cubitts-cx` copies are deployed build artifacts, not source).
- Confirmed no existing contact-reason mention in any skill copy (`grep -rln "contact_reason"` → none).
- Reviewed how the skill documents Gorgias tools: two tool tables in `SKILL.md` and §11 in `REFERENCE.md`; the `dg-*` taxonomy lives in `REFERENCE.md` §5 (existing content describing DigitalGenius auto-tagging).

## Root Cause

N/A (documentation gap, not a bug). The skill simply predated the contact-reason tools.

## Solution

Added the three tools and a clarifying distinction:

- **SKILL.md**: added `gorgias_contact_reasons`, `gorgias_set_contact_reason`, `gorgias_tickets_missing_contact_reason` to both tool tables, plus a new **"Contact reason vs `dg-*` drivers"** subsection — the contact reason is a CX-agent-set custom field (id 625, `managed_type=contact_reason`), distinct from the machine `dg-*` intent tags; with usage notes (read valid options first, the write tool only touches that one field, the finder's `truncated` flag).
- **REFERENCE.md §11**: added the `GET /custom-fields` and `PUT /tickets/{id}/custom-fields/{field_id}` endpoints (with the bare-string-body caveat and the "never use the whole-ticket route — it wipes other custom fields" warning) and the three tools' return shapes.

## Files Modified

| File | Change |
|------|--------|
| `skills/cubitts-cx/skills/cubitts-cx/SKILL.md` | Three tools added to both tool tables; new "Contact reason vs `dg-*` drivers" subsection |
| `skills/cubitts-cx/skills/cubitts-cx/REFERENCE.md` | §11 custom-field endpoints + tool return shapes |

## Testing

Docs-only change; no executable surface. Verified the canonical skill path and that no prior contact-reason content existed. PR opened, reviewed, merged to `main`; local `main` fast-forwarded.

## Prevention / Future Reference

- The **canonical cubitts-cx skill** is `cubitts-claude-skills/skills/cubitts-cx/skills/cubitts-cx/` — edit there, not the `iris-frontend/dist/` or `cdk.out/` copies (those are deployed artifacts).
- **Open question left unresolved (deliberately):** whether DigitalGenius `dg-*` tags are still actively applied, or whether the CX-set "Contact reason" field is now the primary taxonomy. Dan flagged this; the `dg-*` wording was left untouched pending a live check of recent tickets (do tickets still carry `dg-*` tags vs only contact reasons?).

## Related Documentation

- cubitts-mcp fix that this documents: `docs/tasks/2026-06-02-gorgias-contact-reason-write-fix.md` (PR #78).
- Memory: `project_cubitts_cx_skill.md` (cubitts-cx owns CSAT/NPS, Gorgias tools gap-fill from the rate-limited API).
