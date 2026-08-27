/// Extract the JSON body from a model reply.
///
/// MEASURED, not defensive coding: models behind ModelBeat wrap their output
/// in ```json fences DESPITE `response_format: {type: "json_object"}` (seen
/// 2026-08-11 on qwen3-32b and glm-4.7-flash, and again 2026-08-27 through the
/// staging router). The client parsers do a plain jsonDecode, so a fenced
/// reply throws and the feature fails in the quietest possible way — an empty
/// estimate, a plan that will not import, a memory that never populates. No
/// error anywhere.
///
/// Stripping here rather than in each client means one place to fix, and it
/// covers the three features that pass model content straight through.
export function unfence(raw: string): string {
  const t = raw.trim();
  if (!t.startsWith("```")) return t;
  const firstNewline = t.indexOf("\n");
  if (firstNewline < 0) return t;
  let body = t.slice(firstNewline + 1);
  const close = body.lastIndexOf("```");
  if (close >= 0) body = body.slice(0, close);
  return body.trim();
}
