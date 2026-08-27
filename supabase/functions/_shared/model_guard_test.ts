import { assert, assertFalse } from "jsr:@std/assert@1";
import { servedAsRequested } from "./model_guard.ts";

// Shapes observed against api.staging.modelbeat.ai on 2026-08-27.
Deno.test("a tier served as requested verifies", () => {
  assert(servedAsRequested(
    { level: "standard", is_fallback: false }, "modelbeat-standard"));
  assert(servedAsRequested(
    { level: "fast", is_fallback: false }, "modelbeat-fast"));
});

Deno.test("auto accepts whatever level it picked — that is the contract", () => {
  assert(servedAsRequested({ level: "standard", is_fallback: false }, "auto"));
  assert(servedAsRequested({ level: "advanced", is_fallback: false }, "auto"));
});

Deno.test("an EXPLICIT fallback is rejected, even at the right level", () => {
  // The condition the old pin-vs-served check tried to infer. The gateway now
  // states it outright, so we act on it rather than guessing from a string.
  assertFalse(servedAsRequested(
    { level: "standard", is_fallback: true }, "modelbeat-standard"));
  assertFalse(servedAsRequested({ level: "fast", is_fallback: true }, "auto"));
});

Deno.test("a different level than the tier asked for is FINE", () => {
  // Measured: asking modelbeat-fast returns level "standard", is_fallback
  // false. The tier is a hint to a router whose job is picking the cheapest
  // model that can serve the request — enforcing it 502'd every call.
  assert(servedAsRequested(
    { level: "standard", is_fallback: false }, "modelbeat-fast"));
});

Deno.test("ABSENT or unusable routing counts as unverified", () => {
  // Health data: refuse what cannot be confirmed. The previous guard shipped
  // failing OPEN on a missing field; this one does not.
  for (const bad of [undefined, null, "standard", 42, {}, { level: "" },
                     { level: 7 }, { is_fallback: false }]) {
    assertFalse(servedAsRequested(bad, "modelbeat-standard"));
  }
});

Deno.test("an empty requested tier cannot be satisfied", () => {
  // Otherwise a misconfigured env var would verify every response, since
  // every string contains the empty string.
  assertFalse(servedAsRequested({ level: "standard", is_fallback: false }, ""));
});
