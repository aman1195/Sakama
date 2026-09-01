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
import { resolveUpstream } from "../_shared/gateway.ts";
import {
  BodyReadTimeoutMs,
  fetchUpstream,
  readTextWithin,
  UpstreamTimeout,
} from "../_shared/upstream.ts";
import { unfence } from "../_shared/json_content.ts";
import { servedAsRequested } from "../_shared/model_guard.ts";

const DAILY_CAP = 2; // plan generations per user per day — server-side (design §8)
const MODEL = "google/gemini-2.5-flash"; // cheap, JSON-mode; config-swappable
const MAX_TOKENS = 3000; // richer multi-day-type plans need the headroom

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

MAKE IT FEEL PERSONALLY DESIGNED, NOT A TEMPLATE. A plan with one identical day
repeated seven times is a FAILURE. Specifically:

- Declare 2-4 DISTINCT day types that differ MEANINGFULLY from each other -- in
  calories, eating window, emphasis, or all three. A good weight-loss week might
  pair a regular day with 1-2 lighter "reset" days and, if the user is active, a
  higher-protein day. Give each a short, human label ("Lighter reset day"), not
  a generic one ("Day type 1").
- The weekly schedule MUST use more than one day type. Place the lighter/harder
  days sensibly across the week (e.g. a lighter day after a typical heavy-eating
  day, not two lighter days back to back).
- Name REAL DISHES from the user's own cuisine and diet in allowed_foods,
  blocked_foods and checklist -- not food groups. For a south-Indian vegetarian:
  idli, sambar, rasam, poriyal, curd rice, ragi. For north-Indian: roti, dal,
  paneer, sabzi. Generic advice like "include a protein source" is a FAILURE;
  say "add a katori of sprouts or paneer to lunch" instead.
- checklist: at most 4 items per day type, each specific and doable TODAY, and
  DIFFERENT between day types.
- In a day type's "targets", include ONLY fields that DIFFER from
  targets_default. If a day matches the default, omit "targets" entirely --
  never restate identical numbers.
- Populate "rules" with 1-3 short, encouraging coaching messages tied to a
  day_type (use {"id","when":{"day_type":"<key>"},"effect":{},"message":"..."}).
  These are what the coach says on that day; make them specific and warm.

Rules you MUST follow:
- Respect the user's diet: NEVER suggest non-veg foods to a veg/vegan user; no
  eggs to a vegan; honour the stated cuisine.
- Respect stated health conditions and never contradict them (e.g. diabetes ->
  lower refined carbs / added sugar; hypertension -> lower sodium). You are not
  a clinician: keep it a sensible, safe, general plan with no medical claims.
- Keep targets realistic: base them on a Mifflin-St Jeor maintenance estimate
  from the profile, adjusted for the goal (roughly -15..-20% for weight loss,
  +10..+15% for muscle gain, 0 for maintain). No extreme calorie floors
  (never below ~1200 kcal/day for adults). Lighter days may go below the
  plan default but NEVER below that floor.
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
  // During development OpenRouter has no balance, so this routes to ModelBeat
  // when MODELBEAT_ALL is set. Production intent is unchanged — see
  // _shared/gateway.ts.
  const up = resolveUpstream({
    byok,
    tier: Deno.env.get("MODELBEAT_TIER_PLAN_GEN") || "modelbeat-advanced",
    openRouterModel: MODEL,
  });

  let orRes: Response;
  try {
    orRes = await fetchUpstream(up.url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${up.key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: up.model,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: JSON.stringify(profile) },
      ],
      response_format: { type: "json_object" },
      max_tokens: MAX_TOKENS,
    }),
    }, UpstreamTimeout.plan);
  } catch (e) {
    // A HANG IS NOT FREE. Without a deadline this await never returns, the
    // platform kills the function, and the refund below never runs — the user
    // loses one of their daily allowance and gets nothing back. Nothing was
    // billed upstream either way (#104).
    console.error(`upstream unreachable feature=plan_gen :: ${e}`);
    // NO REFUND on an abandoned request — see migration 0009 and the note in
    // vita/index.ts.
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }
  // Refund a rejected request (see the 0009 migration). Plan generation has the
  // tightest cap of the four, so losing one to a provider outage is the most
  // painful — a user could be locked out of generating a plan all day.
  if (!orRes.ok) {
    // Bounded: this read sits BEFORE the refund below.
    const detail = await readTextWithin(orRes, BodyReadTimeoutMs);
    console.error(`openrouter ${orRes.status} feature=plan_gen :: ${detail.slice(0, 500)}`);
    if (!byok) await supabase.rpc("refund_ai_usage", { p_feature: "plan_gen" });
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }
  const or = await orRes.json();

  // Fail closed if ModelBeat did not serve what was asked. `is_fallback` is an
  // explicit signal from the gateway; absent routing counts as unverified.
  if (up.isModelBeat && !servedAsRequested(or?.extra_fields?.routing_info, up.model)) {
    console.error(
      `modelbeat UNVERIFIED ROUTING feature=plan_gen: asked ${up.model}, ` +
        `got ${JSON.stringify(or?.extra_fields?.routing_info)}`,
    );
    if (!byok) await supabase.rpc("refund_ai_usage", { p_feature: "plan_gen" });
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }

  const content = or?.choices?.[0]?.message?.content;
  if (typeof content !== "string") {
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }

  // Pass the model JSON through; the CLIENT validates hard (untrusted input).
  return new Response(unfence(content), {
    headers: { "Content-Type": "application/json" },
  });
});
