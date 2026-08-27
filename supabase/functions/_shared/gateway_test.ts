import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { isFreeTierAllowed, resolveVisionChain } from "./gateway.ts";

/// The free-tier allowlist is a data-protection boundary, not a convenience.
///
/// Google's unpaid terms state that human reviewers read API input and output
/// and that content trains their models, and instruct: "Do not submit
/// sensitive, confidential, or personal information to the Unpaid Services."
/// A meal photo attached to a health profile is exactly that. So the tests
/// that matter here are the ones that prove the boundary FAILS CLOSED.

function withEnv(vars: Record<string, string | null>, fn: () => void) {
  const saved: Record<string, string | undefined> = {};
  for (const k of Object.keys(vars)) saved[k] = Deno.env.get(k);
  try {
    for (const [k, v] of Object.entries(vars)) {
      if (v === null) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
    fn();
  } finally {
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  }
}

const CLEAN = {
  GEMINI_FREE_KEY_DEV_ONLY: null,
  GEMINI_FREE_USER_IDS: null,
  MODELBEAT_API_KEY: null,
  MODELBEAT_ALL: null,
  OPENROUTER_API_KEY: null,
};

Deno.test("allowlist: an unset list means NOBODY, not everybody", () => {
  withEnv({ ...CLEAN }, () => {
    assertFalse(isFreeTierAllowed("dev-user"));
  });
  withEnv({ ...CLEAN, GEMINI_FREE_USER_IDS: "" }, () => {
    assertFalse(isFreeTierAllowed("dev-user"));
  });
  withEnv({ ...CLEAN, GEMINI_FREE_USER_IDS: "   " }, () => {
    assertFalse(isFreeTierAllowed("dev-user"));
  });
});

Deno.test("allowlist: an empty user id is never allowed", () => {
  withEnv({ ...CLEAN, GEMINI_FREE_USER_IDS: "dev-user," }, () => {
    // A trailing comma produces an empty entry. It must not become a wildcard
    // that matches an unauthenticated or malformed caller.
    assertFalse(isFreeTierAllowed(""));
    assert(isFreeTierAllowed("dev-user"));
  });
});

Deno.test("allowlist: matching is exact, not prefix or substring", () => {
  withEnv({ ...CLEAN, GEMINI_FREE_USER_IDS: "abc-123" }, () => {
    assert(isFreeTierAllowed("abc-123"));
    assertFalse(isFreeTierAllowed("abc-1234"));
    assertFalse(isFreeTierAllowed("abc-12"));
    assertFalse(isFreeTierAllowed("xabc-123"));
    assertFalse(isFreeTierAllowed("ABC-123"));
  });
});

Deno.test("allowlist: whitespace around entries is tolerated", () => {
  withEnv({ ...CLEAN, GEMINI_FREE_USER_IDS: " a , b ,c " }, () => {
    for (const id of ["a", "b", "c"]) assert(isFreeTierAllowed(id));
    assertFalse(isFreeTierAllowed("d"));
  });
});

Deno.test("vision chain: a stranger NEVER reaches the free tier", () => {
  withEnv({
    ...CLEAN,
    GEMINI_FREE_KEY_DEV_ONLY: "free-key",
    GEMINI_FREE_USER_IDS: "dev-user",
    MODELBEAT_API_KEY: "mb",
    MODELBEAT_ALL: "1",
    OPENROUTER_API_KEY: "or",
  }, () => {
    const stranger = resolveVisionChain({ byok: "", userId: "someone-else" });
    assertFalse(
      stranger.some((u) => u.isFreeTier === true),
      "another user's health photo must never reach a tier whose terms " +
        "permit human review",
    );
    assertEquals(stranger.map((u) => u.label), ["modelbeat", "openrouter"]);

    // ...while the named developer does get it, first.
    const dev = resolveVisionChain({ byok: "", userId: "dev-user" });
    assertEquals(dev.map((u) => u.label), [
      "gemini-free(dev)",
      "modelbeat",
      "openrouter",
    ]);
  });
});

Deno.test("vision chain: a key with no allowlist is inert", () => {
  withEnv({
    ...CLEAN,
    GEMINI_FREE_KEY_DEV_ONLY: "free-key",
    OPENROUTER_API_KEY: "or",
  }, () => {
    // Setting the key alone must not enable it. Two deliberate acts required.
    const chain = resolveVisionChain({ byok: "", userId: "dev-user" });
    assertEquals(chain.map((u) => u.label), ["openrouter"]);
  });
});

Deno.test("vision chain: BYOK is never chained past", () => {
  withEnv({
    ...CLEAN,
    GEMINI_FREE_KEY_DEV_ONLY: "free-key",
    GEMINI_FREE_USER_IDS: "dev-user",
    MODELBEAT_API_KEY: "mb",
    MODELBEAT_ALL: "1",
    OPENROUTER_API_KEY: "or",
  }, () => {
    // A user's own key is theirs alone: on failure we must not silently spend
    // our gateways, and above all must not send their photo to a free tier.
    const chain = resolveVisionChain({ byok: "sk-user", userId: "dev-user" });
    assertEquals(chain.length, 1);
    assertEquals(chain[0].key, "sk-user");
    assertFalse(chain[0].isFreeTier === true);
  });
});

Deno.test("vision chain: ModelBeat only when explicitly switched on", () => {
  withEnv({
    ...CLEAN,
    MODELBEAT_API_KEY: "mb",
    OPENROUTER_API_KEY: "or",
  }, () => {
    // MODELBEAT_ALL unset: the key alone does not route vision there, because
    // it measured roughly double gemini's calorie error.
    assertEquals(
      resolveVisionChain({ byok: "", userId: "u" }).map((u) => u.label),
      ["openrouter"],
    );
  });
});

Deno.test("vision chain: no upstream configured yields an empty chain", () => {
  withEnv({ ...CLEAN }, () => {
    // The caller must handle this rather than fetch a URL with an empty key.
    assertEquals(resolveVisionChain({ byok: "", userId: "u" }).length, 0);
  });
});

Deno.test("vision chain: never emits an upstream with an empty key", () => {
  withEnv({
    ...CLEAN,
    GEMINI_FREE_KEY_DEV_ONLY: "",
    GEMINI_FREE_USER_IDS: "dev-user",
    MODELBEAT_API_KEY: "",
    MODELBEAT_ALL: "1",
    OPENROUTER_API_KEY: "or",
  }, () => {
    const chain = resolveVisionChain({ byok: "", userId: "dev-user" });
    for (const u of chain) assert(u.key.length > 0, `${u.label} has no key`);
    assertEquals(chain.map((u) => u.label), ["openrouter"]);
  });
});
