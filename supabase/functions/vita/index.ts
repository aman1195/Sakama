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

/// Extraction runs on its OWN small cap (ADR 0016 decision 6), never against
/// the conversation budget. Charging it to `vita` would mean background work
/// silently eating the turns the user can see and paid attention to — the
/// worst possible way to spend a budget. Small because extraction is batched
/// every N turns, not per message.
const EXTRACT_CAP = 12;

// EXTRACTION RUNS ON A DIFFERENT GATEWAY (docs/research/model-bakeoff-2026-08.md).
// ModelBeat is OpenAI-compatible, so this is a base-URL + key swap, and the
// spike showed its models are NOT good enough for vision — but extraction is
// text-only, structured, background work where a miss costs nothing. Keeping
// it off OpenRouter leaves that balance serving only PhotoSnap, the one path
// where the model demonstrably matters.
//
// Configurable per feature ON PURPOSE: ModelBeat is a beta endpoint, so an
// outage there must degrade extraction alone, never the whole app. Unset the
// secret and this falls back to OpenRouter with no deploy.
const MODELBEAT_URL = "https://api.beta.modelbeat.ai/v1/chat/completions";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
// deepseek-v3.2, chosen on evidence (2026-08-11, five-turn transcript fixture):
// all of qwen3-32b, glm-4.7-flash and deepseek-v3.2 extracted the same three
// correct facts and all correctly REFUSED to remember "I had dal chawal for
// lunch today" (a diary entry, not a memory) — the hardest instruction in the
// prompt. Two things separated them:
//   - qwen3-32b and glm-4.7-flash wrap output in ```json fences DESPITE
//     response_format: json_object; deepseek does not.
//   - glm-4.7-flash reports confidence 1.0 for everything, which is useless
//     for a ranking that sorts on confidence.
// kimi-k2-thinking returned null content entirely (a reasoning model) and is
// unusable here without extra handling.
const EXTRACT_MODEL = Deno.env.get("MODELBEAT_EXTRACT_MODEL") || "deepseek-v3.2";

/// Distil a transcript into durable facts. Deliberately NOT the coach persona:
/// this call has one job, and mixing it with conversation degrades both on a
/// cheap model (decision 5 is why extraction is a separate pass at all).
const EXTRACT_PROMPT = `You extract durable facts about a user from a nutrition
coaching conversation, for a personal health app.

Return STRICT JSON: {"facts":[{"kind":"...","content":"...","confidence":0.0-1.0}],"summary":"..."}

kind MUST be one of: constraint, goal, routine, preference, observation
- constraint: a hard limit — allergy, intolerance, medical restriction, religious rule
- goal: what they are working towards
- routine: a stable habit — when they eat, how they cook, when they train
- preference: a like or dislike
- observation: anything else worth remembering that is not the above

RULES
- Only facts that stay TRUE BEYOND TODAY. "I had dal for lunch" is a diary
  entry, not a memory. "I eat dal most days" is a routine.
- Each fact must stand alone without the conversation. Write "Allergic to
  peanuts", never "she said she is allergic to it".
- Prefer FEW, high-value facts. Zero is a valid and common answer.
- Never invent. If the user did not say it, it is not a fact.
- confidence: 0.9 stated plainly, 0.6 implied, 0.3 guessed.
- summary: 2-3 sentences capturing what this conversation was about, for
  continuing it later. Plain text.
- Health data: record what the user told you. Never diagnose.`;
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
- No markdown headers or bullet-symbol spam; plain, friendly text.

LOGGING:
- When the user clearly states something they ate or drank, or their weight,
  call the matching tool INSTEAD of describing what you would log.
- Only call a tool when the user is reporting something, not when they are
  asking a question or thinking out loud ("should I have dal?" is a question).
- LISTING FOODS IS NOT AUTOMATICALLY A REPORT. "What do you think of this meal
  - poha, dal, two rotis?" is a QUESTION: answer it with your actual opinion,
  grounded in their plan and targets. Do not reply by asking which meal slot it
  was, and do not reply with only an offer to log — that ignores what they
  asked. Offer logging at most as a short closing sentence, after the answer.
- Estimate portions from standard Indian servings when the user does not give
  grams. Never invent a number you have no basis for: if the food is too vague
  to estimate, ask one short clarifying question instead of calling the tool.
- The user always confirms before anything is saved, so propose freely, but a
  wrong number wastes their time — be honest, not eager.`;

// Tool schemas (OpenAI/OpenRouter shape). The model PROPOSES; the client
// bounds-checks every argument and the USER confirms before anything is
// written (ADR 0016 decision 2) — nothing here writes.
const TOOLS = [
  {
    type: "function",
    function: {
      name: "log_food",
      description: "Propose logging a food the user says they ate.",
      parameters: {
        type: "object",
        properties: {
          meal: {
            type: "string",
            enum: ["breakfast", "lunch", "dinner", "snack"],
          },
          name: { type: "string", description: "the dish, e.g. dal tadka" },
          energy_kcal: { type: "number" },
          protein_g: { type: "number" },
          carb_g: { type: "number" },
          fat_g: { type: "number" },
          grams: { type: "number", description: "portion weight if known" },
        },
        required: ["meal", "name", "energy_kcal"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "log_water",
      description: "Propose logging water the user says they drank.",
      parameters: {
        type: "object",
        properties: { amount_ml: { type: "number" } },
        required: ["amount_ml"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "log_weight",
      description: "Propose logging the user's stated body weight.",
      parameters: {
        type: "object",
        properties: { weight_kg: { type: "number" } },
        required: ["weight_kg"],
      },
    },
  },
];

function safeParse(v: unknown): Record<string, unknown> {
  if (typeof v !== "string") return {};
  try {
    const p = JSON.parse(v);
    return p && typeof p === "object" ? p as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

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
  // Extraction (ADR 0016 phase 4) is a separate MODE of this function rather
  // than a new function: same auth, same key handling, same refund path, one
  // fewer deployment to keep in step.
  const extractMode = body?.mode === "extract";
  const turns = Array.isArray(body?.messages)
    ? body.messages
    : (extractMode && Array.isArray(body?.turns) ? body.turns : null);
  const context = typeof body?.context === "string" ? body.context : "";
  const priorSummary = typeof body?.prior_summary === "string"
    ? body.prior_summary.slice(0, 1000)
    : "";
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
  // A conversation turn must END with the user; an extraction pass is over a
  // finished slice of transcript and has no such requirement.
  if (clean.length === 0 ||
      (!extractMode && clean[clean.length - 1].role !== "user")) {
    return new Response(JSON.stringify({ error: "bad_request" }), { status: 400 });
  }

  // Budget (atomic, charge-on-attempt, before the provider call).
  if (!byok) {
    const { data: newCount, error: usageErr } = await supabase
      .rpc("increment_ai_usage", {
        p_feature: extractMode ? "memory" : "vita",
        p_cap: extractMode ? EXTRACT_CAP : DAILY_CAP,
      });
    if (usageErr) {
      return new Response(JSON.stringify({ error: "usage_error" }), { status: 500 });
    }
    if (newCount === null || newCount === undefined) {
      return new Response(JSON.stringify({ error: "budget_exhausted" }), { status: 429 });
    }
  }

  const system = extractMode
    ? (priorSummary
        ? `${EXTRACT_PROMPT}\n\n--- Summary so far ---\n${priorSummary}`
        : EXTRACT_PROMPT)
    : context
    ? `${PERSONA}\n\n--- The user's data right now ---\n${context.slice(0, 4000)}`
    : PERSONA;

  // BYOK is always the user's own OpenRouter key, so it pins the OpenRouter
  // path regardless of mode — we must never spend a user's key on a gateway
  // they did not choose.
  const mbKey = Deno.env.get("MODELBEAT_API_KEY");
  const useModelBeat = extractMode && !byok && !!mbKey;
  const endpoint = useModelBeat ? MODELBEAT_URL : OPENROUTER_URL;
  const upstreamKey = byok ||
    (useModelBeat ? mbKey : Deno.env.get("OPENROUTER_API_KEY"));
  const upstreamModel = useModelBeat ? EXTRACT_MODEL : MODEL;

  const orRes = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${upstreamKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: upstreamModel,
      messages: [{ role: "system", content: system }, ...clean],
      // Extraction must NOT be given tools: its job is to distil, and a
      // background pass that could propose a write would be a way to log food
      // without the user ever seeing a confirm card (ADR 0016 decision 2).
      ...(extractMode
        ? { response_format: { type: "json_object" } }
        : { tools: TOOLS }),
      max_tokens: extractMode ? 700 : 500,
    }),
  });
  // Refund a rejected request (see the 0009 migration): no tokens billed, so
  // no exchange spent. A 2xx we cannot parse WAS billed and is not refunded.
  if (!orRes.ok) {
    const detail = await orRes.text().catch(() => "");
    console.error(`openrouter ${orRes.status} feature=vita :: ${detail.slice(0, 500)}`);
    if (!byok) {
      await supabase.rpc("refund_ai_usage",
        { p_feature: extractMode ? "memory" : "vita" });
    }
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }
  const or = await orRes.json();

  // FAIL CLOSED ON A SILENT MODEL SWAP. ModelBeat returns HTTP 200 served by a
  // DIFFERENT model when a pin is unrecognised or retired — no error, no
  // warning field (their API.md §4.3; reproduced 2026-08-11: asking for
  // "google/gemini-2.5-flash" was served by ministral-3-8b). Without this
  // check, a retired pin would silently change what distils a user's health
  // data, and the first symptom would be worse memories months later.
  //
  // A 502 here costs one skipped extraction, which is invisible by design.
  if (useModelBeat) {
    const served = or?.extra_fields?.resolved_model_used;
    if (typeof served === "string" && !served.includes(EXTRACT_MODEL)) {
      console.error(
        `modelbeat SILENT FALLBACK: pinned ${EXTRACT_MODEL}, served ${served}`,
      );
      await supabase.rpc("refund_ai_usage", { p_feature: "memory" });
      return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
    }
  }

  const msg = or?.choices?.[0]?.message;
  const reply = typeof msg?.content === "string" ? msg.content : "";

  // Extraction returns the model's JSON straight through; the CLIENT validates
  // every field hard (a junk memory is worse than a missing one, because the
  // user can see it, cannot edit it, and it steers later replies).
  if (extractMode) {
    if (reply.trim().length === 0) {
      return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
    }
    return new Response(reply, {
      headers: { "Content-Type": "application/json" },
    });
  }

  // A tool call is a PROPOSAL passed straight through: the client bounds-checks
  // every argument (ToolCallParser) and the user confirms before any write.
  const call = Array.isArray(msg?.tool_calls) ? msg.tool_calls[0] : null;
  const name = call?.function?.name;
  const toolJson = typeof name === "string"
    ? JSON.stringify({ tool: name, arguments: safeParse(call?.function?.arguments) })
    : null;

  // Empty text is legitimate WHEN the model chose to act instead of talk.
  if (reply.trim().length === 0 && toolJson === null) {
    return new Response(JSON.stringify({ error: "provider_error" }), { status: 502 });
  }
  return new Response(JSON.stringify({ reply, tool_json: toolJson }), {
    headers: { "Content-Type": "application/json" },
  });
});
