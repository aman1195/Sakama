import { assertEquals } from "jsr:@std/assert@1";
import { unfence } from "./json_content.ts";

Deno.test("a ```json fence is stripped", () => {
  assertEquals(unfence('```json\n{"a":1}\n```'), '{"a":1}');
});

Deno.test("a bare ``` fence is stripped", () => {
  assertEquals(unfence('```\n{"a":1}\n```'), '{"a":1}');
});

Deno.test("unfenced JSON is untouched", () => {
  assertEquals(unfence('{"a":1}'), '{"a":1}');
  assertEquals(unfence('  {"a":1}  '), '{"a":1}');
});

Deno.test("a fence with no closer still yields the body", () => {
  // Truncation at max_tokens is common enough to matter: better to hand the
  // caller partial JSON it can reject than a string it cannot parse at all.
  assertEquals(unfence('```json\n{"a":1}'), '{"a":1}');
});

Deno.test("a lone fence marker does not crash", () => {
  assertEquals(unfence("```"), "```");
});
