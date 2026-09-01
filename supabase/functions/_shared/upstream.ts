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

  /// The budget for a WHOLE request that may try several providers.
  ///
  /// Bounding each call is not enough, and believing otherwise was the bug in
  /// the first version of this file: photosnap walks a chain of up to three
  /// candidates SEQUENTIALLY, so three 75s deadlines sum to 225s against a
  /// platform wall clock of 150s. The platform would kill the function first —
  /// taking the refund with it, which is the precise failure this module was
  /// written to remove, on the function that benefits most from it.
  ///
  /// So a chain gets a total, and each attempt is sliced out of what is left.
  /// The margin below 150s covers what the function already spent before the
  /// first call: auth.getUser() and the increment RPC are both round trips.
  chain: 110_000,

  /// Below this there is no point starting another attempt — it cannot finish,
  /// and the time is better spent returning an honest error while the refund
  /// path is still reachable.
  minAttempt: 12_000,
} as const;

/// The platform's own limit, which is the thing our budgets must stay under.
///
/// Supabase edge functions: 150s wall clock, and a 150s request idle timeout
/// that returns 504. Ours has to fire first, because ours runs the refund and
/// cleanup and theirs does not.
export const PlatformWallClockMs = 150_000;

/// A time budget for a whole request.
///
/// Handed down a retry chain so that N attempts cannot outlive the platform.
export class Deadline {
  private constructor(private readonly endsAt: number) {}

  static inMs(ms: number, now: () => number = Date.now): Deadline {
    return new Deadline(now() + ms);
  }

  remainingMs(now: () => number = Date.now): number {
    return Math.max(0, this.endsAt - now());
  }

  /// Is there enough left for another attempt to be worth starting?
  hasRoomFor(minMs: number, now: () => number = Date.now): boolean {
    return this.remainingMs(now) >= minMs;
  }

  /// The deadline for one call inside this budget: the shorter of what that
  /// kind of call is allowed and what the request has left.
  sliceFor(perCallMs: number, now: () => number = Date.now): number {
    return Math.min(perCallMs, this.remainingMs(now));
  }
}

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

export async function fetchUpstream(
  url: string,
  init: RequestInit,
  timeoutMs: number,
  // Injected for tests. Production passes nothing and gets the real fetch.
  fetchImpl: typeof fetch = fetch,
): Promise<Response> {
  // A caller's own signal would be silently replaced by ours below. No call
  // site passes one today, so refuse rather than quietly ignore it — the next
  // caller should find out here and not from a cancellation that never works.
  if (init.signal) {
    throw new Error("fetchUpstream owns the signal; pass a shorter deadline");
  }
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

/// Read a response body with a deadline.
///
/// `fetch` resolves when the HEADERS arrive, so the deadline above does not
/// cover the body at all — and one of those reads sits in the worst possible
/// place: the error path reads the provider's message BEFORE running the
/// refund. A provider that returns 500 headers and then stalls the body would
/// hang between detecting the failure and compensating the user, which is the
/// same lost-refund shape one layer down. `.catch()` does not help: a stall is
/// not a rejection.
export async function readTextWithin(
  res: Response,
  timeoutMs: number,
): Promise<string> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      res.text(),
      new Promise<string>((_resolve, reject) => {
        timer = setTimeout(
          () => reject(new UpstreamTimeoutError(timeoutMs)),
          timeoutMs,
        );
      }),
    ]);
  } catch (_) {
    // The body is diagnostic only. Losing it must never cost the refund that
    // comes after, so a stalled or broken read degrades to "no detail".
    return "";
  } finally {
    clearTimeout(timer);
  }
}

/// How long a diagnostic body read may take. Short on purpose: nothing after
/// it depends on the text, and everything after it matters more.
export const BodyReadTimeoutMs = 5_000;
