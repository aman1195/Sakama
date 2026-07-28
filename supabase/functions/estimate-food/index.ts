// Sakama AI gateway — food estimation (M2.4, ADR 0011).
//
// App (JWT) -> THIS FUNCTION -> OpenRouter (cheap model, PAID tier: free tiers
// train on data — unacceptable for a health app) -> structured JSON back.
// The provider key lives HERE, never in the client (CLAUDE.md rule 3).
// Per-user daily budget enforced against ai_usage (rule 9) BEFORE any
// provider call, so cost is bounded by construction.

import { createClient } from "jsr:@supabase/supabase-js@2";

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
  const userId = userData.user.id;

  const { dish } = await req.json().catch(() => ({}));
  if (typeof dish !== "string" || dish.trim().length < 2 || dish.length > 120) {
    return new Response(JSON.stringify({ error: "bad_request" }), { status: 400 });
  }

  // Budget check (service role bypasses RLS; ai_usage is server-owned).
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const day = new Date().toISOString().slice(0, 10);
  const { data: usage } = await admin.from("ai_usage")
    .select("count").eq("user_id", userId).eq("day", day)
    .eq("feature", "estimate").maybeSingle();
  if ((usage?.count ?? 0) >= DAILY_CAP) {
    return new Response(JSON.stringify({ error: "budget_exhausted" }), { status: 429 });
  }

  // Provider call via OpenRouter (managed gateway; key is a function secret).
  const orRes = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${Deno.env.get("OPENROUTER_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: dish.trim() },
      ],
      response_format: { type: "json_object" },
      max_tokens: 400,
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

  // Count usage AFTER a successful provider call (a failed call costs the user
  // nothing), atomically via upsert.
  await admin.from("ai_usage").upsert(
    { user_id: userId, day, feature: "estimate", count: (usage?.count ?? 0) + 1 },
    { onConflict: "user_id,day,feature" },
  );

  // Pass the model JSON through; the CLIENT validates hard (untrusted input).
  return new Response(content, {
    headers: { "Content-Type": "application/json" },
  });
});
