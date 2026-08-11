# Model bake-off — August 2026

> **Verdict: `gemini-2.5-flash` stays on PhotoSnap. Extraction moves to ModelBeat (`deepseek-v3.2`).**
> Run 2026-08-11 against the Phase 0 harness in [`spikes/photosnap-validation/`](../../spikes/photosnap-validation/)
> — the same 22 Indian meal photos, the same prompt, the same ground truth that produced the original
> GO in [photosnap-spike-findings.md](photosnap-spike-findings.md).

## Why this ran

ModelBeat offered credits, and a free gateway is worth taking seriously. The question is not "is it
cheaper" but "does it hold the quality the wedge depends on". PhotoSnap accuracy on Indian food is
the product; a cheaper wrong number is not a saving.

## 1. Vision — all four of ModelBeat's vision models

Pass band is ±30% on calories, per [ADR 0013](../adr/0013-validate-photosnap-before-build.md).

| model | gateway | median kcal err | mean | PASS | protein | carb | fat | ~$/photo |
|---|---|---|---|---|---|---|---|---|
| **gemini-2.5-flash** | OpenRouter | **9%** | 15% | **18/22** | 18 | 11 | 18 | ~0.0020 |
| kimi-k2.5 | ModelBeat | 18% | 21% | 15/22 | 26 | 20 | 22 | ~0.0026 |
| mistral-large-3 | ModelBeat | 18% | 26% | 14/21 | 24 | 16 | **46** | ~0.0016 |
| qwen3-vl-235b | ModelBeat | 20% | 26% | 15/22 | 16 | 26 | 41 | ~0.0023 |
| gpt-5-mini | OpenRouter | 24% | 27% | 12/19 | 40 | 22 | 50 | — |
| gemini-2.5-flash-lite | OpenRouter | 30% | 34% | 11/22 | 39 | 21 | 40 | — |
| ministral-3-8b | ModelBeat | 53% | 49% | 7/21 | 45 | 53 | 42 | ~0.0003 |

**Findings**

- **`kimi-k2.5` is ModelBeat's best and still doubles the error.** 9% → 18% median, 18/22 → 15/22.
  It is a good model — its 22% fat error is the only one near Gemini's 18%, and fat is where Indian
  cooking hides calories — but twice the error at a slightly *higher* price is not a trade.
- **`mistral-large-3` is the only cheaper option, and fails where it matters**: 46% fat error, plus
  one image (`dosa-masala.jpg`) that errored outright. Saving $0.0004 a photo to quadruple the fat
  error is not a saving.
- **`qwen3-vl-235b` returned ZERO items on `thali-south.jpg`**, the 12-item restaurant thali. In the
  app that surfaces as "that doesn't look like food" on a real, large meal — the exact plate where a
  nutrition app most needs to work.
- **`ministral-3-8b` (tier 1) is unusable** at 53% median error, despite being 7× cheaper.

**Free credits do not change this.** Quality is the wedge; a free wrong number still costs trust.

## 2. The trap that would have produced a wrong conclusion

ModelBeat returns **HTTP 200 served by a different model** when a pin is unrecognised or retired —
no error, no warning field (their API.md §4.3). Reproduced here: asking for
`google/gemini-2.5-flash` was silently served by `ministral-3-8b`.

Had the harness not checked, it would have scored Ministral's output and attributed it to whatever
was pinned. **The runner now records `resolved_model_used` on every call and refuses to score a
response served by a model it did not ask for.** The Edge Function does the same and fails closed.

Any production use of ModelBeat MUST assert on `resolved_model_used`.

## 3. Text extraction — where ModelBeat does win

Fixture: a five-turn transcript containing a constraint (lactose intolerance), a goal (90 g protein),
a routine (3 eggs at 8am daily), and one **trap** — "I had dal chawal for lunch today", which is a
diary entry, not a memory, and must NOT be extracted.

| model | fenced output? | confidence calibration | trap avoided | verdict |
|---|---|---|---|---|
| **deepseek-v3.2** | no | 0.9, sensible | yes | **chosen** |
| qwen3-32b | **yes** | 0.9, sensible | yes | usable |
| glm-4.7-flash | **yes** | 1.0 for everything | yes | poorly calibrated |
| kimi-k2-thinking | n/a | n/a | n/a | returns **null content** |

**All three non-reasoning models passed the trap**, which is the hardest instruction in the prompt.
Two things separated them: fencing, and calibration. `glm-4.7-flash` reporting 1.0 confidence for
every fact is useless to a ranking that sorts on confidence.

**A shipping bug, caught here:** `qwen3-32b` and `glm-4.7-flash` wrap their JSON in ```` ```json ````
fences **despite `response_format: json_object`**. Our client did a plain `jsonDecode`, so a fenced
reply would throw, `parse()` would return an empty `Extraction`, and memory would **silently never
populate** — a feature that looks perfectly healthy, logs no errors, and learns nothing. The parser
now de-fences, with tests.

## 4. Decisions

1. **PhotoSnap stays on `gemini-2.5-flash`.** Nothing tested comes close.
2. **Extraction moves to ModelBeat `deepseek-v3.2`**, chosen on the evidence above and overridable
   via `MODELBEAT_EXTRACT_MODEL` without a deploy.
3. **Provider is configurable per feature.** ModelBeat is a *beta* endpoint with unlimited default
   rate limits; an outage there must degrade extraction alone, never the whole app. Unset
   `MODELBEAT_API_KEY` and extraction falls back to OpenRouter.
4. **BYOK always pins OpenRouter**, whatever the mode. A user's own key must never be spent on a
   gateway they did not choose.
5. **Vita chat and plan generation are NOT moved** — there is no eval harness for tool-selection
   quality yet ([ADR 0016](../adr/0016-vita-as-assistant.md) decision 7 specified one and it was
   never built). Moving them on the strength of a vision bake-off would be exactly the assumption
   this document exists to avoid.

## 5. Limits of this evidence

- **22 web photos, not user photos** — the Phase 0 caveat still applies.
- **One extraction fixture.** Enough to separate fencing and calibration, not enough to rank
  extraction quality finely. A larger fixture set is the natural companion to the missing
  tool-selection harness.
- **Costs are estimates** from the published per-million rates and the Phase 0 token profile
  (~1.3K in, ~600 out), not measured invoices.
