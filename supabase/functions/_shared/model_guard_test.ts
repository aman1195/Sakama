import { assert, assertFalse } from "jsr:@std/assert@1";
import { servedModelVerified } from "./model_guard.ts";

// The real shapes ModelBeat returned on 2026-08-11.
Deno.test("a matching pin verifies, including provider suffixes", () => {
  assert(servedModelVerified("deepseek.v3.2", "deepseek-v3.2"));
  assert(servedModelVerified("qwen.qwen3-32b-v1:0", "qwen3-32b"));
  assert(servedModelVerified("zai.glm-4.7-flash", "glm-4.7-flash"));
  assert(servedModelVerified("qwen.qwen3-vl-235b-a22b", "qwen3-vl-235b"));
});

Deno.test("the observed silent swap is caught", () => {
  // Asking for gemini was served by ministral, HTTP 200, no error field.
  assertFalse(
    servedModelVerified("mistral.ministral-3-8b-instruct", "google/gemini-2.5-flash"),
  );
  assertFalse(servedModelVerified("mistral.ministral-3-8b-instruct", "deepseek-v3.2"));
});

Deno.test("ABSENT or unusable counts as unverified, not as pass", () => {
  // The bug this test exists for: a guard that only fired on a present string
  // failed OPEN when the field was missing, so a future gateway change would
  // silently reopen the swap.
  assertFalse(servedModelVerified(undefined, "deepseek-v3.2"));
  assertFalse(servedModelVerified(null, "deepseek-v3.2"));
  assertFalse(servedModelVerified("", "deepseek-v3.2"));
  assertFalse(servedModelVerified(42, "deepseek-v3.2"));
  assertFalse(servedModelVerified({}, "deepseek-v3.2"));
});

Deno.test("an empty pin cannot be satisfied by anything", () => {
  // Otherwise a misconfigured MODELBEAT_EXTRACT_MODEL="" would make every
  // response verify, since every string contains the empty string.
  assertFalse(servedModelVerified("deepseek.v3.2", ""));
});
