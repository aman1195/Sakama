# 08 · User foods: favourites and custom foods

> The second slice of the food-library idea. Slice 1 ("recently logged") shipped with **zero schema**
> by deriving from `food_logs`; this adds the table that recents cannot replace — foods you *choose*
> to keep, and foods that exist nowhere but your kitchen.
> **Status: proposed — design only.** Resolves the long-open **#35**.

## 1. What recents cannot do

`recentDistinct()` answers "what did I eat lately". It cannot answer:

- **"Keep this one."** A dish eaten once a month falls out of the recency window (the reviewer's
  bounded-lookback note on #96) and vanishes.
- **"This is my version."** *My mum's rajma* exists in no corpus and never will.
- **"My usual portion."** The corpus knows dal tadka per 100 g; it does not know that *your* katori is
  180 g.
- **"Suggest something I actually like."** Vita can only ground on what it can see; a favourites list is
  a stated preference, not an inference.

## 2. The trap #35 exists to prevent

`FoodRepository.ensureSeeded` runs `DELETE FROM foods` on every `seedVersion` bump. Anything
user-authored stored there is **silently destroyed** on the next release, with no server copy for a
local-only table.

**Therefore: a separate `user_foods` table. Never `foods`.** This is the whole reason #35 was filed.

## 3. The licence trap, and the design that removes it

[CLAUDE.md rule 5](../../CLAUDE.md) calls Open Food Facts the single biggest legal risk in the stack:
ODbL data must stay in a physically separate, source-tagged table and must never be merged into the
proprietary tables.

Copying OFF nutrition values into `user_foods` would create exactly that merge — a derived database
mixing ODbL values into per-user rows, which then **sync to our server**.

**So a user food never copies nutrition it did not author.** A row is one of two things:

| kind | what it stores | nutrition comes from |
|---|---|---|
| **pointer** | `source_table` + `source_id` + *your* portion | read at display time from `foods` / `off_foods` |
| **custom** | its own per-100 g values | itself — the user authored them |

A favourite of an OFF product is a **pointer plus a portion**. No ODbL value is duplicated, so nothing
ODbL-licensed ever reaches the server. The containment is **structural**, not a rule someone must
remember — which is the only kind that survives.

**Enforced by the API shape, not by discipline.** `UserFoodRepository.addPointer()` takes **no
nutrition parameters at all** — only `sourceTable`, `sourceId`, and the user's portion. A caller
therefore *cannot* copy OFF values into a pointer row even by accident; there is nowhere to put them.
`addCustom()` is the only method that accepts nutrition, and by definition its values are
user-authored. This is stronger than a regex gate, which can never prove the absence of a copy.

## 4. Schema (synced)

Unlike conversations (device-local by [ADR 0016](../adr/0016-vita-as-assistant.md)), user foods are
per-user data worth surviving a lost phone, so this is the **full four-file contract**: Drift +
PowerSync + Supabase migration with RLS + sync-streams entry, and a forward-only migration with a
preservation test.

```
user_foods
  id             text pk
  user_id        text null          -- offline-birth rule, as every synced table
  name           text               -- what the USER calls it ("mum's rajma")
  kind           text               -- 'pointer' | 'custom'
  source_table   text null          -- 'foods' | 'off_foods'   (pointer only)
  source_id      text null          -- row id there              (pointer only)
  energy_kcal    real null          -- per 100 g                 (custom only)
  protein_g      real null
  carb_g         real null
  fat_g          real null
  fiber_g        real null
  serving_label  text null          -- "1 katori"
  serving_grams  real null          -- YOUR portion, both kinds
  created_at     int
  updated_at     int                -- LWW
```

Nutrition is per 100 g for custom rows, matching the canonical rule; the logged portion is derived at
read time from `serving_grams`, exactly as the corpus path already does.

**A pointer whose target is missing** (OFF cache evicted, corpus reseeded) must degrade to a named
entry the user can still tap and complete by hand — never a crash and never a silent zero.

## 5. How a food gets into the library

All four routes converge on one repository method, so provenance and licence handling cannot drift:

1. **From a logged row** — "keep this" on the entry sheet (built in #100).
2. **From PhotoSnap** — keep an identified item.
3. **From Vita** — "remember this as my usual breakfast".
4. **By hand** — the "create a food" form, for what exists in no database.

## 6. How it is used

- **Add food**: a *Favourites* section beside *Recent*, one tap to log at your portion.
- **Vita**: the grounding snapshot gains a short favourites list, so "what should I eat?" can answer
  from foods you actually like rather than generic advice. That is the wedge working as intended.

Favourites are **explicit** data Vita reads. They are deliberately **not** memory facts (phase 4):
memory is inferred and correctable; a favourite is stated. Two sources of truth about what you like,
disagreeing, would be worse than either alone.

## 7. Testing

- Repository against real sqlite: create/list/delete both kinds; a pointer resolves its nutrition from
  the source table; a **missing target degrades** rather than crashing; `user_id` scoping.
- **Migration**: forward-only, additive, with a preservation test seeding every existing table.
- **Licence**: a test asserting an OFF-derived favourite stores **no nutrition values** — the structural
  guarantee of §3, enforced rather than documented.
- **CI gate: tried and deliberately NOT adopted.** A regex rule for `user_foods` was added and
  **failed on the repository that implements the guarantee correctly** — `addCustom` legitimately
  writes user-authored nutrition, and `resolve()` legitimately reads `off_foods`, so the three signals
  co-occur in a correct file. A gate that fires on correct code is worse than none: it teaches people
  to suppress it, and the next person adds an exclusion instead of thinking.

  The belt-and-braces role is filled better by the **Postgres CHECK** (§4): it enforces the invariant
  at the server, cannot be bypassed by any client, and cannot produce a false positive. Together with
  the `addPointer()` signature and the unit test, that is three independent guarantees — none of them
  a regex, because a regex can never express "this value was not copied from there".
- UI: keep-from-log, keep-from-PhotoSnap, log-from-favourites at the stored portion.

## 8. Decisions

1. **A pointer FOLLOWS its source; it never freezes it.** This looked like a UX trade (a corrected
   corpus value stays accurate vs a reproducible log history), but for an OFF pointer it is a
   **licence** decision: "freeze" means copying the OFF nutrition into `user_foods` at save time —
   which **is** the ODbL merge §3 exists to prevent, and it would then sync to our server.

   So freeze is **not available** for OFF pointers on rule-5 grounds, independently of any
   reproducibility argument, and there is no reason to treat corpus pointers differently. Log history
   stays reproducible anyway, because a `food_logs` row already snapshots the values as logged.

   Recorded explicitly so a future implementer cannot choose "freeze" for reproducibility and quietly
   reintroduce the trap.

2. **Ordering: most-used**, since the point is to shorten the common path.

## 9. Privacy

§6 adds a favourites list to Vita's grounding snapshot — another slice of user data sent to the
provider. The consent copy and inventory (#87) must be updated **with the feature**, as was done for
plan context and photos, not afterwards.
