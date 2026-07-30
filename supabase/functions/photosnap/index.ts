// Sakama AI gateway — PhotoSnap (M3.2, ADR 0011). The wedge validated in
// Phase 0 (gemini-2.5-flash, 9% median kcal error on Indian meals).
//
// App (JWT + base64 image) -> THIS FUNCTION -> OpenRouter vision (PAID tier;
// free tiers train on data — unacceptable for health photos) -> structured
// JSON items back. Provider key lives HERE (CLAUDE.md rule 3). Per-user daily
// cap enforced atomically against ai_usage BEFORE any provider call (rule 9),
// via the same increment_ai_usage RPC as estimate-food. The CLIENT re-validates
// every field (untrusted model output must never enter a health diary raw).

import { createClient } from "jsr:@supabase/supabase-js@2";

const DAILY_CAP = 8;          // photos/user/day — vision is pricier than text
const MAX_IMAGE_BYTES = 6_000_000; // ~6MB decoded guard (client should downscale)
const MODEL = "google/gemini-2.5-flash"; // Phase 0 winner; config-swappable

const SYSTEM_PROMPT =
  `You identify the foods in a photo of an Indian meal and estimate nutrition.
Reply ONLY with JSON:
{"items": [ {
   "name": string,                 // dish as an Indian would say it
   "portion_label": string,        // "1 katori", "2 roti", "1 bowl", "1 plate"
   "grams": number,                // your best estimate of the portion in grams
   "energy_kcal": number,          // FOR THE WHOLE PORTION (not per 100g)
   "protein_g": number, "carb_g": number, "fat_g": number,
   "confidence": number            // 0..1, honest per-item uncertainty
} ] }
Rules: one entry per distinct food you can see. Use standard Indian portions
(katori cooked dal/veg ~150g, roti ~40g, idli ~35g, plate ~300g). Estimate what
is VISIBLE; do not invent sides that are not in frame. If the image contains no
food, reply {"error":"no_food"}. Keep it to at most 8 items.`;

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

  const body = await req.json().catch(() => ({}));
  // BYOK (ADR 0011): a user's own OpenRouter key. Present => use it upstream
  // and DO NOT charge our budget (they pay their provider). Never logged.
  const byokRaw = typeof body?.byok === "string" ? body.byok.trim() : "";
  const byok = byokRaw.startsWith("sk-") && byokRaw.length > 20 ? byokRaw : "";
  const image = body?.image; // base64 (no data: prefix) or a data URL
  const mime = typeof body?.mime === "string" ? body.mime : "image/jpeg";
  if (typeof image !== "string" || image.length < 100) {
    return new Response(JSON.stringify({ error: "bad_request" }), { status: 400 });
  }
  // base64 is ~4/3 the byte size; cheap guard before paying for the call.
  if (image.length * 0.75 > MAX_IMAGE_BYTES) {
    return new Response(JSON.stringify({ error: "image_too_large" }), { status: 413 });
  }
  const dataUrl = image.startsWith("data:") ? image : `data:${mime};base64,${image}`;

  // ATOMIC budget check-and-increment (rule 9), charge-on-attempt, as the caller.
  if (!byok) {
    const { data: newCount, error: usageErr } = await supabase
      .rpc("increment_ai_usage", { p_feature: "photosnap", p_cap: DAILY_CAP });
    if (usageErr) {
      return new Response(JSON.stringify({ error: "usage_error" }), { status: 500 });
    }
    if (newCount === null || newCount === undefined) {
      return new Response(JSON.stringify({ error: "budget_exhausted" }), { status: 429 });
    }
  }

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
        {
          role: "user",
          content: [
            { type: "text", text: "Identify and estimate the foods in this meal." },
            { type: "image_url", image_url: { url: dataUrl } },
          ],
        },
      ],
      response_format: { type: "json_object" },
      max_tokens: 700,
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

  // Pass the model JSON straight through; the CLIENT validates hard.
  return new Response(content, {
    headers: { "Content-Type": "application/json" },
  });
});
