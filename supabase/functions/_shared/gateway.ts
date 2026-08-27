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
  /// True for a provider tier whose terms permit training and human review.
  /// Callers must never route another person's health data through one.
  isFreeTier?: boolean;
  /// For logs. Never includes the key.
  label: string;
}

const MODELBEAT_URL = () =>
  Deno.env.get("MODELBEAT_URL") ||
  "https://api.staging.modelbeat.ai/v1/chat/completions";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";
/// Bare name: Google's OpenAI-compatible shim does not take OpenRouter's
/// "google/" prefix.
const GEMINI_MODEL = "gemini-2.5-flash";

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
    ? {
      url: MODELBEAT_URL(),
      key: mbKey,
      model: tier,
      isModelBeat: true,
      label: "modelbeat",
    }
    : {
      url: OPENROUTER_URL,
      key: byok || (Deno.env.get("OPENROUTER_API_KEY") ?? ""),
      model: openRouterModel,
      isModelBeat: false,
      label: byok ? "openrouter(byok)" : "openrouter",
    };
}

/// Ordered upstreams to try for a VISION call, best-accuracy first.
///
/// WHY A CHAIN AND NOT A SINGLE PICK. The bake-off measured gemini-2.5-flash
/// at 9% median calorie error against ModelBeat's best at 18%, on the same 22
/// Indian meal photos. Accuracy on those photos is the product, so the right
/// model should be tried first and a worse one used only when the first is
/// unavailable — a rough number beats no number, but only in that order.
///
/// THE FREE-TIER BOUNDARY. Google's unpaid terms state that human reviewers
/// read API input and output and that content trains their models, and they
/// say in terms: "Do not submit sensitive, confidential, or personal
/// information to the Unpaid Services." A meal photo attached to a health
/// profile is exactly that. So the free key is reachable ONLY for user ids
/// named in GEMINI_FREE_USER_IDS — the developer's own account during
/// development. It is not a default, it is not a fallback, and an unset
/// allowlist means the free tier is never used. Fail closed.
///
/// This is deliberately an allowlist and not a flag. A flag gets forgotten and
/// then quietly serves strangers; an allowlist can only ever serve the people
/// written into it. CLAUDE.md rule 3 (paid tiers only for real user data) is
/// therefore enforced by construction rather than by memory.
/// Everything [resolveVisionChain] needs, as data.
///
/// Taken as a parameter rather than read from Deno.env inside, so the tests
/// that guard this boundary need no ambient process permission. A security
/// check that can only be verified by granting the test suite --allow-env is
/// being verified through a side channel; passing the config makes the
/// function a pure function of its inputs and the assertions exact.
export interface VisionConfig {
  geminiFreeKey: string;
  /// Comma-separated user ids. Empty means NOBODY.
  freeUserIds: string;
  modelbeatKey: string;
  modelbeatAll: boolean;
  modelbeatTier: string;
  modelbeatUrl: string;
  openRouterKey: string;
}

/// The production binding. The only place vision routing touches the process
/// environment.
export function visionConfigFromEnv(): VisionConfig {
  return {
    geminiFreeKey: Deno.env.get("GEMINI_FREE_KEY_DEV_ONLY") ?? "",
    freeUserIds: Deno.env.get("GEMINI_FREE_USER_IDS") ?? "",
    modelbeatKey: Deno.env.get("MODELBEAT_API_KEY") ?? "",
    modelbeatAll: Deno.env.get("MODELBEAT_ALL") === "1",
    modelbeatTier: Deno.env.get("MODELBEAT_TIER_PHOTOSNAP") ||
      "modelbeat-advanced",
    modelbeatUrl: MODELBEAT_URL(),
    openRouterKey: Deno.env.get("OPENROUTER_API_KEY") ?? "",
  };
}

export function resolveVisionChain(
  { byok, userId, config }: {
    byok: string;
    userId: string;
    config: VisionConfig;
  },
): Upstream[] {
  // A user's own key is theirs alone: never chain past it onto our gateways.
  if (byok) {
    return [{
      url: OPENROUTER_URL,
      key: byok,
      model: "google/gemini-2.5-flash",
      isModelBeat: false,
      label: "openrouter(byok)",
    }];
  }

  const chain: Upstream[] = [];

  if (
    config.geminiFreeKey.length > 0 &&
    isFreeTierAllowed(userId, config.freeUserIds)
  ) {
    chain.push({
      url: GEMINI_URL,
      key: config.geminiFreeKey,
      model: GEMINI_MODEL,
      isModelBeat: false,
      isFreeTier: true,
      label: "gemini-free(dev)",
    });
  }

  if (config.modelbeatKey.length > 0 && config.modelbeatAll) {
    chain.push({
      url: config.modelbeatUrl,
      key: config.modelbeatKey,
      model: config.modelbeatTier,
      isModelBeat: true,
      label: "modelbeat",
    });
  }

  if (config.openRouterKey.length > 0) {
    chain.push({
      url: OPENROUTER_URL,
      key: config.openRouterKey,
      model: "google/gemini-2.5-flash",
      isModelBeat: false,
      label: "openrouter",
    });
  }

  return chain;
}

/// Exact match on a comma-separated allowlist. Empty means nobody, never
/// everybody: a misconfigured allowlist must reduce access, not grant it.
export function isFreeTierAllowed(userId: string, allowlist: string): boolean {
  if (userId.length === 0) return false;
  if (allowlist.trim().length === 0) return false;
  return allowlist.split(",").map((s) => s.trim()).filter((s) => s.length > 0)
    .includes(userId);
}
