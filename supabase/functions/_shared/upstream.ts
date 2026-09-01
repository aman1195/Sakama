// One timed fetch for every provider call.
//
// WHY THIS EXISTS: none of the four functions bounded their upstream request.
// Deno's fetch has no default timeout, so a provider that accepts a connection
// and then stops talking hangs the call until the platform kills the whole
// function — and the kill takes the refund with it.
//
// That is worse than an error, because #104 already established the rule that
// a failed AI call must not burn the user's budget. An HTTP 5xx refunds
// correctly at every call site. A HANG does not: `refund_ai_usage` sits after
// the await that never returns, so the user loses a photo estimate or a chat
// turn from their daily allowance and gets nothing for it. They cannot see
// why, and they cannot get it back.
//
// A bounded request turns that silent theft into an ordinary provider error,
// which every call site already knows how to refund and report honestly.

/// How long we will wait for a provider, by the kind of work asked of it.
///
/// Generous rather than tight: these are real model calls, and a timeout that
/// fires on a merely slow answer would fail requests that were about to
/// succeed — burning the budget it exists to protect. Vision and plan
/// generation get longer because they legitimately take longer.
///
/// All are comfortably inside Supabase's function wall clock, which is the
/// point: we want OUR deadline to fire, not theirs, because ours runs the
/// refund and theirs does not.
export const UpstreamTimeout = {
  chat: 45_000,
  vision: 75_000,
  plan: 75_000,
} as const;

export class UpstreamTimeoutError extends Error {
  constructor(readonly ms: number) {
    super(`upstream did not respond within ${ms}ms`);
    this.name = "UpstreamTimeoutError";
  }
}

/// `fetch` with a deadline.
///
/// Throws [UpstreamTimeoutError] when the deadline passes, so a caller can
/// tell "the provider refused" from "the provider went quiet" and refund
/// either way. Any other error propagates unchanged.
///
/// The timer is always cleared, including on the error path: a leaked timer in
/// an edge function keeps the isolate alive after the response is sent.
export async function fetchUpstream(
  url: string,
  init: RequestInit,
  timeoutMs: number,
  // Injected for tests. Production passes nothing and gets the real fetch.
  fetchImpl: typeof fetch = fetch,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetchImpl(url, { ...init, signal: controller.signal });
  } catch (e) {
    // An abort surfaces as a DOMException/AbortError rather than anything
    // that names the deadline. Translate it once, here, so no call site has
    // to know what an aborted fetch looks like.
    if (controller.signal.aborted) throw new UpstreamTimeoutError(timeoutMs);
    throw e;
  } finally {
    clearTimeout(timer);
  }
}
