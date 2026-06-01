# Add `ask_chatgpt` MCP tool (query OpenAI ChatGPT)

**Date**: 2026-06-01
**Project**: cubitts-mcp
**Type**: Feature
**Commits**: `4502a82` (PR #70 — initial), `b527933` (PR #71 — simplification, final state)

## Summary

Added an `ask_chatgpt` tool to the cubitts MCP server so agents, scheduled routines and digests can ask OpenAI's ChatGPT a question (a second opinion from a different model family). Final signature:

```python
ask_chatgpt(prompt: str, model: str = "", system: str = "") -> str
```

With no `model` it uses OpenAI's auto-rolling `gpt-5.1-chat-latest` alias (the current ChatGPT model, no concrete version pinned); pass `model` per call or set `OPENAI_CHAT_MODEL` to override fleet-wide without a deploy.

## Problem

Dan wanted a cubitts MCP tool to ask ChatGPT, with an optional model override, otherwise pick the latest model. Open sub-question: did a new OpenAI API key need to be a **Service account** key?

## Investigation

- **API key question**: a personal ("You") key is disabled if the user leaves the org/project; a **Service account** key is a non-human identity for backend automation. Service account is the right choice for a persistent backend — but it turned out **no new key is needed**: `OPENAI_API_KEY` already lives in the `cubitts/mcp` secret (mem0 + the KB embedder use it), and the `openai` SDK is already a transitive dep via `mem0ai==2.0.2`.
- **Key scope (live tests against the deployed key)**:
  - Chat Completions (`/v1/chat/completions`) works (`gpt-5.1-chat-latest`, `gpt-4o`, etc.).
  - Responses API (`/v1/responses`) → `Missing scopes: api.responses.write`.
  - `/v1/models` listing → `Missing scopes: api.model.read`.
- **"Latest model" resolution**: because the key can't list models, a dynamic `/v1/models` resolver would always fail and fall back. OpenAI's maintained `-chat-latest` alias is the right primitive — it points at the current ChatGPT model and works via Chat Completions. Verified `gpt-5.1-chat-latest` returns real content (`17*23 → 391`, "Paris").

## Solution

Single OpenAI **Chat Completions** call (broadest key-scope compatibility — works with the existing restricted key, no new key required). Default model resolves to `gpt-5.1-chat-latest`; `model.strip() or _OPENAI_DEFAULT_MODEL` so blank/whitespace falls back. Follows server conventions: sync `def` + `@mcp.tool()`, returns a string (never raises — errors come back as `error: ...`), logs on entry/error with `[ask_chatgpt]`, 60s client timeout, `logging.exception` on failure.

**Scope note:** PR #70 originally also included a `web_search=True` path (Responses API + built-in browsing). That was unrequested scope I added on my own initiative, and it was the *only* reason for the dual code path and the only thing needing a broader-scope key. PR #71 removed it (and the `_openai_output_text` helper it required), leaving the lean single-path tool Dan asked for.

## Files Modified

| File | Change |
|------|--------|
| `cubitts-mcp/server/server.py` | `ask_chatgpt` tool (single Chat Completions call); `_OPENAI_DEFAULT_MODEL` = `gpt-5.1-chat-latest` via `OPENAI_CHAT_MODEL` env |
| `cubitts-mcp/tests/test_ask_chatgpt.py` | Unit suite (fake `openai` via `sys.modules`): guards, model resolution, env-override via module reload, system routing, empty-response, exception→string |
| `cubitts-mcp/README.md` | Tool added to the tool list + note on the latest-alias default and `OPENAI_CHAT_MODEL` override |

## Testing

- Live calls through the deployed (restricted) key: blank model → `gpt-5.1-chat-latest` → "Paris"; `model="gpt-4o"` → "4"; empty prompt guarded. ✅
- `pytest tests/` → 46/46 pass; `py_compile` clean; zero new ruff findings vs main.
- Full PR review on both PRs (Step 1 lint/test → 3 language-agnostic agents → docs). Findings actioned: client timeout, `logging.exception`, self-contained tests (#70); env-override execution test (#71). All review agents clean on the final state.

## Prevention / Future Reference

- **No new OpenAI key needed** — the tool works with the restricted key already in `cubitts/mcp`.
- **Default model self-updates** within the family via the `-chat-latest` alias; to jump to a new family (e.g. `gpt-6-chat-latest`) set `OPENAI_CHAT_MODEL` in the `cubitts/mcp` secret — no code deploy.
- The `openai` SDK is transitive via `mem0ai` (not pinned in `requirements.txt`, to avoid conflicting with mem0's pin).
- Deploy is via **CodePipeline** on merge to `main` (EC2 instance replacement); no PR CI gate on this repo.
- **Scope-creep learning**: I added `web_search` without it being requested, which drove the new-key investigation and the dual-path complexity; Dan had it stripped. Default to the asked-for surface; flag extras as a question, not a built-in.

## Related Documentation

- PRs: https://github.com/Cubitts-KX/cubitts-mcp/pull/70 (initial), https://github.com/Cubitts-KX/cubitts-mcp/pull/71 (simplification)
- Repo: `Cubitts-KX/cubitts-mcp`
