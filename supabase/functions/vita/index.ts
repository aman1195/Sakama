// Sakama AI gateway — Vita, the coach (M3.3, ADR 0011). The wedge's voice:
// a coach that knows the user's EXACT day, so it says something useful, not
// "drink more water" (PRODUCT.md principle 4: "the coach earns its place").
//
// The CLIENT assembles a grounding snapshot from LOCAL data (today's logs,
// targets, profile) and sends it with the message turns — so the function
// stays stateless/cheap and works right after an offline session syncs. The
// snapshot is injected into the system prompt; the model never sees raw PII
// beyond what the user themselves logged.
//
// JWT-gated; atomic per-user daily cap via increment_ai_usage (rule 9); key
// server-side only (rule 3).

import { createClient } from "jsr:@supabase/supabase-js@2";

const DAILY_CAP = 30;   // coach turns/user/day — text is cheap, conversation matters
const MODEL = "google/gemini-2.5-flash";
const MAX_TURNS = 12;   // trailing history window sent upstream (cost bound)

const PERSONA =
  `You are Vita, a warm, knowledgeable Indian nutrition coach inside the Sakama
app. You know Indian food and units (katori, roti, idli, dosa) without being
told. You are a friend who happens to be a brilliant nutritionist — never a
drill sergeant, never shaming, never performing enthusiasm.

RULES:
- Ground EVERY reply in the user's real data below. "You've had 1,180 of 1,650
  kcal and only 28g protein — a katori of dal would help" beats generic advice.
- If the data doesn't support a specific answer, say what you'd need, briefly.
- Keep it short and practical — this is a phone, mid-meal. 1-3 sentences unless
  asked for more.
- Never give medical diagnoses or prescribe for conditions; suggest seeing a
  professional for medical concerns.
- No markdown headers or bullet-symbol spam; plain, friendly text.`;

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
  const turns = Array.isArray(body?.messages) ? body.messages : null;
  const context = typeof body?.context === "string" ? body.context : "";
  if (!turns || turns.length === 0) {
    return new Response(JSON.stringify({ error: "bad_request" }), { status: 400 });
  }
  // Validate + window the turns (untrusted client input).
  const clean = turns
    .filter((m: unknown) =>
      m && typeof (m as { role?: unknown }).role === "string" &&
      typeof (m as { content?: unknown }).content === "string" &&
      ((m as { role: string }).role === "user" ||
        (m as { role: string }).role === "assistant"))
    .slice(-MAX_TURNS)
    .map((m: { role: string; content: string }) => ({
      role: m.role,
      content: m.content.slice(0, 2000),
    }));
  if (clean.length === 0 || clean[clean.length - 1].role !== "user") {
    return new Response(JSON.stringify({ error: "bad_request" }), { status: 400 });
  }

  // Budget (atomic, charge-on-attempt, before the provider call).
  const { data: newCount, error: usageErr } = await supabase
    .rpc("increment_ai_usage", { p_feature: "vita", p_cap: DAILY_CAP });
  if (usageErr) {
    return new Response(JSON.stringify({ error: "usage_error" }), { status: 500 });
  }
  if (newCount === null || newCount === undefined) {
    return new Response(JSON.stringify({ error: "budget_exhausted" }), { status: 429 });
  }

  const system = context
    ? `${PERSONA}\n\n--- The user's data right now ---\n${context.slice(0, 4000)}`
    : PERSONA;

  const orRes = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${Deno.env.get("OPENROUTER_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [{ role: "system", content: system }, ...clean],
      max_tokens: 500,
    }),
  });
  if (!orRes.ok) {
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }
  const or = await orRes.json();
  const reply = or?.choices?.[0]?.message?.content;
  if (typeof reply !== "string" || reply.trim().length === 0) {
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }
  return new Response(JSON.stringify({ reply }), {
    headers: { "Content-Type": "application/json" },
  });
});
