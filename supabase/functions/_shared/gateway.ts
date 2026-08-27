// Which AI gateway a feature talks to, and how.
//
// WHY THIS EXISTS. During development OpenRouter has no balance, so every AI
// path — vision included — routes to ModelBeat instead. That decision was
// about to be copy-pasted into four Edge Functions, which is how four
// functions end up disagreeing about a fallback rule six weeks later.
//
// PRODUCTION INTENT IS UNCHANGED and this must not quietly become permanent:
// the bake-off (docs/research/model-bakeoff-2026-08.md §1) measured ModelBeat's
// vision at roughly double gemini-2.5-flash's calorie error on 22 Indian meal
// photos. PhotoSnap should go back to Gemini before real users see it. Unset
// MODELBEAT_ALL and every feature returns to OpenRouter with no code change.

export interface Upstream {
  url: string;
  key: string;
  model: string;
  /// True when ModelBeat served it, so callers know to check routing_info.
  isModelBeat: boolean;
}

const MODELBEAT_URL = () =>
  Deno.env.get("MODELBEAT_URL") ||
  "https://api.staging.modelbeat.ai/v1/chat/completions";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

/// Resolve the upstream for one call.
///
/// [byok] always pins OpenRouter, whatever else is configured: a user's own
/// key must never be spent on a gateway they did not choose.
///
/// [tier] is a ModelBeat tier ("auto", "modelbeat-fast|standard|advanced") —
/// named models are rejected by the current API, and the identity of the
/// serving model is deliberately not published.
export function resolveUpstream({
  byok,
  tier,
  openRouterModel,
  force,
}: {
  byok: string;
  tier: string;
  openRouterModel: string;
  /// Set for features that route to ModelBeat regardless of MODELBEAT_ALL
  /// (today: memory extraction, which has its own recorded decision).
  force?: boolean;
}): Upstream {
  const mbKey = Deno.env.get("MODELBEAT_API_KEY") ?? "";
  const all = Deno.env.get("MODELBEAT_ALL") === "1";
  const useModelBeat = !byok && mbKey.length > 0 && (all || force === true);

  return useModelBeat
    ? { url: MODELBEAT_URL(), key: mbKey, model: tier, isModelBeat: true }
    : {
      url: OPENROUTER_URL,
      key: byok || (Deno.env.get("OPENROUTER_API_KEY") ?? ""),
      model: openRouterModel,
      isModelBeat: false,
    };
}
