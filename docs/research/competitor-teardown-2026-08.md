# Competitor teardown — August 2026

Store screenshots from four shipping nutrition apps, read against what Sakama actually
does today. Our side is **verified from the code**, not remembered: every "we do not
have this" below was checked against `app/lib/` on 2026-08-27.

No code was copied from anything. This is a features-and-decisions read.

---

## 1. Our baseline, as verified

| Surface | State |
|---|---|
| Screens | home, diary, coach, me, snap, scan, quick-add, plans (+detail, import), memory, onboarding, 3 settings |
| Home shows | today's calories, macro row, meal cards |
| Diary shows | 28-day summary, expandable day rows, food entries, workouts |
| Entry edit | name, kcal, protein, carb, fat, grams, **meal** |
| Food logging | photo, barcode, search, quick-add, Vita chat |
| Saved | favourites + custom foods (`user_foods`) |
| Provenance | `source`, `licence`, `confidence` on every food row |

---

## 2. Gaps that are real, ordered by what they cost the user

### 2.1 You cannot move an entry to another day

Their edit sheet offers **servings, meal, date and nutrition**. Ours offers everything
except **date** (`log_entry_sheet.dart:65`).

The failure is ordinary and constant: you log dinner at 1am and it lands on the wrong
day, or you remember yesterday's lunch this morning. Today the only repair is delete and
re-add, which loses the entry and its provenance. This is a one-field fix and it is the
cheapest real improvement on this list.

### 2.2 Portions are grams-only, and that is worst for our own users

They log `1.5 cup`, `1 slice`, `1 medium`, `2 oz`, `1 container` — a serving multiplier
over a named unit, with grams derived underneath.

We take grams and nothing else. That is backwards for the market we chose: **CONTEXT.md
§3.1 says portions are katori, piece and plate**, and the food schema already carries
`default_serving_label` and `default_serving_grams`. We store the right thing and then ask
the user to convert it in their head. "Two rotis" becoming "80 g" is arithmetic we should
be doing, not them.

This is the single biggest UX gap, and it is bigger for us than for the app it was copied
from, because a katori has no intuitive gram value to an Indian user either.

### 2.3 Confidence is computed and then thrown away

Every one of their food rows carries a green shield. Rule 7 makes us store `source`,
`licence` and `confidence` on every food row, and `confidence` appears in **zero** food
UI — verified by grep across `lib/features/*/presentation/`.

We do the hard, legally-motivated part and skip the part the user sees. It matters more
for us: our Indian dishes come from AI estimation, so "verified" versus "estimated" is a
real distinction, and it is the honest counterweight to a number a model guessed.

### 2.4 Burn is calculated and hidden

One dashboard reads `1,488 consumed · 846 remaining · 314 burned`, three figures side by
side rather than a net number.

We shipped the MET burn today and **Home does not show it at all** — only the Diary day
row does. Showing it separately is the correct call for the same reason the calculation
returns null instead of zero: a number that changes what somebody eats has to be visible,
not folded invisibly into a budget.

### 2.5 No Library

They have one: Foods 39 · Meals 5 · Exercises 16 · Workout presets 3, with a Create row
above it.

We have favourites and custom foods, and no home for them. Two pieces are missing
outright: **meals** (a named group of foods logged in one tap — "my usual breakfast") and
**workout presets** (the same idea for the gym). Both are pure repetition-killers, and
repetition is what tracking is.

### 2.6 Progress is one number, not a trend per thing

Their Progress tab breaks into Overview · Calories · Nutrients · Macros · Weight · Steps,
with per-nutrient cards carrying the week's average and a sparkline.

Our Diary summary gives 28-day averages in aggregate. Vita can answer a progress question
in chat (#132), which is genuinely better than a chart for "how did last week go", but
there is no place to *look* at protein over time without asking.

### 2.7 Search has one source and no way to say which

They show `USDA · FatSecret · Mealie · Open Food Facts` as filter chips.

For us this is not decoration. Rule 5 requires OFF rows to stay physically separate, and
[ADR 0014](../adr/0014-off-live-lookup-only.md) makes OFF live-lookup-only. A source chip
is how that separation becomes legible to the user instead of an invisible implementation
detail — and it is how someone avoiding crowd-sourced data can say so.

### 2.8 Smaller, still real

- **No week strip.** Their `S M T W T F S` with completion dots gives streak feedback with
  no nagging. Fits PRODUCT.md principle 4 better than a notification does.
- **Micronutrients are stored and unshown.** We keep fibre; their entry detail lists fibre,
  sugars, saturated fat and sodium. CONTEXT.md §3.1 promises a micronutrient panel, and
  sodium and iron feed the condition-aware coaching we say is a differentiator.
- **No rest timer** in workouts, and no per-exercise history. Pairs with the carry-over
  idea from LiftLog (AGPL, read for domain understanding only) — see §4.
- **No recipes or meal planning.** Two of the four apps lead with it. M4 territory, not now.

---

## 3. What not to take

### Auto-tracking the camera roll

One app offers "Snap Gallery · Auto-Track": it reads the photo library and logs meals it
finds, unprompted.

It is a clever friction kill and it is the wrong trade for us. It needs standing access to
every photo on the device, for a health app, in a product whose stated promise is no ads
and no data selling. The blast radius of one bug is somebody's entire camera roll reaching
a vision model. A share-sheet target, or "pick from recent photos", gets most of the value
and none of that exposure.

### Medication tracking

One shows an Ozempic dose countdown and side-effect logging. GLP-1 tracking is a real
market, and it moves the product from nutrition into **medication adherence**, which is a
different regulatory posture and a different duty of care. Not a v1 question, and not one
to drift into by accident.

### The engagement furniture

A lightning-bolt streak counter in the header, and rocket and tick emoji in insight cards.
PRODUCT.md's anti-references name guilt-driven fitness apps and generic AI chrome
explicitly. The week strip is worth taking because it is information. The streak counter
next to it is a score, and a score invites shame on the day it resets.

---

## 4. What to build, in order

Ranked by user value per unit of work. The first three are small.

| # | Change | Why it is first |
|---|---|---|
| 1 | **Date on the entry edit sheet** | One field. Fixes a mistake every user makes weekly, that currently costs them the entry. |
| 2 | **Serving multiplier** (`1.5 × katori`) | The data is already in the schema. Removes mental arithmetic from every single log, and Indian portions are the whole positioning. |
| 3 | **Confidence badge** on food rows | Data already stored, rule 7 already requires it, nothing new to compute. Turns provenance from a legal obligation into a trust signal. |
| 4 | **Burn on Home** | Shipped today and invisible. Three figures, not a net. |
| 5 | **Meals** (named groups, one tap) | The largest repetition kill available. Needs a table and the four-file contract. |
| 6 | **Workout carry-over + presets** | Turns the workout log into a training tool. See the LiftLog notes: open each exercise on last session's numbers, ignore abandoned sessions. |
| 7 | **Source chips in search** | Makes ODbL separation visible instead of hidden. |
| 8 | **Week strip** on Home | Streak feedback without a streak counter. |

Items 5–8 want the whole-health work in ROADMAP M8 anyway; 1–4 do not block on anything.

---

## 5. Where we are already ahead, and should not trade it away

Worth stating, because a gap list read alone argues for becoming a copy of the thing it
compares against.

- **Conversational logging with propose-confirm.** Two of these apps have voice logging that
  transcribes and logs. Vita bounds-checks every argument before a draft can exist, and the
  user taps to confirm. That is slower by one tap and correct by construction.
- **A plan engine.** They have meal planners; we have plans as JSON data that Vita reads and
  enforces, including fasting windows and blocked foods. That is the Type 1 user nobody else
  serves.
- **Offline-first for real.** Local Drift is the source of truth, not a cache. Every one of
  these apps needs a network for its core loop.
- **Refusing to invent numbers.** Null burn instead of a default 70 kg person; no accuracy
  figure quoted for an unmeasured model. It costs a feature here and there and it is the
  entire reason to trust a nutrition app.
