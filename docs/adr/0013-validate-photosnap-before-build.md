# 0013. Validate PhotoSnap accuracy before building the app (spike-first)

**Status:** Accepted · **Date:** 2026-07 · **Grilling outcome**

## Context
The entire product thesis rests on one untested assumption: **a VLM estimates a home-cooked Indian
meal's macros well enough to be useful.** Our own research flagged that absolute portion estimation from
a flat photo is the hard part, and Indian mixed thalis are the hard case. If it does not work, the moat,
the freemium wall on PhotoSnap, and "better AI than HealthifyMe" all collapse — and a solo dev could
discover this only *after* building M0–M3 around it. It is the cheapest, highest-leverage thing to test,
and it needs **no app** — just API calls with images.

## Decision
**A validation spike is the first task — before installing Flutter.**

- ~20–30 photos of real Indian meals, each with a best-estimate "true" macro figure.
- Run through 2–3 VLMs (Gemini Flash, Claude, optionally GPT) using the **ported Fud AI prompt** adapted
  to Indian portion units (katori, roti, idli).
- Judge whether estimates land within a **useful band** (target ±25–30%).
- **Free provider tiers are fine here** — it is our own test data, not user health data
  ([ADR 0011](0011-serverless-ai-gateway.md)).

## Consequences
- **Go:** proceed to M0 with confidence, and the spike already picks the v1 model.
- **No-go:** learn it in a day, then pivot the wedge (barcode/search-first, or invest in a two-stage
  segmentation + VLM pipeline) *before* sinking a month.
- Reorders nothing else — it front-loads the one test that can invalidate the plan. Appears as **Phase 0**
  in [../ROADMAP.md](../ROADMAP.md), ahead of M0.
- Output: a short findings note in `docs/research/` (model chosen, error band, failure cases).
