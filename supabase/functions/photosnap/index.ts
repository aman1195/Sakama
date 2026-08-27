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
import { resolveUpstream } from "../_shared/gateway.ts";
import { unfence } from "../_shared/json_content.ts";
import { servedAsRequested } from "../_shared/model_guard.ts";

const DAILY_CAP = 8;          // photos/user/day — vision is pricier than text
const VITA_CAP = 30;          // a converse photo also costs one coach exchange
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

// CONVERSE mode (docs/architecture/07-photo-in-chat.md). A SEPARATE prompt by
// design: the log-mode prompt above earned the Phase-0 GO decision and must not
// be put at risk by conversational tuning.
const CONVERSE_PROMPT =
  `You are Vita, a warm Indian nutrition coach, looking at a photo the user sent.
Reply ONLY with JSON:
{"items": [ {
   "name": string, "portion_label": string, "grams": number,
   "energy_kcal": number,            // FOR THE WHOLE PORTION
   "protein_g": number, "carb_g": number, "fat_g": number,
   "confidence": number
} ],
 "description": string,   // one short line naming what is visible, e.g.
                          // "two rotis, dal tadka, cucumber salad"
 "answer": string,        // your reply to the user, 1-3 sentences
 "log_intent": "yes"|"no",// does the user want this SAVED to their diary?
 "meal": "breakfast"|"lunch"|"dinner"|"snack"|null}

Rules:
- Answer the user's question directly, grounded in their data below and in what
  you can actually SEE (portion size, visible oil, what is missing from the
  plate). That visual judgement is why they sent a photo.
- If the image is NOT a plated meal — a menu, a packet, an ingredients label, a
  supplement — still ANSWER helpfully and return "items": []. Only a plated meal
  produces loggable items.
- Never invent food that is not in frame. Standard Indian portions (katori
  ~150g, roti ~40g, idli ~35g, plate ~300g).
- JUDGE INTENT, do not follow a rule blindly. Set "log_intent":"yes" ONLY when
  the user is telling you they ATE this or is asking you to save it — "I had
  this for lunch", "log it", "just finished this". Set "no" when they are
  asking about it — "should I eat this?", "what do you think?", "is this too
  oily?", or no caption at all. When in doubt, "no": the cost of a missed offer
  is one extra sentence from them; the cost of a wrong one is a phantom meal in
  their diary.
- With "log_intent":"yes", set "meal" from what they said, or from the time of
  day if they did not say. Otherwise "meal": null.
- Never say "want me to log this?" in the answer — the app shows a confirm card
  when it is warranted. Answer what they actually asked.
- No medical diagnoses; suggest a professional for medical concerns.`;

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
  // mode defaults to today's behaviour, so existing callers are untouched.
  const converse = body?.mode === "converse";
  const question = typeof body?.question === "string" ? body.question.trim() : "";
  const ctx = typeof body?.context === "string" ? body.context.slice(0, 4000) : "";
  if (typeof image !== "string" || image.length < 100) {
    return new Response(JSON.stringify({ error: "bad_request" }), { status: 400 });
  }
  // base64 is ~4/3 the byte size; cheap guard before paying for the call.
  if (image.length * 0.75 > MAX_IMAGE_BYTES) {
    return new Response(JSON.stringify({ error: "image_too_large" }), { status: 413 });
  }
  const dataUrl = image.startsWith("data:") ? image : `data:${mime};base64,${image}`;

  // ATOMIC budget check-and-increment (rule 9), charge-on-attempt, as the caller.
  //
  // SCARCE CAP FIRST (design §3): increment_ai_usage returns NULL WITHOUT
  // consuming when already at cap, so charging the binding cap (photos, 8)
  // first makes the common refusal cost nothing. Charging the abundant cap
  // first would burn an exchange per retry for a user who is out of photos.
  if (!byok) {
    const { data: photoCount, error: usageErr } = await supabase
      .rpc("increment_ai_usage", { p_feature: "photosnap", p_cap: DAILY_CAP });
    if (usageErr) {
      return new Response(JSON.stringify({ error: "usage_error" }), { status: 500 });
    }
    if (photoCount === null || photoCount === undefined) {
      // Say WHICH cap: a photos-exhausted user can still text-chat, and the
      // scarce-first order preserved that budget for them (review #94).
      return new Response(
        JSON.stringify({ error: "budget_exhausted", which: "photo" }),
        { status: 429 },
      );
    }
    // A converse photo is also a coach exchange (ADR 0016 decision 6).
    if (converse) {
      const { data: vitaCount, error: vitaErr } = await supabase
        .rpc("increment_ai_usage", { p_feature: "vita", p_cap: VITA_CAP });
      if (vitaErr) {
        return new Response(JSON.stringify({ error: "usage_error" }), { status: 500 });
      }
      if (vitaCount === null || vitaCount === undefined) {
        return new Response(
          JSON.stringify({ error: "budget_exhausted", which: "exchange" }),
          { status: 429 },
        );
      }
    }
  }

  // During development OpenRouter has no balance, so this routes to ModelBeat
  // when MODELBEAT_ALL is set. Production intent is unchanged — see
  // _shared/gateway.ts.
  const up = resolveUpstream({
    byok,
    tier: Deno.env.get("MODELBEAT_TIER_PHOTOSNAP") || "modelbeat-advanced",
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
        {
          role: "system",
          content: converse ? `${CONVERSE_PROMPT}\n\nUSER DATA:\n${ctx}` : SYSTEM_PROMPT,
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: converse
                ? (question.length > 0
                  ? question
                  : "What is this, and should I eat it given my plan?")
                : "Identify and estimate the foods in this meal.",
            },
            { type: "image_url", image_url: { url: dataUrl } },
          ],
        },
      ],
      response_format: { type: "json_object" },
      // converse also returns a description + a prose answer on top of items.
      max_tokens: converse ? 1000 : 700,
    }),
  });
  // Upstream failures used to collapse to a bare 502, discarding what the
  // provider actually said — which turned a two-minute diagnosis into reading
  // dashboard logs. Log the status and a bounded slice of the body.
  //
  // SAFE TO LOG: this is OpenRouter's ERROR RESPONSE, never the request. The
  // image, the prompt, the user context and the API key are not in it, so no
  // health data and no secret reaches the log (OWASP M1, CLAUDE.md rule 3).
  if (!orRes.ok) {
    const detail = await orRes.text().catch(() => "");
    console.error(
      `openrouter ${orRes.status} mode=${converse ? "converse" : "analyze"} ` +
        `image_b64_len=${image.length} byok=${byok ? "yes" : "no"} :: ` +
        detail.slice(0, 500),
    );
    // REFUND: the provider rejected the request, so no tokens were billed and
    // the user should not lose a daily estimate for our outage. Only this
    // branch refunds — a 2xx we failed to parse WAS charged upstream (see the
    // 0009 migration). Best-effort: a failed refund must not turn a provider
    // error into a 500, so the response below is unconditional.
    if (!byok) {
      await supabase.rpc("refund_ai_usage", { p_feature: "photosnap" });
      if (converse) await supabase.rpc("refund_ai_usage", { p_feature: "vita" });
    }
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }
  const or = await orRes.json();

  // Fail closed if ModelBeat did not serve what was asked. `is_fallback` is an
  // explicit signal from the gateway; absent routing counts as unverified.
  if (up.isModelBeat && !servedAsRequested(or?.extra_fields?.routing_info, up.model)) {
    console.error(
      `modelbeat UNVERIFIED ROUTING feature=photosnap: asked ${up.model}, ` +
        `got ${JSON.stringify(or?.extra_fields?.routing_info)}`,
    );
    if (!byok) await supabase.rpc("refund_ai_usage", { p_feature: "photosnap" });
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }

  const content = or?.choices?.[0]?.message?.content;
  if (typeof content !== "string") {
    // A 200 with no usable content — a different failure from a rejected
    // request, and previously indistinguishable from one.
    console.error(
      `openrouter 200 but no content :: ${JSON.stringify(or).slice(0, 500)}`,
    );
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }

  // Pass the model JSON straight through; the CLIENT validates hard.
  return new Response(unfence(content), {
    headers: { "Content-Type": "application/json" },
  });
});
