// Guard against a gateway silently serving a DIFFERENT model than the one
// pinned. ModelBeat returns HTTP 200 with another model when a pin is
// unrecognised or retired — no error, no warning field (their API.md §4.3;
// reproduced 2026-08-11: asking for "google/gemini-2.5-flash" was served by
// ministral-3-8b).
//
// Lives in its own module so it can be unit-tested: importing vita/index.ts
// would execute Deno.serve and start a listener.

/// True only when the response PROVES the pinned model served the request.
///
/// ABSENT COUNTS AS UNVERIFIED. The first version of this check fired only
/// when `resolved_model_used` was a present string, so a missing or renamed
/// field skipped it — a guard labelled "fail closed" that failed OPEN, which
/// is worse than no guard because it reads as protection. On health data the
/// safe default is to refuse what cannot be confirmed.
///
/// Substring, not equality: providers append their own suffixes
/// (`deepseek-v3.2` is served as `deepseek.v3.2`, `qwen3-32b` as
/// `qwen.qwen3-32b-v1:0`), so an exact match would reject every valid
/// response. The pin is normalised the same way before comparing.
export function servedModelVerified(served: unknown, pinned: string): boolean {
  if (typeof served !== "string" || served.length === 0) return false;
  if (pinned.length === 0) return false;
  const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");
  return norm(served).includes(norm(pinned));
}
