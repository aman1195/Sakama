# 07 · Photo in chat: PhotoSnap as the shared vision service (phase 3)

> Phase 3 of [ADR 0016](../adr/0016-vita-as-assistant.md), realising decision 11: PhotoSnap stops
> being a one-shot recogniser and becomes the app's **shared vision service**, so Vita can answer
> questions *about a picture* instead of about a name and a calorie count.
> **Status: proposed — design only.** Decisions below came out of a `/grilling` pass.

## 1. Why one service, not two

Answering "should I eat this?" needs the model to **see** the food — portion, oil, freshness — which a
structured item list throws away. But re-implementing vision in a second function would mean two
prompts, two budgets and two quality bars to maintain.

So one call in **converse mode** returns everything: `items` (loggable), `description` (reusable), and
`answer` (the reply). That is cheaper than recognise-then-discuss and richer than discuss-without-seeing.

## 2. The mode contract

`mode` defaults to today's behaviour, so **existing callers are untouched** and new keys are additive
siblings to `items` (the client already reads `j['items']` by key).

| | `mode` absent / `"log"` (today) | `mode: "converse"` (new) |
|---|---|---|
| Input | `image`, `mime` | `+ question` (optional), `+ context` (grounding) |
| Output | `{items:[…]}` or `{error:"no_food"}` | `{items:[…], description, answer}` |
| Prompt | **byte-identical to today** | its own prompt, carrying the combined job |
| Not a meal | refuses `no_food` | **answers anyway**, `items: []` |

**Separate prompts per mode is deliberate.** PhotoSnap's extraction accuracy is what earned the Phase-0
GO decision ([ADR 0013](../adr/0013-validate-photosnap-before-build.md)); rewriting that prompt into a
coach would put a validated path at risk for the benefit of a new one. Tuning one mode must never be
able to degrade the other.

**Non-food images are answered in converse mode** (decision 8). A menu, an ingredients label or a
packet is exactly where a nutrition coach earns its place; refusing because it is not a plated meal
reads as broken. Log mode keeps `no_food`, because there genuinely is nothing to log.

## 3. Budget (decision 3)

A photo message costs **1 exchange + 1 photo** ([ADR 0016](../adr/0016-vita-as-assistant.md) decision
12). Converse mode is a single call, so the function charges both itself:

```
increment_ai_usage("vita",      cap 30)   ← FIRST
increment_ai_usage("photosnap", cap  8)   ← second
```

**Order is load-bearing.** These are two separate atomic RPCs, not one transaction: whichever is
charged first is spent even if the second is exhausted. Charging the abundant resource first means a
refused request burns 1 of 30 rather than 1 of only 8 daily photos. BYOK skips both, as elsewhere.

## 4. Entry points (decision 4)

Two doors, **one controller method** — so there is a single state machine to reason about and test:

1. **Attach button in the chat input.** Photo + optional caption sent together; with no caption the
   question defaults to "what is this, and should I eat it given my plan?".
2. **"Ask Vita" on the PhotoSnap result.** This path has *already* paid for vision, so it sends the
   extracted `items` + `description` **as text** on a normal Vita turn — 1 exchange, **no second photo
   charge**, no second vision call to re-derive what is already in hand (decision 5). The trade is that
   Vita reasons from names and macros rather than pixels; acceptable because from this entry point the
   food is already identified and on screen.

## 5. The photo is not stored (decision 1)

The image is **never persisted**. The message keeps the model's description instead:

```
[photo: two rotis, dal tadka, cucumber salad] is this too oily?
```

Why: chat text is ~1.5 MB/year, which is what made "keep until deleted"
([ADR 0016](../adr/0016-vita-as-assistant.md) decision 9) safe. Photos are ~100–500 KB **each**; at the
8/day cap that is 300 MB–1.5 GB/year on the user's phone — it would break the premise of that decision,
and force file-deletion logic into thread deletion (an orphaned-file bug class text does not have).
It also matches today's PhotoSnap, which already discards the image after the call.

**The description does double duty** (decision 7): it is the visible stand-in in the transcript *and*
the grounding for follow-up turns, because it flows upstream as ordinary history. It is written into
the user's message once the vision call returns — a new `ChatRepository.updateMessage`, **no schema
change**. Cost: that message is written twice (once on send, once when the description arrives).

## 6. Logging from a photo conversation (decision 6)

Nothing is offered automatically. The user says "log it in lunch" and the existing **phase-2 tool path**
runs unchanged: tool call → `ToolCallParser` bounds-check → confirm card → write tagged
`logged_via: 'vita'`.

Deliberately not auto-offered: **"should I eat this?" is asked *before* eating.** A confirm card there
presumes a meal that has not happened, and a mis-tap would put a phantom entry in the diary. Saying
"in lunch" also names the meal slot for free, instead of us guessing from the clock.

## 7. Testing

**Locally testable (CI):** the mode branch and response parsing; the PhotoSnap→Vita text handoff builds
the right payload and does **not** call vision; the description is written into the message and appears
in the next turn's history; a non-food converse response with empty `items` still renders an answer;
budget errors map to the right messages; both entry points reach the same controller method.

**Operator-verified:** the deployed function, real vision quality in converse mode, and the two
`increment_ai_usage` calls against real Postgres — `supabase functions deploy photosnap` plus a
real-JWT smoke test, as with `generate-plan`.

## 8. Out of scope / carried forward

- **Privacy copy needs widening**: the disclosure says *"PhotoSnap sends the food photo you take"* —
  after this, **Coach** sends photos too. Same data, new surface; update with the feature, not after.
- **Food library / favourites** (raised in the same session) is its own milestone, not part of this
  phase. It resolves the open #35 and must respect three constraints: a separate `user_foods` table
  (never `foods`, which `ensureSeeded` deletes wholesale), ODbL provenance preserved on anything
  derived from Open Food Facts (CLAUDE.md rule 5), and a clear split between *a pointer to a corpus
  food with your usual portion* and *a genuinely custom food*. "Recently logged" is derivable from
  `food_logs` with **zero schema** and is the cheap first slice.
