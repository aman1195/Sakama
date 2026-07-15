# 0011. Serverless AI gateway — Edge Function + managed gateway, no self-hosted proxy

**Status:** Accepted · **Date:** 2026-07 · **Grilling outcome** ·
**Supersedes:** [0006](0006-litellm-gateway-byok-hybrid.md) (self-hosted LiteLLM proxy)

## Context
ADR 0006 put a **self-hosted LiteLLM proxy on an always-on VM** at the centre of the AI layer. For a
solo dev ([ADR 0010](0010-wedge-v1-scope-solo.md)), an always-on service is permanent ops: deploy,
secure, patch, monitor, and it can take down all AI features at 3am. We checked how the reference
projects actually do it — decisive because one is our own company's production product:

- **Helium (he2-beta)** uses `litellm` as an **in-process library**, a **managed Cloudflare AI Gateway**
  (caching/limits/observability), and its **own** `tier_router` + `billing_v3` for metering. **No
  self-hosted proxy.**
- **Fud AI**: no backend; client → provider directly with the user's key.
- **wger**: no AI at all.

Nobody self-hosts a LiteLLM proxy. Separately, verified free-tier research surfaced a hard constraint:
**free LLM tiers (e.g. Gemini free) train on submitted data and allow human review** — disqualifying for
a health app under the "privacy-first, no data selling" promise (India gets no EEA-style exception).

## Decision
**Serverless gateway, provider-swappable, paid tier for real user data.**

- AI entry point = **Supabase Edge Function (Deno)** — verifies JWT/RLS, checks entitlement + usage in
  the `ai_usage` table (enforces the freemium caps from [ADR 0009](0009-freemium-monetization.md)),
  shapes the request, persists the result. Serverless — nothing always-on to operate.
- Route providers through a **managed gateway** — **Cloudflare AI Gateway** (Helium's choice) or
  **OpenRouter** — for caching, rate-limits, multi-provider switching, and BYOK. This delivers the
  original "switch providers easily" goal with zero servers.
- **Provider tier by phase:** free tiers / OpenRouter free models are fine in **development** (our own
  test data); **real user health data must use a paid tier** (Vertex/paid API — no training on our data).
  The gateway abstraction makes this a config switch.
- **Self-hosted LiteLLM proxy is explicitly rejected for v1** — kept on the shelf only if metering ever
  outgrows the Edge Function (it will not at wedge scale).

## Consequences
- **Near-$0 infrastructure** (Supabase free + Cloudflare AI Gateway free); the only unavoidable spend is
  **LLM tokens on a paid tier**, which is exactly what freemium funds.
- Metering/tier logic is *our* code in the Edge Function (port Helium's `tier_router` pattern to TS) —
  full control, no proxy dependency.
- **On-device AI is a later cost/privacy layer (v1.1):** push nutrition-label OCR (Apple Vision / Android
  ML Kit), barcode, and voice→text to the device (free, private, offline). The cloud VLM is reserved for
  the one thing that needs it — estimating a cooked Indian plate. On-device cannot do that well today.
- BYOK: per-call key, encrypted at rest, redacted from logs (unchanged from 0006).
