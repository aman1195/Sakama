// Verify that a gateway served the request the way we asked.
//
// REWRITTEN 2026-08-27 for ModelBeat's current API, which changed materially
// from the beta this originally targeted:
//
//  - Named models are REJECTED: asking for "deepseek-v3.2" now returns
//    `model '...' is not available during beta. Use 'auto' or a tier name`.
//    You request a TIER (modelbeat-fast/standard/advanced) or "auto".
//  - `resolved_model_used` is gone. Their routing docs say plainly that "the
//    identity of the model that served a request is not part of the published
//    API" — responses carry the serving tier instead.
//
// So the old pin-vs-served substring check cannot work, and would have failed
// CLOSED on every single call: `resolved_model_used` is absent, absent counts
// as unverified, every extraction 502s.
//
// What replaced it is better. `routing_info.is_fallback` is an EXPLICIT signal
// that the gateway did not serve what was asked — the exact condition the old
// guard tried to infer from a substring. We check it directly.

/// The routing block ModelBeat returns, as much of it as we rely on.
export interface RoutingInfo {
  level?: unknown;
  is_fallback?: unknown;
}

/// True when the gateway did not substitute for what was asked.
///
/// RELAXED 2026-08-27, after measuring. The first version also required the
/// returned `level` to match the requested tier — and that is wrong: asking
/// for "modelbeat-fast" returns `level: "standard"` with `is_fallback: false`,
/// because a tier is a HINT to a router whose stated job is picking "the
/// cheapest model that can actually serve the request". Enforcing the tier
/// rejected perfectly good responses and 502'd every call.
///
/// So the only substitution signal that means anything is the one the gateway
/// raises itself. STILL FAILS CLOSED on absent or unrecognised routing: a
/// health-data path should refuse what it cannot confirm, and "no routing
/// block" is not confirmation.
export function servedAsRequested(
  routing: unknown,
  requestedTier: string,
): boolean {
  if (requestedTier.length === 0) return false;
  if (routing === null || typeof routing !== "object") return false;
  const r = routing as RoutingInfo;

  // An explicit fallback means it could not serve the request as framed.
  if (r.is_fallback === true) return false;

  // A level must be present and non-empty — its VALUE is the router's choice,
  // but its absence means we cannot tell what happened.
  return typeof r.level === "string" && r.level.length > 0;
}
