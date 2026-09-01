import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  fetchUpstream,
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

Deno.test("deadlines are inside Supabase's wall clock, so OURS fires first",
  () => {
    // If the platform's limit fired first the function would be killed and the
    // refund would never run — the exact loss this exists to prevent.
    for (const ms of Object.values(UpstreamTimeout)) {
      assert(ms > 0);
      assert(ms <= 90_000, "a deadline longer than this races the platform");
    }
    // Vision and plan generation legitimately take longer than a chat turn.
    assert(UpstreamTimeout.vision > UpstreamTimeout.chat);
  });
