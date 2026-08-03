# 05 · AI plan generation (M4.4)

> Design for the `generate-plan` Edge Function and its client path. Turns an onboarded profile
> into a **plan JSON** (the [04-plan-engine](04-plan-engine.md) v1 contract) that the user can apply.
> Decisions inherited: [ADR 0007](../adr/0007-plan-engine-as-json-data.md) (plans are data),
> [ADR 0011](../adr/0011-serverless-ai-gateway.md) (serverless gateway, no self-hosted proxy).
> **Status: proposed — design only, no code yet.**

## 1. Scope

One new capability: **"Generate a plan for me."** The user taps it (Plans surface), the app sends their
profile to an Edge Function, the function asks a schema-capable model for a v1 plan JSON, and the app
runs that JSON through the **already-built** `PlanImporter.validate` (#71) → `PlanRepository.savePlan`
(source `ai_generated`, activated). No new persistence, no new engine — generation only produces the
same JSON that import already handles.

Non-goals (this slice): editing a generated plan, multi-plan A/B, plan "refinement" chat, batch/scheduled
regeneration. Those are later.

## 2. Request path

```
Plans page ("Generate a plan")
  → PlanGenerationService (client)
      → POST /functions/v1/generate-plan   (JWT; optional BYOK)
          → increment_ai_usage("plan_gen", cap)        // atomic budget, BEFORE provider
          → OpenRouter (paid tier, JSON mode)           // provider key server-side only
          ← raw plan JSON string (passed through)
      ← PlanImporter.validate(raw)                       // CLIENT is the hard gate (#71)
          ok  → savePlan(source: "ai_generated", activate: true) → dashboard/Vita update
          err → friendly message, nothing saved
```

This mirrors `estimate-food` exactly (auth → atomic cap → OpenRouter `json_object` → **client validates
hard**). The server never trusts the model output as a plan; the client's tolerant `PlanImporter` +
`Plan.tryParse` (malformed-JSON / non-Map / schema-version gates from review #68) is the authoritative
validator. This is deliberate: one validation code path, already tested, shared by import and generation.

## 3. Edge Function `generate-plan`

Same skeleton as `estimate-food/index.ts`:

- **Auth**: JWT via `supabase.auth.getUser()`; 401 if absent.
- **Input** (`POST` JSON):
  - `profile`: `{ age, sex, height_cm, weight_kg, activity, goal, diet, cuisine, conditions[] }`
    — a compact projection of the on-device profile (no `user_id`, no free text).
  - `byok?`: user's own `sk-...` key (bypasses our cap, uses their upstream — ADR 0011).
  - Validate shape/size server-side (reject absurd payloads with `bad_request`); **not** a plan
    validation, just a guard.
- **Budget**: `increment_ai_usage("plan_gen", DAILY_CAP)` — atomic check-and-increment, charge-on-attempt,
  **before** the provider call. `null` row → `429 budget_exhausted`. Skipped when BYOK.
  - Proposed `DAILY_CAP = 2` (generation is heavy and infrequent; a user rarely needs >1/day). Config
    constant, tunable.
- **Model**: `google/gemini-2.5-flash` (Phase-0 winner, cheap, JSON mode, strong on Indian context) as
  the default, **config-swappable**. Plan generation is more structured than an estimate; if eval shows
  weak plans we escalate to a mid model behind the same interface (a follow-up, not a rewrite).
- **Provider call**: OpenRouter `chat/completions`, `response_format: { type: "json_object" }`,
  `max_tokens: 2000` (a full multi-day plan is larger than an estimate). Key = function secret
  `OPENROUTER_API_KEY`, or the BYOK key.
- **Response**: pass the model's JSON **string** straight through (`Content-Type: application/json`).
  The client validates. Provider failure → `502 provider_error`; usage RPC failure → `500`.

### Error taxonomy (client-mapped to messages)

| HTTP / body | Client message |
|---|---|
| `429 budget_exhausted` | "You've used today's plan generations. Try again tomorrow, or add your own AI key for unlimited." |
| `502 provider_error` / `500` | "Couldn't generate a plan right now. Please try again." |
| 200 but `PlanImporter` rejects | "The generated plan wasn't valid. Please try again." (+ one silent retry, see §6) |

## 4. The system prompt (server-side)

Instructs the model to emit **only** the v1 plan JSON of [04-plan-engine §JSON contract](04-plan-engine.md),
grounded in the profile:

- Honour `goal`, `diet` (never propose non-veg to a veg user), `cuisine`, and `conditions` (e.g.
  diabetes → lower refined carbs; never contradict a stated condition).
- Targets consistent with a Mifflin–St Jeor maintenance estimate ± the goal adjustment (the same basis as
  the computed default), so a generated plan and the computed fallback are in the same ballpark.
- `schema_version: 1`, a sensible `name`, at least one `day_type`, a `schedule` that references only
  declared day types, and `source: "ai_generated"`.
- Keep it realistic and safe: no extreme calorie floors, no medical claims.

The prompt is **long and static** → prompt-cached (cost lever, CLAUDE.md rule 9). Only the profile varies.

## 5. Client integration

- `PlanGenerationService` (in `features/plans/data`): builds the profile projection from the local
  `ProfileRecord`, calls the function (reusing the existing auth/BYOK plumbing that `estimate-food` uses),
  returns `PlanImportResult` (reuses the §2 validator) or a typed transport error.
- Entry point: a **"Generate a plan for me"** action on the Plans page (empty state + a button), busy
  state, and the error messages above. On success → `savePlan(source: "ai_generated")` and pop/snackbar.
- No schema/migration/RLS change. `user_plans.source` already carries `ai_generated`.

## 6. Edge cases & decisions

- **Malformed model output** → `PlanImporter` rejects cleanly (no crash — the #68 guards). Propose **one**
  silent server-agnostic retry on the client before showing the error, since JSON-mode still occasionally
  emits an unparseable or day-type-less plan.
- **Schema-version drift**: if the model emits `schema_version > 1`, the importer's note-2 gate rejects it
  ("needs a newer app"). Acceptable; the prompt pins v1.
- **Budget exhausted mid-generation**: charge-on-attempt means a provider failure still consumes one of the
  2/day. Matches `estimate-food`; acceptable for a hard-capped free tier. (Alternative — charge only on
  success — is a known TOCTOU/refund complexity we deliberately avoid.)
- **Conditions safety**: the prompt forbids contradicting a stated condition, but the model is not a
  clinician. Generated plans are **suggestions**; the app already avoids medical claims. Worth a one-line
  disclaimer on the generate action.

## 7. Testing strategy (the verifiability gap)

**Locally testable (unit, in CI):**
- `PlanGenerationService`: profile → request-body projection is correct and strips PII.
- Response handling: a captured "good" JSON → `PlanImportOk` → would-save with `source: ai_generated`;
  a malformed body → retry-then-error; each HTTP status → the right typed error/message.
- UI: generate action shows busy / success / each error state (widget tests, mocked service).
- The generated JSON flows through the **same** `PlanImporter` tests already in the suite.

**Operator-verified (cannot run in `flutter test` / current CI):**
- The deployed function itself (Deno), the live OpenRouter call, JSON-mode fidelity, prompt quality, and
  the `increment_ai_usage("plan_gen")` path against real Postgres. These need `supabase functions deploy
  generate-plan` + a manual smoke test with a real JWT. **This is the one part that ships unverified by
  CI** and must be smoke-tested before the client feature is enabled (a kill-switchable entry point, per
  MOBILE.md, lets us ship the client dark until the function is verified).

## 8. Decisions (resolved 2026-08-03)

1. **`DAILY_CAP = 2`** for `plan_gen` (non-BYOK). One plan/day is the norm; the 2nd covers a retry.
2. **Model `google/gemini-2.5-flash`** to start — cheapest capable option; config-swappable, escalate only
   if plan quality proves weak.
3. **One silent retry** on invalid model output before surfacing an error (JSON-mode occasionally emits an
   unparseable/day-type-less plan). Worst case doubles that attempt's cost/latency; acceptable.
4. **Ship the client entry dark behind a kill switch** (MOBILE.md) until the deployed function is
   smoke-tested live — bridges the CI verifiability gap of §7. The entry gates on a remote flag so the
   client can merge (fully unit-tested) while the function is verified out-of-band.
