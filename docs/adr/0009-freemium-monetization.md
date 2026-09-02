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

---

## Amendment, 2026-09-02 — the on-device tier, and availability by device

This ADR named **two** escape valves from the metered free tier: **Sakama Plus** and **BYOK**. Both
assume a cloud call — pay us, or pay the provider yourself. A model running on the user's own phone
is a **third** answer that removes the cost rather than routing it, and it did not exist as a
practical option when this was written.

### Where each path stands today

| Path | Cost to us | State |
|---|---|---|
| **Free, metered** — Vita 30/day, PhotoSnap 8, estimates 10, plan-gen 2, memory extraction 12 | per call, bounded by the caps | **built**, enforced server-side against `ai_usage` |
| **BYOK** — user's own provider key | ~$0 | **built** — `byok_page.dart`, `byok_store.dart`, threaded through every AI path; caps are skipped when a key is present |
| **Sakama Plus** — subscription | per call, unbounded per user unless capped | **decided here, not built** — no StoreKit, no Play Billing, no entitlement check |
| **On-device** — model on the user's phone | **$0** | **not built** — see [voice-agent-architecture.md](../research/voice-agent-architecture.md) |

### 9a. On-device is a fourth path, and its job is rule 1 — not quality

A 1–2B model does not beat the gateway at coaching, and judging it that way is the wrong test. Vita
is the only part of this app that stops working without signal. A local model has to beat **nothing
at all** — on a train, in a basement, on a spent prepaid balance. It is a **fallback tier**, and
offline-first is rule 1.

It also changes what "free forever" is bounded *by*. Today the bound is what we can afford to give
away. With an on-device tier the bound becomes **what the user's hardware can do**. That is a better
promise for some users and a worse one for others, and the marketing copy must not blur the two.

### 9b. Availability is decided by the device, and the rules are not obvious

Models are **downloaded in-app, named with their provider, and chosen by the user** (research §8).
Three implementation rules, each one the opposite of the obvious approach:

- **Probe available memory, never a device-model table.** iOS exposes `os_proc_available_memory()`,
  Apple's documented way to ask what *this app* may still use before jetsam, with
  `ProcessInfo.physicalMemory` for the total. A table of device names is wrong the week a phone
  ships, and per [MOBILE.md](../MOBILE.md) **we cannot hotfix**.
- **Thresholds live in `app_config`, not the binary** — beside `min_supported_build` and the kill
  switches, so a model that thrashes in the field can be withdrawn without a store release.
- **Show what a phone cannot run, and say why.** "Needs 6 GB — this phone has 4 GB" rather than a
  silent omission. Same instinct as the sync-failure receipts and the below-the-floor plan notice:
  this app says what happened instead of quietly doing less.

Descriptors are **plain language, led by time-to-first-audio**, because that is where the latency
actually is: 106 ms to 3,658 ms across candidate TTS engines, against 20–30 ms for a 1B model's
first token. The LLM tier gets a different warning — **battery and heat**.

### 9c. Accepted: the device split is regressive

A flagship runs a model locally — free, offline, private, unlimited. A 4 GB phone cannot, so for
that user the only route to good coaching is **paying us or bringing a key**. In an India-first free
app, the cheapest hardware gets the worst deal.

This is accepted, not solved. It is a consequence of hardware, but it must be a decision we made
rather than one discovered in reviews, and it argues for keeping the **free metered tier generous**
rather than treating on-device as its replacement.

### 9d. Voice is metered separately from chat, in every tier

The economics are not comparable and must not share a budget:

| | cost |
|---|---|
| one text turn | **~$0.0005** |
| one minute of realtime speech-to-speech | **~$0.013** (cheapest credible option) |

Five minutes of voice a day is **~$2 per user per month** — about 4,000 text turns. So voice gets
its own minute budget **even inside Plus**; "unlimited" there would let one enthusiastic user cost
more than ten subscriptions. On-device voice (recognition and synthesis) is exempt, because it costs
nothing.

Realtime speech-to-speech additionally needs its own ADR before it is built: it moves **audio** off
the device, which is biometric, and the free tier of the obvious provider trains on submitted
content with human review — already forbidden by rule 3.

### 9e. Gate: an SLM must pass the safety prompts before it is offered

ADR 0016's guardrails assume a capable model. A 1B model follows them **less reliably**.

Propose-confirm protects us structurally — the model can only *propose*, a human confirms, so a weak
model cannot write a wrong row alone. **The eating-disorder refusals have no such backstop.** Any
model offered in the picker must pass the same safety prompts first. Failing that, it does not ship.
This is a gate, not a preference.

### Verified while writing this, because published summaries were wrong

Checked directly against the Hugging Face and GitHub APIs, and against Apple's documentation:

- **LFM2.5-2.6B is not Apache-2.0.** It reports `license: other`, `license_name: lfm1.0`. A widely
  circulated report states Apache-2.0 while ranking it the top pick for tool-calling.
- **TEN VAD is not Apache-2.0.** GitHub reports NOASSERTION; the LICENSE is Apache-2.0 *with
  additional conditions*, including "You may not Deploy the ten-vad in a way that competes with
  Agora's offerings", binding derivative works. Same report recommends it in every stack.
- **Apple's Foundation Models framework requires A17 Pro or later** — iPhone 15 Pro and up. The
  "free, no download, zero per-token cost" on-device model **cannot run on the test device** or on
  most Indian iPhones.
- Confirmed permissive: Gemma 4 E2B/E4B (Apache-2.0, ungated), Qwen3.5 0.8B/2B/4B (Apache-2.0),
  Phi-4 Mini (MIT), Kokoro-82M (Apache-2.0), sherpa-onnx (Apache-2.0). Supertonic is MIT code with
  **OpenRAIL-M weights**.

The pattern is consistent enough to be a rule: **the headline licence describes the wrapper, not the
asset**. Verify weights separately from code, from the registry, before a model enters the picker.

### 9f. Plus is HIGHER CAPS, never unlimited (owner ruling, 2026-09-02)

> "There is no company who [is] unlimited, every company has a cap — and also we are not funded yet."

Both halves are the decision. Unlimited is not the industry norm it is marketed as, and for an
unfunded company an **unbounded per-user cost behind a fixed monthly price** is a bet that no
subscriber is heavy. That bet loses on the users who like the product most.

**The rule that sets every Plus cap:**

```
cap × cost-per-call × 30  <  subscription price × target margin
```

A subscriber who hits their cap **every single day** must still cost less than they pay. Any cap
that fails that line is not a cap, it is a hope. Set the caps from the arithmetic, not from what
sounds generous — and re-check them whenever provider pricing moves, because the left side is
someone else's number.

**The mechanism already exists, which is the good news.** `increment_ai_usage(p_feature, p_cap)`
already takes the cap as a *parameter* (migration 0005) and enforces it atomically server-side. The
Edge Functions pass constants today (`DAILY_CAP = 30` for Vita, 8 for PhotoSnap, 10 for estimates,
2 for plan generation, 12 for extraction). Plus is therefore **not new metering** — it is the same
call with a cap resolved from the caller's entitlement instead of a compile-time constant.

That is the whole server-side change: `cap = f(feature, tier)`. What remains genuinely new is the
entitlement itself — StoreKit and Play Billing, receipt validation, restore-purchases, and a
trustworthy server-side answer to "is this user on Plus right now". The cap must be resolved
**server-side from a verified receipt**, never from a client claim, for the same reason the caps
were put in the Edge Function rather than the app.

**Over the cap stays a gentle prompt, not a broken feature** — the original rule in this ADR, and
it applies to Plus too. A paying user who hits a limit is owed a clear message about when it
resets, not a dead button.

### Open — owner decisions, not recorded here

1. ~~Does Plus mean genuinely unlimited, or higher caps?~~ **Decided: higher caps — see 9f.**
2. Is voice inside Plus, or metered and sold separately?
3. Is the on-device tier free, or a Plus feature? Free is more generous and costs nothing; Plus-
   gating it is the only lever that makes a subscription attractive to a flagship owner who could
   otherwise self-serve.
4. Price point.
