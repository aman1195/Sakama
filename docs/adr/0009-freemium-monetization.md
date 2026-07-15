# 0009. Freemium monetization — core free forever, expensive AI metered

**Status:** Accepted · **Date:** 2026-07 · **Grilling outcome**

## Context
The product promise is "free forever, no ads, no data selling." But the AI features (PhotoSnap vision,
Vita chat, plan generation) cost real money per call, and that cost scales with engagement and user
count. "Free forever" and "an unbounded per-user AI cost" cannot both hold with no revenue source — that
is a burn rate that grows with success. The plan named cost *discipline* (cheap models, caching, budgets)
but never named the *money*. Ads and data-sale are ruled out by the core promise.

## Decision
**Freemium, with the wall around the *expensive* AI only — never the core.**

- **Free forever:** all tracking (calorie/macro/micro), the food database, manual + barcode logging,
  water, weight, fasting, basic coaching nudges. This is "the core" — it is never gated.
- **Metered on free tier:** the costly AI — a daily cap on **PhotoSnap**, a monthly token budget on
  **Vita** chat. Over the cap → a gentle prompt, not a broken feature.
- **Plan generation is free but rate-limited** (~3–5/month) — it is the headline anti-HealthifyMe claim
  and is low-frequency, so it stays free without being an abuse hole. (Its own sub-decision.)
- **Two escape valves:** "Sakama Plus" (unlimited AI, paid subscription) and **BYOK** (bring your own
  provider key → costs us ~$0).

## Consequences
- The marginal cost of a free user is **bounded by construction** (the caps), so "free forever" is
  financially survivable.
- We now need: a subscription/entitlement system (StoreKit / Play Billing, likely via RevenueCat), and
  usage metering — enforced server-side at the AI entry point against the `ai_usage` table
  ([ADR 0011](0011-serverless-ai-gateway.md)).
- The core promise is honoured literally: no basic feature is ever paywalled; no ads; no data sold.
- Monetization is a real workstream, not an afterthought — receipts, restore-purchases, and pricing all
  need care. Folded into the roadmap around the AI milestone.
