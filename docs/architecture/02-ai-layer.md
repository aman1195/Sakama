# Sakama — AI Layer

> Multi-provider, BYOK-capable AI for PhotoSnap (vision), Vita (coaching), and plan generation.
> Grounded in July 2026 research ([research-sources.md](../research/sources.md)).

## 1. Design goals

1. **Multi-provider, hot-swappable** — switch Claude / Gemini / OpenAI / open-source without client
   changes. (User requirement: LiteLLM.)
2. **BYOK** — power users bring their own key; their usage costs us ~$0.
3. **Mobile-safe** — the app never holds a provider key (OWASP M1). All calls go through the backend.
4. **Free-forever viable** — hard per-user budgets so cost is bounded by construction.

## 2. Gateway: LiteLLM proxy (self-hosted)

LiteLLM ships as an SDK and a **proxy server**. We use the **proxy** — one OpenAI-compatible endpoint
that authenticates callers, applies budgets/rate-limits, tracks spend per key, and routes to real
providers. This centralizes key custody and metering away from the client.

Deployment: single small always-on instance (Fly.io / $5–10/mo VM / Cloud Run) + Postgres for the
virtual-key/spend DB. `config.yaml` declares model routes and provider keys (server-side only).

**Three key mechanisms:**
- **Virtual keys** — proxy-issued `sk-...` per user, each with a monthly budget, RPM/TPM cap, and
  model allow-list. This meters free-tier users without exposing real provider keys.
- **BYOK passthrough** — `forward_llm_provider_auth_headers: true` forwards the user's provider key
  upstream (takes precedence). User pays the provider; we still get routing + logging + guardrails.
- **Key rotation** — regeneration with grace periods for hygiene.

All three product use cases are covered across providers: **vision** (OpenAI-format `image_url`
blocks; gate with `supports_vision`), **structured JSON** (`response_format` / schema — but pin plan
generation to a natively schema-capable model and validate server-side; some providers only emulate
via tool-calling), and **streaming** (SSE for Vita's chat UI).

## 3. Request path

```
App (Supabase JWT only)
  → Supabase Edge Function (Deno): verify JWT, RLS, resolve virtual key or fetch encrypted BYOK
    key from Vault, shape OpenAI-format request, persist result
    → LiteLLM proxy: budget check, route, cache, call provider, log spend
      → Gemini / Claude / OpenAI / vLLM
```

The Edge Function is the BFF and the **only** AI entry point. It is not the gateway (stateless,
short-lived) — it fronts LiteLLM.

## 4. Feature designs

### 4.1 PhotoSnap (vision food logging)
- **Flow:** compress photo → upload to Storage (`meals/{user_id}/…`) → Edge Function sends image +
  prompt to LiteLLM → model returns strict JSON `{items:[{name, portion_desc, grams, energy_kcal,
  macros{}, confidence}]}` → app maps to `food_logs`, lets user confirm/adjust portions.
- **Default model:** Gemini Flash-class (cheapest per image; strong on regional/mixed Indian plates;
  native structured output). Claude Sonnet / GPT configured as fallback + A/B.
- **Prompt** anchors on Indian context and portion units (katori, roti, idli) and asks for grams +
  confidence. Grounding hint: reference nearest `foods` rows when available (retrieval-assisted).
- **Accuracy caveat:** LLM vision under-performs on absolute portion grams. Ship LLM-only, instrument
  confidence + user corrections, and only if needed move to a two-stage (segmentation + LLM) pipeline.

### 4.2 Vita (coach chatbot)
- **Context assembled per turn (server-side):** active plan + resolved day type + today's targets vs.
  totals, streaks, weekly trend, checklist state, recent logs. This is what makes advice specific
  ("you've had 1.8L today and it's 4 PM…") instead of generic.
- **Streaming** SSE to the chat UI. History + `context_snapshot` persisted to `coach_messages`.
- **Model policy:** cheap model (Flash/Haiku) for routine turns; **escalate to Claude Sonnet** for
  quality-sensitive coaching. **Prompt-cache** the long persona + plan schema system prompt (largest
  cost lever — cached reads ~10% of base).

### 4.3 Plan generation
- **Input:** onboarding answers (goal, profile, diet, conditions, cuisine, activity).
- **Output:** the Plan JSON contract in [architecture/04-plan-engine.md](04-plan-engine.md), produced by a
  schema-capable model, **validated server-side** before persisting to `user_plans.config`.
- **Latency-tolerant** → use the Batch API (~50% cheaper) where possible.
- **Import path:** user-pasted text or uploaded document → LLM normalizes into the same Plan JSON.

## 5. BYOK + cost control

**Hybrid model (recommended):** everyone defaults to a budgeted virtual key; adding a personal key
flips them to passthrough.

- **Non-BYOK (free):** hard monthly budget + RPM cap per virtual key (e.g. N PhotoSnaps/day, capped
  chat tokens). Over-limit → LiteLLM blocks → app shows a gentle BYOK/limit prompt. Cost per free user
  is bounded.
- **BYOK:** key entered once, exchanged for a server-side reference; stored **envelope-encrypted**
  (KMS data key, ciphertext in Postgres / Supabase Vault). Device never re-receives plaintext.
  Forwarded per request; **redacted from all logs**. User can rotate/revoke.

**Cost levers (all at the proxy):** prompt caching (biggest), per-key budgets + rate limits,
cheap-model-default + escalation, Batch API for plans, BYOK offload.

**Envelope (illustrative, 10k users, ~2k AI-active):** PhotoSnap ≈ $15/mo, Vita chat ≈ $60/mo, plans
≈ $20/mo → **~$95/mo provider tokens** + ~$5–15/mo proxy VM. Hard per-user budgets guarantee it cannot
spike. **The one thing that blows the budget is defaulting chat/vision to a flagship model** —
enforce cheap-default + escalation at the proxy.

## 6. Provider policy table (config-driven, in LiteLLM)

| Task | Default | Escalate / fallback | Why |
|---|---|---|---|
| PhotoSnap vision | Gemini Flash-class | Claude Sonnet, GPT vision | Cheapest/image; benchmark on Indian food |
| Vita routine turn | Flash / Haiku (cached prompt) | Claude Sonnet | Cost; escalate on complexity |
| Vita complex coaching | Claude Sonnet | GPT flagship | Reasoning quality |
| Plan generation | Schema-capable mid model (Batch) | — | Native JSON schema + cheap batch |

## 7. Must-verify before building AI features
1. **Run an Indian-food portion-estimation eval** across Gemini / Claude / GPT on a labeled set —
   the "best" vision model here is genuinely workload-dependent.
2. **Confirm `supports_response_schema` per model** in LiteLLM — native vs. tool-call-emulated
   structured output behave differently for the plan generator.
