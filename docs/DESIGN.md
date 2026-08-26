# Design — UI/UX System

> The interaction and visual system for Sakama. Brand and principles live in [PRODUCT.md](../PRODUCT.md).
> This document records **what we are taking from Fud AI and HealthifyMe, and what we are deliberately
> rejecting.**
>
> **Provenance note:** the Fud AI patterns below are verified from its source
> ([research/eval-fud-ai.md](research/eval-fud-ai.md) — its actual view and service names). The
> HealthifyMe patterns are from general product knowledge of the app, not a code-level teardown. If you
> want pixel-level fidelity on HealthifyMe, we should do a screenshot-driven UX teardown; say the word.

---

## 0. Visual refresh — August 2026 (SAK-124)

The visual language was refreshed from a set of modern **fintech** design references (a banking app
and an investing app). Provenance matters here as much as it did for food data: those are somebody
else's design shots, read for **direction only**. Nothing is reproduced screen-for-screen, and no
asset from them ships. Both typefaces they use are **SIL OFL** — checked before adoption, rule 4 —
and we bundle Plus Jakarta Sans with its licence file rather than fetching it, because offline-first
applies to typography too.

**What we took**

| From the references | Why it transfers |
|---|---|
| Near-black surfaces (`#101010` / `#1A1C19`) | Reads modern, saves OLED battery, and lets one accent carry the whole brand |
| One saturated accent (`#98EF5A`) | A single identity colour is easier to keep disciplined than a palette |
| Large display numerals, heavy weight, tight tracking | A day's calorie total should read like a headline, not a table cell |
| 20dp cards, stadium pills, borderless filled inputs | Softer, more touchable, fewer visual lines competing with data |
| Floating bottom bar with a pill indicator | Clear current-tab signal without chrome |

**What we refused, and this is the load-bearing part**

Both references **colour an entire card by a single metric** — a lime balance card when the number is
good, a red portfolio card when it is down. We did not take that, and the refusal is written into
`theme.dart` so it is not re-added later as an improvement.

In fintech, a red card is neutral information about money. In a health app, a red screen because you
ate too much *is* the guilt loop — [PRODUCT.md](../PRODUCT.md) anti-reference #1 — and it contradicts
principle 5 outright: *"Earn every colour... never colour the whole screen by a calorie deficit."*

So the rule is: **the accent marks identity, never judgement.** Brand surfaces, the primary action,
the selected tab. Amber and red stay reserved for attention and genuine problems.

Three tests in `test/app/theme_test.dart` enforce it rather than trusting discipline: the accent can
never be reused as a macro colour, no macro may be alarm-red, and the four macros must stay
distinct. Contrast is asserted at WCAG AA on both themes — which caught a real trap, since the raw
lime cannot carry white text, so light mode uses a darkened variant and only dark mode uses it neat.

## 1. What we take from Fud AI

Fud AI's core insight, and the one we adopt wholesale: **the AI is the logging mechanism, not a feature
in a side menu.**

| Pattern (from its source) | What it is | Adopt? |
|---|---|---|
| **AI-first capture** | Photo / voice / nutrition-label / barcode are the *primary* log paths. Manual search is the fallback, not the default. | ✅ **Core.** This is the whole product. |
| **`FoodResultView` — confirm before log** | AI returns items → user reviews, adjusts portion, then commits. Never silently logs a guess. | ✅ **Core.** This is how we surface confidence and capture corrections. |
| **`unit_options` portion semantics** | AI returns *sensible units* (slice, piece, cup, tbsp, can), not just grams. Counts visible slices of a divisible food. | ✅ **Core**, re-vocabularized: katori, roti, phulka, idli, dosa, glass. |
| **`ChatView` — coach as a first-class tab** | The coach is a persistent conversation with memory, not a popup. | ✅ Adopt (our Vita). |
| **Progress rings + `HomeComponents`** | At-a-glance daily calories/macros against target on the home screen. | ✅ Adopt. |
| **Widgets + Watch app** | Log and glance without opening the app. | ➖ Post-v1. Strong retention lever, not a launch blocker. |
| **Provider picker in settings (BYOK)** | User can plug in their own AI key. | ✅ Adopt as the **power-user tier**, not the default. |

### The one thing we explicitly do NOT copy from Fud AI
Its **BYOK-only architecture**. Fud AI has no backend, so *every* user must bring an API key. That is a
dealbreaker for a mass-market Indian app. We route AI through our own proxy so **the default user gets AI
for free**, with BYOK as an option. See [architecture/02-ai-layer.md](architecture/02-ai-layer.md).

---

## 2. What we take from HealthifyMe

HealthifyMe's strength is that it makes a **daily habit** feel obvious and Indian users feel seen.

| Pattern | What it is | Adopt? |
|---|---|---|
| **Calorie budget model** | Frame the day as a budget: target, consumed, burned, remaining. Simple, universally understood. | ✅ Core mental model for the home screen. |
| **Meal-slot cards** | Breakfast / Lunch / Dinner / Snack as fixed, always-visible slots with a "+" on each. | ✅ Adopt. This is the single most important layout decision. |
| **Indian food framing** | Dishes named as people actually say them, in Indian portions. | ✅ Core, and we go further with a real Indian DB. |
| **Coach presence** | A named coach who checks in. Makes the app feel accompanied, not audited. | ✅ Adopt (Vita), but every message must be grounded in real data. |
| **Plans as a first-class object** | A visible, followable plan with day-by-day structure. | ✅ Adopt via our JSON plan engine (serves plan-followers and goal-setters). |
| **Streaks / consistency** | Gentle habit reinforcement. | ✅ Adopt, **without** loss-shaming. |
| **Quick-add / recents / favourites** | Yesterday's dal is one tap away. | ✅ Adopt. Huge friction win. |

### Home-screen teardown (screenshot-driven, 2026-07-29)

Owner-supplied screenshots of HealthifyMe's live home screen. What actually makes it feel great,
and what Sakama adopts vs. rejects (visual pass SAK-37 implements the adopts):

| Observation | Verdict |
|---|---|
| **One hero number per card** ("Eat 1,650 Cal") — everything else subordinated | ✅ Adopted: the calorie ring's remaining-kcal is the single display-size number on Home. |
| **Progress rings as the shared visual language** across trackers (workout, steps) | ✅ Adopted for calories now; rings for future trackers (steps, fasting) as they land. |
| **Scannable tracker rows**: leading icon in a circle, name + one fact, ONE action on the right | ✅ Adopted for meal-slot cards (per-meal icon circle, kcal + item count, a "+"). |
| **Warm illustrated empty state** ("Nothing Tracked Yet!") with a single CTA | ✅ Adopted, assetless (tilted tinted tiles) — teaches the first action instead of a blank list. |
| **Per-tracker accent colors** giving each metric a stable identity | ✅ Adopted for macros (protein/carbs/fat identity colors, used ONLY for those macros). |
| Sparkle-FAB AI affordance on every screen | ❌ Rejected — PRODUCT.md anti-reference ("a sparkle icon on everything"). Vita is a *tab*, not chrome. |
| "Free Trial Expired" pill + premium framing on the home screen | ❌ Rejected — no premium wall on basics, ever. |
| Unread-message marketing hero occupying the top third | ❌ Rejected — Home opens on *today*, not on a message from us. |

### What we reject from HealthifyMe
- **The premium wall.** Core tracking, the food database, and basic AI stay free. Always.
- **Nutritionist upsell pressure.** Vita replaces it, free.
- **Notification nagging** and guilt framing.

---

## 3. Information architecture

Five tabs. Resist adding a sixth.

```
┌──────────────────────────────────────────────┐
│  HOME        DIARY      [ + ]   COACH   ME   │
└──────────────────────────────────────────────┘
```

- **Home** — today at a glance. Calorie budget ring (target · eaten · burned · remaining), macro bars,
  quick chips (water, steps, fasting), today's plan day-type banner and checklist if a plan is active.
- **Diary** — calendar-driven log. Meal-slot cards (Breakfast/Lunch/Dinner/Snack), micronutrient panel,
  day totals vs. targets.
- **[ + ] — the capture button (centre, prominent).** This is the product. Opens the capture sheet:
  **Photo · Voice · Barcode · Search · Quick add**. Photo is the default focus.
- **Coach** — Vita. Persistent chat with memory and full context of the plan and today's logs.
- **Me** — profile, weight chart, plan, goals, settings, BYOK key, data export.

## 4. The capture flow (the most important flow in the app)

```
[ + ] → Capture sheet
         ├── 📷 Photo  → camera → AI analyses → ┐
         ├── 🎤 Voice  → speak → AI parses    → ├→ CONFIRM SHEET → logged
         ├── ▮▮ Barcode → scan → DB lookup     → │   (items, portion,
         ├── 🔍 Search  → local Indian DB      → │    confidence, edit)
         └── ⚡ Quick add → title + kcal        → ┘
```

**Rules:**
1. **Never skip the confirm sheet on AI paths.** Show each detected item, its portion in an Indian unit,
   its macros, and a **confidence indicator**. One tap to adjust portion. One tap to log.
2. **Corrections are training data.** Every portion the user fixes is captured and fed back
   (see [architecture/03-food-database.md](architecture/03-food-database.md) — the AI-estimate promotion queue).
3. **Optimistic and offline.** The log commits locally and instantly. Sync happens invisibly.
4. **Target: under 10 seconds, photo to logged.**

## 5. Visual language

- **Warm, not clinical.** Off-white / warm-neutral base, not stark grey. Dark mode is a peer, not an
  afterthought.
- **One accent for on-track (green), amber for attention, red reserved for genuine problems.** Never paint
  the screen red for a calorie overshoot.
- **Data is legible first.** Numbers big and scannable; decoration never competes with the figure.
- **Type:** one humanist sans with strong Devanagari support (Hindi is a launch-adjacent locale — do not
  pick a face that cannot render it).
- **Motion:** functional only (state transitions, ring fills). Reduced-motion alternatives required.
- **No AI chrome.** No sparkles, no gradient "AI" badges. The intelligence shows up in the answer.

## 6. Components to build (v1)

| Component | Notes |
|---|---|
| `CalorieBudgetRing` | target / eaten / burned / remaining. The hero of Home. |
| `MacroBars` | protein, carbs, fat, fibre vs target. |
| `MealSlotCard` | Breakfast/Lunch/Dinner/Snack, with entries + "+". |
| `CaptureSheet` | the five capture modes. |
| `FoodConfirmSheet` | **the highest-value screen in the app.** Items, Indian portion stepper, confidence, edit, log. |
| `MicronutrientPanel` | iron, calcium, vitamins vs DRI. Day and week view. |
| `PlanDayBanner` | day-type + checklist when a plan is active. |
| `CoachThread` | streaming chat, grounded context chips. |
| `WaterChip`, `FastingChip`, `StepsChip` | one-tap trackers on Home. |
| `WeightChart` | trend with moving average. |

Charts via `fl_chart` (MIT). **Do not use Best-Flutter-UI-Templates** — its licence is not MIT and is
unsafe for a commercial product (see [research/base-decision.md](research/base-decision.md)).

## 7. Onboarding

Six steps, each one screen, skippable where honest:
1. Goal (lose weight / detox / build muscle / manage condition / just track)
2. Profile (age, weight, height, gender)
3. Diet (veg / non-veg / vegan / eggetarian)
4. Health conditions (optional — diabetes, thyroid, liver, PCOD…)
5. Cuisine (North / South / both / other)
6. Activity level

→ **AI generates a personalized 7-day plan, live, in front of them.** This is the "wow" moment and it must
feel fast. Show it being written.
→ Alternative path: **import an existing plan** (paste text or upload a document) for plan-followers.
