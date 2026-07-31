# 0015. Anonymous sign-in abuse posture for v1 — caps + rate limit + monitoring, defer attestation

**Status:** Accepted · **Date:** 2026-07-31 · **Relates to:** [0011](0011-serverless-ai-gateway.md)
(AI gateway + per-user budgets, rule 9), the anonymous-first auth decision (M3.1)

## Context

Auth is **anonymous-first**: the first launch silently creates an anonymous Supabase session so AI and
budgets work with zero signup friction. That friction-free onboarding is a deliberate, locked product
decision.

Anonymous sign-in has a cost-abuse vector: each anonymous user receives fresh per-user daily AI caps, so
an attacker who farms many anonymous users multiplies free AI. **PhotoSnap is the exposed call** because
vision is the priciest per request.

Supabase's dashboard nudges toward **captcha on sign-in** as the mitigation. But enabling Supabase
captcha forces the client to pass a captcha token on **every** `signInAnonymously`, which puts a captcha
challenge on the very first cold launch. That directly contradicts the zero-friction anonymous-first
decision.

## Options considered

1. **Caps + Supabase per-IP anon rate limit + monitoring** (chosen for v1). Zero added friction. Bounds
   per-user cost via the existing daily caps; Supabase throttles anon creation per IP; the operator
   watches usage for farm signals. Residual risk: a determined distributed attacker.
2. **Mobile attestation** (App Attest / Play Integrity). Zero user friction, the mobile-correct
   equivalent of captcha, but real per-platform engineering and can be awkward in dev/review builds.
3. **Captcha on anonymous sign-in.** Strongest against farming, but breaks zero-friction onboarding.
   Rejected on that ground.

## Decision

**For v1: option 1.** Keep the per-user daily AI caps (estimate 10, PhotoSnap 8, Vita 30; charged on
attempt, enforced atomically in `increment_ai_usage`). Rely on Supabase's per-IP anonymous rate limit.
Add operator **monitoring** so farming is visible: the `admin_ai_usage_daily` view
(migration `20260731000006`) surfaces distinct users, total calls, and max/avg per-user calls per
feature per day. The farm signal is distinct-users rising sharply while max-user-calls sits at the cap.

**Do not** enable captcha on anonymous sign-in (breaks the locked zero-friction decision). Attestation is
**deferred, not rejected** — it is the intended real fix if abuse appears.

## Revisit trigger

Add **App Attest / Play Integrity** (option 2) when monitoring shows sustained anon-farming — concretely:
a day-over-day spike in `distinct_users` for `photosnap` (or any feature) with `max_user_calls` pinned at
the cap, not explained by real launch growth. Tracked in the deferred-attestation issue.

## Consequences

- v1 ships with the onboarding the product decision demands: silent, zero-friction anonymous sessions.
- Cost exposure is bounded per user by the caps; the uncapped risk is breadth (many users), which the
  monitoring view makes observable before it becomes expensive.
- If abuse never materializes, we spent nothing on friction or attestation engineering. If it does, the
  signal and the fix are both pre-decided.
