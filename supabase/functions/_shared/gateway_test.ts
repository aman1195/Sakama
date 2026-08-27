import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  isFreeTierAllowed,
  resolveVisionChain,
  type VisionConfig,
} from "./gateway.ts";

/// The free-tier allowlist is a data-protection boundary, not a convenience.
///
/// Google's unpaid terms state that human reviewers read API input and output
/// and that content trains their models, and instruct: "Do not submit
/// sensitive, confidential, or personal information to the Unpaid Services."
/// A meal photo attached to a health profile is exactly that. So the tests
/// that matter here are the ones proving the boundary FAILS CLOSED.
///
/// NOTHING HERE TOUCHES Deno.env. The first version of this file did, which
/// meant it needed --allow-env, which CI does not pass — so every one of these
/// tests silently failed in CI while passing locally, and the most
/// security-critical file in the change was protected by nothing. Routing
/// config is a parameter now, so these run under default permissions.

const NONE: VisionConfig = {
  geminiFreeKey: "",
  freeUserIds: "",
  modelbeatKey: "",
  modelbeatAll: false,
  modelbeatTier: "modelbeat-advanced",
  modelbeatUrl: "https://modelbeat.example/v1/chat/completions",
  openRouterKey: "",
};

const cfg = (over: Partial<VisionConfig> = {}): VisionConfig => ({
  ...NONE,
  ...over,
});

const ALL = cfg({
  geminiFreeKey: "free-key",
  freeUserIds: "dev-user",
  modelbeatKey: "mb",
  modelbeatAll: true,
  openRouterKey: "or",
});

Deno.test("allowlist: an empty list means NOBODY, not everybody", () => {
  for (const list of ["", "   ", ",", " , , "]) {
    assertFalse(
      isFreeTierAllowed("dev-user", list),
      `list ${JSON.stringify(list)} must grant nobody`,
    );
  }
});

Deno.test("allowlist: an empty user id is never allowed", () => {
  // A trailing comma produces an empty entry. It must not become a wildcard
  // matching an unauthenticated or malformed caller.
  assertFalse(isFreeTierAllowed("", "dev-user,"));
  assert(isFreeTierAllowed("dev-user", "dev-user,"));
});

Deno.test("allowlist: matching is exact, not prefix or substring", () => {
  const list = "abc-123";
  assert(isFreeTierAllowed("abc-123", list));
  for (const near of ["abc-1234", "abc-12", "xabc-123", "ABC-123", "abc123"]) {
    assertFalse(isFreeTierAllowed(near, list), `${near} must not match`);
  }
});

Deno.test("allowlist: whitespace around entries is tolerated", () => {
  const list = " a , b ,c ";
  for (const id of ["a", "b", "c"]) assert(isFreeTierAllowed(id, list));
  assertFalse(isFreeTierAllowed("d", list));
});

Deno.test("vision chain: a stranger NEVER reaches the free tier", () => {
  const stranger = resolveVisionChain({
    byok: "",
    userId: "someone-else",
    config: ALL,
  });
  assertFalse(
    stranger.some((u) => u.isFreeTier === true),
    "another user's health photo must never reach a tier whose terms permit " +
      "human review",
  );
  assertEquals(stranger.map((u) => u.label), ["modelbeat", "openrouter"]);

  // ...while the named developer does get it, first.
  assertEquals(
    resolveVisionChain({ byok: "", userId: "dev-user", config: ALL })
      .map((u) => u.label),
    ["gemini-free(dev)", "modelbeat", "openrouter"],
  );
});

Deno.test("vision chain: a key with no allowlist is inert", () => {
  // Setting the key alone must not enable it. Two deliberate acts required.
  assertEquals(
    resolveVisionChain({
      byok: "",
      userId: "dev-user",
      config: cfg({ geminiFreeKey: "free-key", openRouterKey: "or" }),
    }).map((u) => u.label),
    ["openrouter"],
  );
});

Deno.test("vision chain: an allowlist with no key is inert", () => {
  assertEquals(
    resolveVisionChain({
      byok: "",
      userId: "dev-user",
      config: cfg({ freeUserIds: "dev-user", openRouterKey: "or" }),
    }).map((u) => u.label),
    ["openrouter"],
  );
});

Deno.test("vision chain: BYOK is never chained past", () => {
  // A user's own key is theirs alone: on failure we must not silently spend
  // our gateways, and above all must not send their photo to a free tier.
  const chain = resolveVisionChain({
    byok: "sk-user",
    userId: "dev-user",
    config: ALL,
  });
  assertEquals(chain.length, 1);
  assertEquals(chain[0].key, "sk-user");
  assertFalse(chain[0].isFreeTier === true);
});

Deno.test("vision chain: ModelBeat only when explicitly switched on", () => {
  // The key alone does not route vision there, because it measured roughly
  // double gemini's calorie error on the bake-off photos.
  assertEquals(
    resolveVisionChain({
      byok: "",
      userId: "u",
      config: cfg({ modelbeatKey: "mb", openRouterKey: "or" }),
    }).map((u) => u.label),
    ["openrouter"],
  );
});

Deno.test("vision chain: a paid upstream is always the tail", () => {
  // Whatever precedes it, the chain must end somewhere with defensible data
  // terms rather than degrade INTO the free tier.
  const chain = resolveVisionChain({
    byok: "",
    userId: "dev-user",
    config: ALL,
  });
  assertFalse(chain[chain.length - 1].isFreeTier === true);
  assertEquals(chain[chain.length - 1].label, "openrouter");
});

Deno.test("vision chain: no upstream configured yields an empty chain", () => {
  // The caller must handle this rather than fetch a URL with an empty key.
  assertEquals(
    resolveVisionChain({ byok: "", userId: "u", config: NONE }).length,
    0,
  );
});

Deno.test("vision chain: never emits an upstream with an empty key", () => {
  const chain = resolveVisionChain({
    byok: "",
    userId: "dev-user",
    config: cfg({
      geminiFreeKey: "",
      freeUserIds: "dev-user",
      modelbeatKey: "",
      modelbeatAll: true,
      openRouterKey: "or",
    }),
  });
  for (const u of chain) assert(u.key.length > 0, `${u.label} has no key`);
  assertEquals(chain.map((u) => u.label), ["openrouter"]);
});
