# 0010. Wedge v1 (M0–M3), solo builder — launch the differentiator, fast-follow the rest

**Status:** Accepted · **Date:** 2026-07 · **Grilling outcome** ·
**Amends:** the "everything in the vision" scope in [../ROADMAP.md](../ROADMAP.md)

## Context
Scope was "everything in the vision" (calorie/macro/micro, barcode, water, fasting, weight, food DB,
PhotoSnap, Vita, plan generation + enforcement, workouts, steps, sleep, voice, offline sync, a
built-from-scratch food DB, an AI gateway). Under grilling, two facts landed: the build is **solo**
(one person, first Flutter app, part-time), and "everything" is a 3–4-quarter effort for a *team*. The
common failure mode is real here: build toward everything, ship nothing for months, and the genuinely
differentiating wedge never reaches a user — while the non-differentiating features (workouts, steps,
sleep, plan *enforcement*) gate the differentiating ones.

## Decision
**Keep "everything" as the north star, but launch a much smaller wedge.**

- **v1 = M0–M3:** onboarding + tracking core + Indian food DB (bundled) + **PhotoSnap + Vita**. The
  differentiator, end to end, in real users' hands.
- **The launch line is drawn after M3**, not M7.
- **Fast-follows to existing users:** plan engine (M4), fasting/workouts/steps/sleep (M5), voice +
  micronutrient polish (M6), launch hardening (M7).
- Same milestone *order* as before; only the "this is what we ship" line moves earlier.

## Consequences
- First release is months sooner; the risky premise (does Indian PhotoSnap resonate?) gets tested with
  real users far earlier.
- Solo-dev complexity is concentrated on the wedge, not spread across everything.
- Every architecture choice is now judged against "does a solo dev need this for the wedge?" — which
  drove [ADR 0011](0011-serverless-ai-gateway.md) (no self-hosted proxy) and
  [ADR 0012](0012-ship-bundled-food-data.md) (bundle, don't recompute).
- PowerSync ([ADR 0003](0003-supabase-offline-first-drift-powersync.md)) was pressure-tested under this
  lens and **deliberately kept** — multi-device + backup from day one, accepting the added complexity.
