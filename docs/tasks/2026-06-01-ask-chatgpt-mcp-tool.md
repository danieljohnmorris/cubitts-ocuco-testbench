# Add `ask_chatgpt` MCP tool (query OpenAI ChatGPT)

**Date**: 2026-06-01
**Project**: cubitts-mcp
**Type**: Feature
**Commit**: `4502a82` (merge of PR #70 into `main`), commits `9500089..33bf2fa`

## Summary

Added an `ask_chatgpt` tool to the cubitts MCP server so agents, scheduled routines and digests can get a second opinion from OpenAI's ChatGPT (a different model family) or web-grounded answers.

## Problem

Dan wanted a cubitts MCP "skill" (tool) to ask ChatGPT. Open sub-question: did the new OpenAI API key need to be a **Service account** key or a personal ("You") key?

## Investigation

- **API key question**: A personal key is tied to the individual user and is disabled if they leave the org/project; a **Service account** key is a non-human identity meant for backend automation. Recommended Service account for a persistent backend like the MCP server.
- **Existing wiring**: Verified `OPENAI_API_KEY` already lives in the `cubitts/mcp` secret — mem0 (`_mem0()`) and the KB embedder (`_kb_embed()`) already use it. So the new tool needs **no new secret wiring**; the slot is already populated and the `openai` SDK is already a transitive dependency (via `mem0ai==2.0.2`).
- **Key-scope discovery (live test against the deployed key)**:
  - Chat Completions (`/v1/chat/completions`) works — `gpt-5.1` and `gpt-4o` both answered (`17*23 → 391`).
  - Responses API (`/v1/responses`) returns **`Missing scopes: api.responses.write`** — the current key in the secret is *restricted*.
- **Tool-type check**: Confirmed against the installed SDK (v2.39.0) that `{"type": "web_search"}` is the **GA** Responses tool type (`web_search_preview` is the older alias) — `openai/types/responses/web_search_tool_param.py` literal is `["web_search", "web_search_2025_08_26"]`.

## Root Cause

N/A (feature). Key design driver: the existing key only has Chat Completions scope, so the tool must work with Chat Completions by default and only use the Responses API (for `web_search`) when a broader-scope key is present.

## Solution

Added `ask_chatgpt(prompt, model="gpt-5.1", system="", web_search=False) -> str` to `server/server.py`:

- **Default path** → Chat Completions (broadest key-scope compatibility; works with the existing restricted key today).
- **`web_search=True`** → Responses API with the built-in `web_search` tool (the only surface with native browsing; needs an `api.responses.write`-scoped key).
- Reuses `OPENAI_API_KEY` from env (loaded from `cubitts/mcp`). Optional `OPENAI_CHAT_MODEL` env var overrides the default model.
- Follows server conventions: sync `def` + `@mcp.tool()`, returns a string (never raises — errors come back as `error: ...`), logs on entry/error with `[ask_chatgpt]` prefix.
- `60s` client timeout so a hung call can't tie up a thread-pool slot for the SDK's 600s default; `logging.exception` on failure to keep the traceback.
- `_openai_output_text` helper extracts the answer robustly: prefers `output_text`, falls back to walking `output[].content[].text`, captures **refusals** (`.refusal`), and tolerates missing attributes. The web_search path also surfaces `status=="incomplete"` (token-capped/truncated) with its reason instead of a generic "empty response".

## Files Modified

| File | Change |
|------|--------|
| `cubitts-mcp/server/server.py` | New `ask_chatgpt` tool + `_openai_output_text` helper |
| `cubitts-mcp/tests/test_ask_chatgpt.py` | New — 28-test suite (both API paths, guards, routing, refusal/incomplete/empty handling, helper fallbacks); injects a fake `openai` via `sys.modules`; self-contained env setup |
| `cubitts-mcp/README.md` | Added tool to the tool list; note on `web_search` key-scope requirement + `OPENAI_CHAT_MODEL` override |

## Testing

- Live call through the deployed key (Chat Completions path): `17*23 → 391`. ✅
- Confirmed the deployed key lacks `api.responses.write` (hence the dual-path design).
- `pytest tests/` → **28/28 pass** (self-contained, no manual env needed).
- `py_compile server/server.py` clean; ruff finding set identical to `main` (zero new lint errors).
- Full PR review run (Step 1 build/lint/test → 3 language-agnostic agents → docs). Two review rounds; actioned: client timeout, `logging.exception`, self-contained tests, and the MEDIUM silent-failure finding (refusal/incomplete-status misattribution on the web_search path).

## Prevention / Future Reference

- **To enable `web_search` in production**: point `cubitts/mcp`'s `OPENAI_API_KEY` at a key with `api.responses.write` scope (a Service-account or full-access key). Until then, `web_search=True` will return an auth error; plain calls work.
- The `openai` SDK is a transitive dep via `mem0ai` — no need to add it to `requirements.txt` (kept off to avoid version conflicts with mem0's pin).
- Deploy happens via **CodePipeline** on merge to `main` (replaces the EC2 instance); `deploy.yml` is dead and there is no PR CI gate on this repo.

## Related Documentation

- PR: https://github.com/Cubitts-KX/cubitts-mcp/pull/70
- Repo: `Cubitts-KX/cubitts-mcp`
- Related memory: cubitts-mcp deploy + routines (CodePipeline deploy model)
