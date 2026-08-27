// Sakama AI gateway — food estimation (M2.4, ADR 0011).
//
// App (JWT) -> THIS FUNCTION -> OpenRouter (cheap model, PAID tier: free tiers
// train on data — unacceptable for a health app) -> structured JSON back.
// The provider key lives HERE, never in the client (CLAUDE.md rule 3).
// Per-user daily budget enforced against ai_usage (rule 9) BEFORE any
// provider call, so cost is bounded by construction.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { resolveUpstream } from "../_shared/gateway.ts";
import { unfence } from "../_shared/json_content.ts";
import { servedAsRequested } from "../_shared/model_guard.ts";

const DAILY_CAP = 10; // estimates per user per day — server-side, not client
const MODEL = "google/gemini-2.5-flash"; // Phase 0 winner; config-swappable

const SYSTEM_PROMPT = `You estimate nutrition for Indian dishes. Reply ONLY with JSON:
{"name": string, "energy_kcal_100g": number, "protein_g_100g": number,
 "carb_g_100g": number, "fat_g_100g": number, "fiber_g_100g": number|null,
 "serving_label": string|null, "serving_grams": number|null,
 "confidence": number (0..1, your honest uncertainty),
 "assumptions": string (oil/preparation assumed, one short sentence)}
Values are PER 100 g of the prepared dish. Use standard Indian preparations
(katori ≈ 150 g, roti ≈ 40 g, idli ≈ 35 g). If the input is not a food, reply
{"error":"not_food"}.`;

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
  const dish = parsed?.dish;
  // BYOK (ADR 0011): user's own OpenRouter key -> use upstream + skip our cap.
  const byokRaw = typeof parsed?.byok === "string" ? parsed.byok.trim() : "";
  const byok = byokRaw.startsWith("sk-") && byokRaw.length > 20 ? byokRaw : "";
  if (typeof dish !== "string" || dish.trim().length < 2 || dish.length > 120) {
    return new Response(JSON.stringify({ error: "bad_request" }), { status: 400 });
  }

  // Budget: ATOMIC check-and-increment in Postgres (review #46 — the previous
  // read-check-write here was TOCTOU-racy under concurrency). Runs as the
  // CALLER (auth.uid() = user), charge-on-attempt, BEFORE the provider call.
  // No row back = cap spent.
  if (!byok) {
    const { data: newCount, error: usageErr } = await supabase
      .rpc("increment_ai_usage", { p_feature: "estimate", p_cap: DAILY_CAP });
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
    tier: Deno.env.get("MODELBEAT_TIER_ESTIMATE") || "modelbeat-standard",
    openRouterModel: MODEL,
  });

  const orRes = await fetch(up.url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${up.key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: up.model,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: dish.trim() },
      ],
      response_format: { type: "json_object" },
      max_tokens: 400,
    }),
  });
  // Same rule as photosnap (see the 0009 migration): the provider REJECTED the
  // request, so no tokens were billed and the user must not lose an estimate
  // for our outage. A 2xx we cannot parse is NOT refunded — that one was
  // billed. Log the upstream reason: a bare 502 is what made the 2026-08-07
  // credit exhaustion take half an hour to identify.
  if (!orRes.ok) {
    const detail = await orRes.text().catch(() => "");
    console.error(`openrouter ${orRes.status} feature=estimate :: ${detail.slice(0, 500)}`);
    if (!byok) await supabase.rpc("refund_ai_usage", { p_feature: "estimate" });
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }
  const or = await orRes.json();

  // Fail closed if ModelBeat did not serve what was asked. `is_fallback` is an
  // explicit signal from the gateway; absent routing counts as unverified.
  if (up.isModelBeat && !servedAsRequested(or?.extra_fields?.routing_info, up.model)) {
    console.error(
      `modelbeat UNVERIFIED ROUTING feature=estimate: asked ${up.model}, ` +
        `got ${JSON.stringify(or?.extra_fields?.routing_info)}`,
    );
    if (!byok) await supabase.rpc("refund_ai_usage", { p_feature: "estimate" });
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
