# 0006. LiteLLM gateway with hybrid BYOK

**Status:** Accepted · **Date:** 2026-07

## Context
Sakama needs multi-provider LLM access (vision for PhotoSnap, chat for the coach, structured JSON for plan
generation), easy provider switching, and BYOK. A mobile app **must never ship provider API keys**
(OWASP M1). And "free forever" requires that non-BYOK users get AI **we** pay for, with bounded cost.

## Decision
- **LiteLLM proxy**, self-hosted, as the AI gateway: virtual keys, hard per-user budgets, RPM caps,
  provider routing, prompt caching, spend ledger.
- **Supabase Edge Function** in front of it as the only AI entry point: verifies JWT, enforces RLS,
  resolves the virtual key or the encrypted BYOK key, shapes the request, persists results.
- **Hybrid BYOK:** everyone defaults to a budgeted virtual key (keeps the free tier viable and cost
  bounded); users who add their own key flip to passthrough and cost us ~$0.
- Cheap model by default (vision + routine chat), escalate only for hard coaching turns.

## Consequences
- Free-tier cost is **bounded by construction**. Envelope: ~$95/month in provider tokens for ~10k users,
  plus a small proxy VM.
- **The one thing that blows the budget is defaulting chat or vision to a flagship model.** Enforce
  cheap-default + escalation at the proxy.
- **LiteLLM is MIT except its `enterprise/` directory** (proprietary). Deploy the OSS proxy via Docker;
  never vendor `enterprise/`.
- BYOK keys: envelope-encrypted at rest, never returned to the device, redacted from all logs.
- This is precisely what Fud AI **cannot** do (no backend), and is therefore our differentiator over it.
