import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  BodyReadTimeoutMs,
  Deadline,
  fetchUpstream,
  PlatformWallClockMs,
  readTextWithin,
  UpstreamTimeout,
  UpstreamTimeoutError,
} from "./upstream.ts";

// The point of the deadline is that a hung provider becomes an ordinary error
// the caller can refund, instead of a kill that takes the refund with it.

Deno.test("a responsive provider passes straight through", async () => {
  const res = await fetchUpstream(
    "https://example.test",
    { method: "POST" },
    1000,
    () => Promise.resolve(new Response("ok", { status: 200 })),
  );
  assertEquals(res.status, 200);
  assertEquals(await res.text(), "ok");
});

Deno.test("a provider that goes quiet raises a timeout, not a hang", async () => {
  const err = await assertRejects(
    () =>
      fetchUpstream(
        "https://example.test",
        {},
        20,
        // Never resolves on its own — exactly the failure being bounded.
        (_url, init) =>
          new Promise((_resolve, reject) => {
            (init?.signal as AbortSignal).addEventListener(
              "abort",
              () => reject(new DOMException("Aborted", "AbortError")),
            );
          }),
      ),
    UpstreamTimeoutError,
  );
  assertEquals((err as UpstreamTimeoutError).ms, 20);
});

Deno.test("the signal is passed to fetch, or nothing can abort", async () => {
  let seen: AbortSignal | undefined;
  await fetchUpstream("https://example.test", { method: "POST" }, 1000, (
    _url,
    init,
  ) => {
    seen = init?.signal as AbortSignal;
    return Promise.resolve(new Response("ok"));
  });
  assert(seen instanceof AbortSignal);
  assertEquals(seen!.aborted, false);
});

Deno.test("caller's init survives — a dropped body would be worse than a hang",
  async () => {
    let seenMethod: string | undefined;
    let seenBody: BodyInit | null | undefined;
    await fetchUpstream(
      "https://example.test",
      { method: "POST", body: '{"model":"x"}' },
      1000,
      (_url, init) => {
        seenMethod = init?.method;
        seenBody = init?.body;
        return Promise.resolve(new Response("ok"));
      },
    );
    assertEquals(seenMethod, "POST");
    assertEquals(seenBody, '{"model":"x"}');
  });

Deno.test("a non-timeout error propagates unchanged", async () => {
  await assertRejects(
    () =>
      fetchUpstream(
        "https://example.test",
        {},
        1000,
        () => Promise.reject(new TypeError("dns failure")),
      ),
    TypeError,
    "dns failure",
  );
});

Deno.test("a single call's deadline is inside the platform's wall clock", () => {
  for (const ms of [UpstreamTimeout.chat, UpstreamTimeout.vision, UpstreamTimeout.plan]) {
    assert(ms > 0);
    assert(ms < PlatformWallClockMs);
  }
  // Vision and plan generation legitimately take longer than a chat turn.
  assert(UpstreamTimeout.vision > UpstreamTimeout.chat);
});

// THE GUARD THE FIRST VERSION WAS MISSING. It asserted that each constant was
// small enough, which says nothing about a chain that walks several of them in
// sequence — and photosnap does. Three 75s attempts sum to 225s against a 150s
// platform cap: the function is killed mid-flight and the refund it exists to
// protect never runs.
Deno.test("a whole CHAIN cannot outlive the platform, however many links", () => {
  // The budget bounds the sum regardless of chain length, which is the point:
  // this holds for two candidates and for ten.
  assert(
    UpstreamTimeout.chain + UpstreamTimeout.minAttempt < PlatformWallClockMs,
    "a chain that overruns is killed before it can refund",
  );
  // And with room to spare for the auth + increment round trips already spent
  // before the first call, plus the response itself.
  assert(PlatformWallClockMs - UpstreamTimeout.chain >= 30_000);
});

Deno.test("a chain of three vision attempts fits inside the budget", () => {
  let now = 1_000_000;
  const clock = () => now;
  const deadline = Deadline.inMs(UpstreamTimeout.chain, clock);

  let started = 0;
  for (let link = 0; link < 3; link++) {
    if (!deadline.hasRoomFor(UpstreamTimeout.minAttempt, clock)) break;
    const slice = deadline.sliceFor(UpstreamTimeout.vision, clock);
    assert(slice > 0);
    started++;
    now += slice; // this link used every millisecond it was given
  }
  assertEquals(started, 2, "the third has no room and is not begun");
  assert(now - 1_000_000 <= UpstreamTimeout.chain);
});

Deno.test("the last slice shrinks rather than overrunning the budget", () => {
  let now = 0;
  const clock = () => now;
  const deadline = Deadline.inMs(100_000, clock);
  now += 60_000;
  assertEquals(deadline.sliceFor(UpstreamTimeout.vision, clock), 40_000);
  now += 40_000;
  assertEquals(deadline.remainingMs(clock), 0);
  assertEquals(deadline.hasRoomFor(1, clock), false);
});

Deno.test("a stalled error body degrades to no detail, and does not block",
  async () => {
    // This read sits between detecting a provider failure and refunding the
    // user. A stall here would hang exactly where the compensation happens.
    const stalled = new Response(
      new ReadableStream({ start() {/* never enqueues, never closes */} }),
    );
    const detail = await readTextWithin(stalled, 20);
    assertEquals(detail, "", "no detail is fine; a hang is not");
  });

Deno.test("a readable error body is returned intact", async () => {
  const detail = await readTextWithin(
    new Response("insufficient credits"),
    BodyReadTimeoutMs,
  );
  assertEquals(detail, "insufficient credits");
});

Deno.test("a caller's own signal is refused, not silently discarded", () => {
  // Ours replaces it, so accepting one would hand the next caller a
  // cancellation that never fires.
  const theirs = new AbortController();
  let called = false;
  const call = () =>
    fetchUpstream("https://example.test", { signal: theirs.signal }, 1000, () => {
      called = true;
      return Promise.resolve(new Response("ok"));
    });
  assertRejects(call, Error, "owns the signal");
  assertEquals(called, false);
});
