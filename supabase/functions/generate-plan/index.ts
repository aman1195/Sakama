// Sakama AI gateway — plan generation (M4.4, ADR 0007 + 0011).
//
// App (JWT + profile projection) -> THIS FUNCTION -> OpenRouter (cheap model,
// PAID tier: free tiers train on data — unacceptable for a health app) -> a
// v1 plan JSON (docs/architecture/04-plan-engine.md) back. The provider key
// lives HERE, never in the client (CLAUDE.md rule 3). Per-user daily budget
// enforced against ai_usage (rule 9) BEFORE any provider call.
//
// The model output is UNTRUSTED: this function passes it straight through and
// the CLIENT validates hard with PlanImporter (#71). One validation path,
// shared by import and generation (docs/architecture/05-plan-generation.md).

import { createClient } from "jsr:@supabase/supabase-js@2";

const DAILY_CAP = 2; // plan generations per user per day — server-side (design §8)
const MODEL = "google/gemini-2.5-flash"; // cheap, JSON-mode; config-swappable
const MAX_TOKENS = 2000; // a full multi-day plan is larger than an estimate

const SYSTEM_PROMPT =
  `You design a personal nutrition plan and reply with ONLY a JSON object in
this exact schema (Sakama plan v1). No prose, no markdown fences.

{
  "schema_version": 1,
  "id": "generated",
  "name": string,                         // short, human, e.g. "4-Week Reset"
  "goal": "lose_weight"|"detox"|"build_muscle"|"manage_condition"|"maintain",
  "source": "ai_generated",
  "duration_days": number|null,
  "targets_default": {
    "calories": number,
    "macros": { "protein_g": number, "carb_g": number, "fat_g": number, "fiber_g": number },
    "water_ml": number
  },
  "day_types": {                          // at least one; keys referenced by schedule
    "<key>": {
      "label": string,
      "targets": { "calories": number, "macros": { "protein_g": number, "carb_g": number, "fat_g": number, "fiber_g": number } },
      "fasting_window": { "eat_start": "HH:mm", "eat_end": "HH:mm" }|null,
      "allowed_foods": string[]|null,     // null = anything allowed
      "blocked_foods": string[],
      "checklist": string[]
    }
  },
  "schedule": {                           // reference ONLY declared day_type keys
    "type": "weekly", "map": { "mon": "<key>", ..., "sun": "<key>" }
  },
  "rules": []
}

Rules you MUST follow:
- Respect the user's diet: NEVER suggest non-veg foods to a veg/vegan user; no
  eggs to a vegan; honour the stated cuisine.
- Respect stated health conditions and never contradict them (e.g. diabetes ->
  lower refined carbs / added sugar; hypertension -> lower sodium). You are not
  a clinician: keep it a sensible, safe, general plan with no medical claims.
- Keep targets realistic: base them on a Mifflin-St Jeor maintenance estimate
  from the profile, adjusted for the goal (roughly -15..-20% for weight loss,
  +10..+15% for muscle gain, 0 for maintain). No extreme calorie floors
  (never below ~1200 kcal/day for adults).
- schema_version MUST be 1. Use "weekly" schedule. Every schedule value MUST be
  a declared day_type key. Output MUST be valid JSON and nothing else.`;

Deno.serve(async (req) => {
  const auth = req.headers.get("Authorization") ?? "";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } } },
  );
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData?.user) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
  }

  const parsed = await req.json().catch(() => ({}));
  const profile = parsed?.profile;
  // BYOK (ADR 0011): user's own OpenRouter key -> use upstream + skip our cap.
  const byokRaw = typeof parsed?.byok === "string" ? parsed.byok.trim() : "";
  const byok = byokRaw.startsWith("sk-") && byokRaw.length > 20 ? byokRaw : "";
  // Shape/size guard only — NOT plan validation (the client does that).
  if (
    typeof profile !== "object" || profile === null ||
    JSON.stringify(profile).length > 2000
  ) {
    return new Response(JSON.stringify({ error: "bad_request" }), { status: 400 });
  }

  // Budget: ATOMIC check-and-increment in Postgres (charge-on-attempt, BEFORE
  // the provider call). No row back = cap spent. Skipped for BYOK.
  if (!byok) {
    const { data: newCount, error: usageErr } = await supabase
      .rpc("increment_ai_usage", { p_feature: "plan_gen", p_cap: DAILY_CAP });
    if (usageErr) {
      return new Response(JSON.stringify({ error: "usage_error" }), { status: 500 });
    }
    if (newCount === null || newCount === undefined) {
      return new Response(JSON.stringify({ error: "budget_exhausted" }), { status: 429 });
    }
  }

  // Provider call via OpenRouter (managed gateway; key is a function secret).
  const orRes = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${byok || Deno.env.get("OPENROUTER_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: JSON.stringify(profile) },
      ],
      response_format: { type: "json_object" },
      max_tokens: MAX_TOKENS,
    }),
  });
  if (!orRes.ok) {
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }
  const or = await orRes.json();
  const content = or?.choices?.[0]?.message?.content;
  if (typeof content !== "string") {
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }

  // Pass the model JSON through; the CLIENT validates hard (untrusted input).
  return new Response(content, {
    headers: { "Content-Type": "application/json" },
  });
});
