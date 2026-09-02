# Where Vita runs, and who pays for it

**Date:** 2026-09-02 · One page over [ADR 0009](../adr/0009-freemium-monetization.md) and
[voice-agent-architecture.md](voice-agent-architecture.md). Costs and sizes verified against provider
pricing pages and the Hugging Face / GitHub APIs on this date — re-check before committing, provider
pricing moves.

---

## 1. The four paths — two already work

| Path | Cost to us | State |
|---|---|---|
| **Free, metered** — Vita 30/day · PhotoSnap 8 · estimates 10 · plans 2 · memory 12 | per call, capped | **BUILT**, enforced server-side against `ai_usage` |
| **BYOK** — user's own provider key | ~$0 | **BUILT** — `byok_page.dart`, `byok_store.dart`, threaded through every AI path; caps skipped when a key is present |
| **Sakama Plus** — subscription, higher caps | per call, capped | **NOT BUILT** — decided July 2026; no billing, no receipts, no entitlement check |
| **On-device** — model runs on the user's phone | **$0** | **NOT BUILT** — research only |

## 2. What is decided

**Plus means higher caps, never unlimited.** Every serious company caps, and an unbounded per-user
cost behind a fixed monthly price is a bet that no subscriber is heavy — a bet that loses on the
users who like the product most. Owner ruling, 2026-09-02, unfunded company.

    cap × cost-per-call × 30  <  subscription price × margin

A subscriber who hits their cap *every day* must still cost less than they pay. A cap failing that
line is not a cap, it is a hope.

**The on-device model's job is offline, not quality.** A 1–2B model loses on coaching and that is the
wrong test. Vita is the only part of this app that stops working without signal, so a local model
has to beat *nothing at all* — on a train, in a basement, on a spent prepaid balance. Rule 1
reaching the one feature that never had it.

**Models are the user's choice, downloaded in-app**, named with their provider. Nothing bundled, so
the store binary stays near today's 25.6 MB — and naming them *is* the attribution these licences
ask for.

**Availability is decided by the device.** Probe available memory (`os_proc_available_memory()`),
never a device-model table. Thresholds in `app_config`, not the binary. Show what a phone cannot run
and *why*. Labels lead with **how long before it talks**, then how it sounds; the on-device LLM gets
a battery-and-heat warning instead.

**Voice is metered separately in every tier**, including Plus.

**Any on-device model must pass the safety prompts before it is offered.** Propose-confirm protects a
write structurally; the eating-disorder refusals have no such backstop, and a small model follows
them less reliably. A gate, not a preference.

## 3. What it costs

| Thing | Cost | Meaning |
|---|---|---|
| One text turn with Vita | ~$0.0005 | Affordable to give away at 30/day |
| One minute of realtime voice | ~$0.013 | ≈ 4,000 text turns |
| 5 min of voice a day | **~$2 / user / month** | Cannot be free at any scale |
| On-device | $0 | But a 0.9–1.2 GB download |
| BYOK | $0 | User's own key, own terms |

## 4. What a phone can actually hold

Sizes measured from the registries. The iPhone 13 has **4 GB RAM** — 1–2B works, 4B does not.

| Role | Model | Size | Licence |
|---|---|---|---|
| Speech in | sherpa-onnx streaming ASR | 60–80 MB | Apache-2.0 |
| Voice out | Kokoro-82M `uint8f16` | **114 MB** | Apache-2.0 |
| Voice out | Supertonic 3 | 401 MB | MIT code · **OpenRAIL-M weights** |
| Offline coach | Gemma 3 1B `Q4` | 714 MB | Gemma terms |
| Offline coach | Qwen3 1.7B `Q4` | 1,010 MB | Apache-2.0 |

## 5. Accepted, not solved: the device split is regressive

A flagship runs a model locally — free, offline, unlimited. A 4 GB phone cannot, so that user's only
route to good coaching is paying us or bringing a key. **In an India-first free app, the cheapest
hardware gets the worst deal.** It follows from hardware, but it should be a decision we made rather
than one found in reviews — and it argues for keeping the free metered tier generous.

## 6. What the research changed

Four claims from circulated reports were wrong, each checked against the source registry:

- **LFM2.5** is `lfm1.0`, not Apache-2.0 — while being the top pick for tool-calling.
- **TEN VAD** is Apache-2.0 *with an Agora non-compete* binding derivative works — while appearing
  in every recommended stack.
- **Supertonic's** MIT badge covers the code; the weights are OpenRAIL-M.
- **Apple's free on-device model** needs A17 Pro — it cannot run on the test iPhone, or on most
  Indian iPhones.

Standing rule: **the headline licence describes the wrapper, not the asset.** Verify weights
separately from code before a model enters the picker.

## 7. Still open — owner decisions

1. **Is voice inside Plus, or sold separately?** Now Plus is capped, voice can sit inside it with its
   own tighter minute budget — cheaper and simpler to explain.
2. **Is the on-device tier free, or a Plus feature?** Free is more generous and costs nothing;
   Plus-gating it is the only lever that makes a subscription attractive to a flagship owner who
   could otherwise self-serve.
3. **Price.** It sets every cap through the formula in §2, so nothing else finalises until this does.

## 8. Next

Everything above rests on figures that published reports mark *estimated*, measured on hardware two
to four generations newer than the target.

1. **Spike on the iPhone 13 first** — size, cold start, time-to-first-audio, battery and heat,
   accuracy on Indian English. That sets the device tiers and the descriptor wording.
2. **Then own the audio input** — streaming recognition, a better voice, and real interruption are
   one piece of work, not three; none is reachable while the current plugin owns audio capture.
3. **Plus is mostly not new metering** — `increment_ai_usage(p_feature, p_cap)` already takes the cap
   as a parameter and enforces it atomically. What is new is billing, receipts, and a trustworthy
   server-side answer to "is this user on Plus".
