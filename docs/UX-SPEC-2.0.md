# Sakama 2.0 — Frontend / UI / UX Product Specification (v2)

> **Version 2, 2026-08-31.** This revision replaces v1 of this document. The product owner adopted
> the "app does the work" vision (three pillars below) and the richer visual direction after using
> the shipped app and judging it under-designed. v2 is therefore a **redesign spec**, not an
> increment: it changes the information architecture, the home screen, the visual identity, and
> Vita's presence model. The engineering foundation (offline-first Drift, PowerSync, RLS, licence
> containment, the AI gateway) is unchanged and is what makes this redesign a matter of weeks, not
> months.

## The three pillars (product owner's vision, binding)

1. **Invisible Logging.** The fastest log is the one the user barely notices making. PhotoSnap,
   voice logging, barcode scan, and AI-assisted search exist to reduce the average food log to
   under 5 seconds. Every logging entry point is reachable in one tap from the home screen.
2. **Contextual Intelligence.** Vita is not a chatbot in a separate tab. It surfaces proactively
   on the dashboard with observations, inside food search ("This dal has 18g protein — good for
   your current deficit"), and inside workout logging ("You last did this exercise 6 days ago at
   60kg"). The AI is woven into every screen, not siloed.
3. **Honest Progress.** The app never hides bad days. Streaks show gaps honestly. Charts show
   trends without smoothing tricks. Calm and supportive, never gamified to the point of anxiety.
   A missed day is a gap, not a failure state.

The operating principle behind all three: **effort in, meaning out.** Every user action must
produce a visible, personal reaction from the app. Storage is not a product; the reaction is.

## Decision log — what v2 overrides, and what it refuses

The owner's direction wins on every product and aesthetic call. A small set of items from the
source document cannot ship as written; each carries its reason here, once, so it is not
re-litigated later.

| # | Topic | v2 decision |
|---|---|---|
| D1 | Calorie ring | **Adopted.** The ring returns as the Home hero (reverses the v1 "number only" treatment). |
| D2 | IA | **Adopted.** Tabs: Home · Diary · [+] · Progress · Vita. Settings behind the avatar. The Me tab is retired. |
| D3 | Visual identity | **Adopted.** New palette (teal system, §12) and type (Inter + Noto Sans, bundled). Retires the Aug 2026 lime/near-black refresh. |
| D4 | Proactive Vita | **Adopted.** Suggestion card on Home, insights in search and workouts, morning push nudge (opt-in at onboarding, per-module control). Every insight must trace to real user rows. |
| D5 | Streaks | **Adopted, honest variant.** Streak card with gap-not-reset semantics; milestone celebrations honor reduced-motion. |
| D6 | Meal photo gallery | **Adopted, opt-in.** Photos stored only when the user enables the gallery; per-user storage behind RLS, disclosed at enable time. |
| D7 | INDB | **Refused — legal.** INDB is unlicensed and IFCT-derived (CLAUDE.md rule 6, docs/research/base-decision.md). Everywhere the source document says "INDB", read **"Sakama Indian corpus"**: USDA CC0 base + AI estimation + commercially licensed Indian data (FatSecret / Bon Happetee). The 🇮🇳 source badge stays; the data source changes. |
| D8 | Sign-up wall | **Refused — architecture.** Sakama is anonymous-first and offline-first (rule 1; shipped M3.1). Welcome slides are adopted; "Get Started" enters onboarding directly with no account, no email verification, no network. The account is offered later as "sync your data". Splash performs no token/network check. |
| D9 | "Hey Vita" wake word | **Deferred.** Always-on microphone in a health app is a store-review and trust risk. Voice mode activates by tap and long-press; wake word ships later behind a flag if demanded. |
| D10 | Family access levels | **Adapted.** The invite/manage UI is adopted; the permission model is the seven granular read scopes with write-never-default (ROADMAP M10), not a View/Full binary. |
| D11 | Admin screens | **Removed.** Web-only concern; not in the mobile app. |
| D12 | Live multi-source online food search | **Adapted.** Search reads the local bundled corpus + user foods + cached barcode results (offline-first). Barcode does the one live OFF lookup it does today. No parallel API fan-out. |
| D13 | Wearable calorie adjustment | **Adapted.** Adaptive weekly target recalculation (MacroFactor-style, transparent, user can override) plus an opt-in same-day activity adjustment toggle, default off. Burns are always shown; netting only happens when the user turned it on. |
| D14 | SparkyFitness | Reference for patterns only. Its licence is custom non-commercial: no code, markup, styles, or copy may be reused. |

Tags used below: **[BUILT]** exists today (survives v2) · **[PLANNED]** committed in
ROADMAP/CONTEXT · **[RECOMMENDED]** this spec's proposal · **[INFERRED]** unverified competitor
claim. Everything else is the adopted v2 design.

Follow-ups this pivot creates: DESIGN.md §0–§2 and PRODUCT.md design principle 5 describe the
retired visual system and the quiet-coach doctrine; both need a revision PR after this spec is
approved.

---

# 1. Product & UX Architecture

## 1.1 Structure

```
BOTTOM NAVIGATION (5 destinations)
[Home]   [Diary]   [+ LOG]   [Progress]   [Vita]

Home     = today: ring, meals, stats, Vita's observation, streak
Diary    = any day's full record: food, movement, water, sleep, mood, fasting, cycle
+ LOG    = universal quick-add: photo / voice / barcode / search / natural language
Progress = charts, trends, reports, exports
Vita     = the coach: chat, voice mode, history
Settings = behind the avatar (top-left of Home), not a tab
```

- The [+] is the visually dominant center action (56px circle, brand fill, elevated).
- **Contextual [+]**: on Diary it defaults to "add to the current meal slot"; on Progress it
  defaults to "log weight"; on Vita it opens voice mode.
- Every daily screen carries the **DateNavigator** (7-day strip, today centered); swiping the
  content area also moves days. [BUILT: nothing — this is new chrome.]

## 1.2 The reaction layer (pillar 2, engineered)

Two engines, one voice:

**The deterministic insight engine (no AI call, offline, free).** A local service reads Drift
streams and emits typed insights. Launch set:

| Insight | Trigger | Surfaces at |
|---|---|---|
| Gap-to-goal | any log event | Home suggestion card, food search rows |
| Streak state | day rollover / log | Streak card, morning push |
| Best-day / n-day-run | rollup crosses previous best | Home card, weekly narrative |
| Last-time context | opening an exercise | set grid header ("6 days ago · 60kg × 10") |
| Usual-portion recall | selecting a known food | portion prefill + "your usual" chip |
| Pace vs plan | mid-day thresholds | suggestion card ("on pace", "dinner budget: 620") |
| Recomposition verdict | weight + girth trends diverge | Progress, weekly narrative |

Rules: every insight names its data ("4 days in a row" is countable in Diary); insights never
scold; at most one suggestion card is visible on Home at a time; dismissing holds that insight
class for the day.

**The narrative engine (LLM, budgeted).** Turns the day's or week's typed insights into Vita's
voice: the morning nudge, the Sunday narrative, suggestion-card phrasing variants. Runs through
the existing gateway and budget; falls back to the deterministic template text when offline or
capped, so the reaction layer never goes dark.

## 1.3 Retention model

1. **Streaks without shame** — gap-day semantics (a missed day shows as a gap; logging the next
   day continues the count with "1 day gap" noted).
2. **Vita's daily nudge** — one morning push, generated from yesterday's real rows, opt-in at
   onboarding, one tap from settings to silence. Never a generic reminder.
3. **The 3-tap rule** — any core action within 3 taps of Home; regression is a design bug, and
   the flow specs in §17 carry the tap counts.
4. **Progress visibility** — Home always surfaces at least one true positive datum (the engine
   picks the best available: streak, protein run, sleep improvement).

## 1.4 Global patterns

Date navigation everywhere daily data shows · bottom sheets for all mobile modals (draggable,
snap 50/90%) · swipe-left on list rows = Delete/Edit, swipe-right = Duplicate/Favorite ·
pull-to-refresh on data screens (spins the logo; with local-first data it re-runs the insight
pass) · toasts above the nav bar, 3s success / 5s error-with-retry / 5s undo · haptics: light
(navigation), medium (log actions), heavy (destructive, set completion) · **stable kebab-case
`Semantics` identifiers on every interactive widget** [BUILT convention, retained] · unknown
values render blank, never zero [BUILT rule, retained — pillar 3].

---

# 2. Screen Map

```
AUTH-ADJACENT             S-001 Splash (offline-safe, no network gate)
                          S-002 Welcome (3 slides)         S-003/004 Sign in/up (OPTIONAL, from settings or "sync" prompts)
ONBOARDING                S-010 Personal → S-011 Body → S-012 Goal → S-013 Activity
                          S-014 Diet prefs → S-015 Notifications → S-016 Wearables (skip) → S-017 Done
HOME                      S-020 Home · S-021 Calorie detail sheet · S-022 Macro detail sheet
DIARY                     S-030 Diary · S-032 Daily summary sheet
FOOD                      S-040 Search · S-041 Food detail/add · S-042 Barcode · S-043 Snap camera
                          S-044 Snap results · S-045 Snap edit table · S-046/047 Custom food
                          S-048–050 Recipe create/detail/edit · S-051/052 Meal templates
                          S-053 Recent · S-054 Favorites · S-055 Meal gallery (opt-in)
WORKOUT                   S-060 Exercise library · S-061 Exercise detail · S-062 Active session
                          S-063 Set entry variants · S-064 Rest timer · S-065 Summary
                          S-066 History · S-067–069 Plans · S-070 Personal records
TRACKING                  S-080 Water · S-081 Weight · S-082 Measurements · S-083 Sleep
                          S-084 Mood · S-085 Fasting · S-086 Cycle · S-088 Check-in
PROGRESS                  S-090 Overview · S-091 Nutrition · S-092 Weight · S-093 Body comp
                          S-094 Workout · S-095 Sleep · S-096 Mood · S-097 Fasting · S-099 Export
VITA                      S-100 Chat · S-101 Voice mode · S-102 Action confirmation · S-103 History
SETTINGS (via avatar)     S-110 Main · S-111 Account · S-112 Goals · S-113 Diet · S-114 Notifications
                          S-115 Integrations · S-116 Family · S-117 Data & privacy · S-118 Appearance
                          S-119 AI settings/BYOK · S-120 Subscription · S-121 Help
SYSTEM                    S-141 Network error states (per-surface) · Update-required overlay [BUILT]
```

Migration note: shipped routes keep working during the rebuild; `/me` content redistributes into
S-110–S-121 (settings) and S-081/S-082 (weight and measurements move under Progress and
tracking). The kill-switch overlay, AI-consent sheet, BYOK, memory, and data-sources screens
carry over as they are [BUILT].

## Amendments from the owner's reference screenshots (2026-08-31)

Nine App Store screenshots were supplied mid-draft (a GLP-1 tracker's goals/insights screens, an
auto-tracking snap gallery, a voice-logging app, and the SparkyFitness mobile app's dashboard,
diary, search, food-edit, workout, and library screens). They are adopted as the visual bar.
Three additions they force:

- **D15 — Auto-Track (amends D6).** The snap-gallery app shows an "Auto-Track" toggle: meal
  photos are recognised and logged in the background. Adopted as an **explicit opt-in mode**
  inside the gallery: default off; enabling it shows a one-time disclosure (photos analysed,
  entries created automatically, budget usage); auto-created entries carry an "Auto-tracked"
  badge, land as Estimate provenance, and are one-tap reviewable from the gallery. Manual
  confirm remains the default path for everyone who does not flip the switch.
- **S-056 Library.** SparkyFitness's Library screen is adopted: a single management home for
  everything reusable — Create tiles (Food · Meal · Exercise · Preset), count rows (Foods 39 ›,
  Meals 5 ›, Exercises 16 ›, Workout presets 3 ›), and Recent. Reached from the [+] sheet
  ("Manage library") and from Settings. This closes the shipped app's missing-library gap.
- **The [+] sheet layout** follows the screenshot: a 2×2 tile grid (Food · Exercise ·
  Measurements · Barcode) plus a full-width row (Sync health data in theirs; **Ask Vita /
  natural-language input** in ours), with Photo and Voice tiles added above.
- **D16 — Voice-first Vita (owner ruling, 2026-08-31).** Vita is a voice-first AI agent AND
  chat: spoken replies via on-device TTS, barge-in interruption, spoken confirmation mapped to
  the visible confirm card (§8.1). Supersedes the earlier "Sakama listens; it does not talk"
  line. Backend contract: [SYSTEM-DESIGN-2.0.md](SYSTEM-DESIGN-2.0.md) §3.
- **Small adopted details** (verified from the full-resolution set): the header **streak chip**
  ("3 ⚡") beside the date on Home; the calories card variant "976 cal / 2,074 · 1,098 left"
  with a single bar (used on compact layouts); the macro card's **consumed/remaining swap
  toggle**; the Fiber cell as the fourth macro; a **Net carbs display mode** in goal settings;
  per-meal "N Cal" pill + chevron on Diary cards; named water containers with −/+ steppers;
  the dashboard Exercise card with Minutes and Calories bars; the recipe screen's "View all
  nutrients ›" link and footer share/delete round actions.

---

# 3. Home / Dashboard (S-020)

**Purpose:** the daily command centre. One screen answers "how is today going" and starts every
log in one tap.

## 3.1 Layout, top to bottom

```
HEADER        [Avatar]  Good morning, Priya        [🔔] 
              Monday, Aug 31
WEEK STRIP    S  M  T  W  T  F  S      ← checked circles for logged days,
              ✓  ✓  ✓  ○  ○  ○  ○        today ringed; tap a day = that day's view
CALORIE CARD  1,488          ⭘ 846          314
              Consumed    remaining of     Burned
                          2,020 kcal
MACRO CARD    Protein 130g/101g   Carbs 154g/227g
              Fat 45g/79g         Fiber 20g/28g     (colored mini bars)
MEAL CARDS    🌅 Breakfast   603 Cal   [Log]  →  items inline, tap to edit
              ☀ Lunch · 🌙 Dinner · 🍎 Snacks
INSIGHT CARD  Protein ›  "Aim for 1 serving above average today"
              This week's avg 74 g  ▂▄▂▆▁▁▁            (one at a time, dismissable)
QUICK STATS   [💧 Water] [👟 Steps] [🏋 Workout] [⚖ Weight]   (horizontal scroll)
STREAK CARD   12-day streak · 14-day dot strip (gap days hollow, never reset)
BOTTOM NAV    [Home] [Diary] [＋] [Progress] [Vita]
```

## 3.2 Component detail

**Header.** 40px avatar (initials fallback, brand fill) → Settings. Greeting is time-of-day +
first name; date line below in muted 13px. Right: notification bell with unread dot (opens the
notification centre sheet: nudges, weekly digests, sync notes).

**WeekStrip.** Seven 36px circles labelled S–S. Logged day = filled check circle; today = ringed
(filled once anything is logged); future = hollow muted. Tap switches the whole screen to that
day (content slides horizontally; DateNavigator semantics). A missed past day stays hollow: the
gap is visible, never red [pillar 3].

**CalorieRingCard.** The adopted tri-stat arrangement: left column "1,488 / Consumed", centre
120px ring with "846 / remaining / of 2,020 kcal", right column "314 / Burned". Ring fill brand
colour clockwise; over-budget flips fill and centre text to the warm over-tone with "Over by
N". Burned shows measured + computed burn; it reduces "remaining" only when the user enabled
activity adjustment (D13), and the card says so ("adjusted for activity") when it does. Tap →
S-021 calorie detail sheet (day timeline, per-meal split, the math). Ring animates on value
change (spring 400ms; instant under reduced motion).

**MacroCard.** 2×2 grid: Protein, Carbs, Fat, Fiber. Each cell = label + "130g / 101g" + 6px
mini bar in the macro identity colour. A swap icon toggles consumed/remaining mode (remembered).
Tap a cell → S-022 macro detail (7-day bars + top contributing foods).

**MealSectionCards.** One card per slot: icon + name + "603 Cal" pill + [Log] button; logged
items listed inline (name · portion · Cal, ConfidenceBadge retained [BUILT]); "View all" → Diary.
Empty slot: "Nothing logged yet" + the **"Same as yesterday"** ghost row when yesterday's slot
has entries. Swipe-left an item = Delete/Edit; swipe-right = Duplicate/Favorite.

**InsightCard.** The adopted anatomy from the screenshots: nutrient/topic label in its identity
colour + chevron, one bold insight sentence, "This week's avg" value, right-aligned 7-bar mini
chart. Content comes from the insight engine (§1.2); LLM phrasing when available, template text
otherwise. One card at a time; swipe-left dismisses for the day; tap → the relevant Progress
sub-tab. Positive framing rules apply ("Aim for 1 serving above average today", never "You
failed protein").

**QuickStatsRow.** Four 80px stat cards (water, steps, workout, weight): icon in identity
colour, bold value, label, thin progress arc. Blank value renders as "—" with a dashed border,
never 0. Tap → the module screen.

**StreakCard.** Count + "day streak" + 14-day dot strip. Gap semantics per D5: a gap shows as a
hollow dot and the count continues after one missed day with "1 day gap" noted; two or more
missed days restart the count but the history strip keeps the truth. Milestones (7/30/100) get a
one-second celebration, skipped under reduced motion.

**Vita is present, not resident.** The InsightCard is Vita's voice on Home. There is no chat
widget on Home; the Vita tab and the [+] sheet's natural-language row are one tap away.

# 4. Progress Tab & the Insight System

**Purpose:** the reaction layer's long-range half — pillar 3 made visible.

## 4.1 Structure (S-090)

Title "Progress" + export icon (S-099). Horizontal **sub-tab strip**, adopted from the
screenshots: `Overview · Calories · Nutrients · Macros · Weight · Steps · Workouts · Sleep ·
Mood · Fasting · Cycle` (modules with no data hide their tab). Date range pills below:
`7D · 30D · 90D · 1Y · Custom`.

## 4.2 Overview

A scrolling stack of **insight cards** (same anatomy as Home's) — one per active module, each
with the weekly mini-bar chart and one sentence; tap opens that sub-tab. Below: "Manage my
goals" link → S-112. Weekly Digest row at the bottom (the Sunday narrative, expandable, share
sheet export).

## 4.3 Sub-tabs

- **Calories:** daily bars vs target line; on-target band stat (85–105%; under-eating is not
  success [BUILT rule, retained]); best/worst day; most-logged foods top 5.
- **Nutrients:** the micronutrient panel — per-nutrient rows with min/max band bars (within
  band = quiet fill, outside = amber; never red/green moralising), tap for top contributing
  foods.
- **Macros:** stacked daily bars in identity colours + per-macro weekly averages.
- **Weight:** line chart + 7-day moving average + goal line (dashed) + linear trend; pinch to
  zoom; stats: start/current/goal, rate, projected date. **Recomposition card** when girth data
  diverges from scale data ("Weight flat, waist down — you are recomposing").
- **Workouts:** volume/week bars, PR list, per-exercise progression (from S-061 history).
- **Steps/Sleep/Mood/Fasting/Cycle:** per-module trend charts, blank-not-zero throughout.
- Every chart carries a text summary for screen readers.

# 5. Food Logging — Forensic Breakdown

## 5.1 Entry points (all ≤1 tap from Home)

1. [Log] on any meal card → S-040 preset to that slot.
2. [+] sheet → Food / Photo / Voice / Barcode tiles, or the natural-language row.
3. Diary meal section → add.
4. Vita chat → "log my breakfast" → confirm card.
5. Voice mode → parse → confirm.
6. Snap Gallery → Auto-Track (opt-in) or manual review.

## 5.2 The [+] universal sheet

Bottom sheet over the current tab: **natural-language input row** at top ("What did you do? —
'had dal rice', 'ran 30 min', '500ml water'"; routes to the right confirm surface via one text
AI call, degrades offline to plain search); 2×3 tile grid: Photo · Voice · Barcode · Food
(search) · Exercise · Measurements; full-width row: "Manage library" → S-056. Tiles show gate
states inline ("2 photo estimates left today").

## 5.3 Food Search (S-040)

- Header: close · "Add to Breakfast" · camera · mic icons. Search bar (48px, pill, auto-focus,
  300ms debounce, barcode icon when empty / clear when typing). Meal selector tabs under it.
- **Quick-access tabs:** Recent · Frequent · Favorites · My Foods · Meals. Recents grouped
  Today/Yesterday/This week; every row = 40px image-or-emoji circle, name, serving, kcal,
  **[+] one-tap re-log with last serving**; tap opens S-041.
- **Source filter chips** over results, adopted from the screenshot bar (`USDA · Fatsecret ·
  Yours · OFF · AI` — the licensed Indian source appears under its own brand chip; **no INDB**,
  D7). Chips filter the local corpus + cached OFF rows; every result row carries its source
  badge (🇮🇳 for the Indian corpus, per rule 7 provenance).
- Ranking: exact > starts-with > contains > fuzzy; user's own history boosted; verified above
  AI estimates. "Your usual" pinned suggestion when the query matches a habitual food
  ("Dal tadka — your usual, 1 katori, 180 kcal · one tap").
- No-match: "Create '[query]'" + "Ask Vita to estimate" (consent-gated; lands as `ai_estimate`
  with badge and assumptions snackbar [BUILT]).
- Natural-language queries ("bowl of dal with rice") produce an ✨ AI Estimate card at the top
  of results → opens the Snap-style edit table (S-045).

## 5.4 Food Detail / Add (S-041) — the adopted "full control" sheet

Draggable 90% sheet: drag handle → header (80px food image, name, brand/source badge, ♡
favorite, ⋮ report/share/edit) → **servings stepper row** `[−] 1.5 [+] cup ▾` with the
equivalence line "1.5 servings · 1 cup per serving ≈ 360g" (unit menu lists the food's own
units first — katori, roti, piece, glass — then g/ml; gram truth always visible and editable)
→ **nutrition card**: big kcal left, Protein/Carbs/Fat mini bars right, "Tap to edit
nutrition" (hand edits drop provenance to manual [BUILT rule]) → secondary rows: Fiber, Sugars,
Sat fat, Sodium → collapsible full panel (all stored nutrients, blank when unknown) → **Date**
and **Meal** dropdowns (backdating allowed; future denied) → context line from the insight
engine ("closes most of today's protein gap") → [Add to Breakfast] (52px, success tick, undo
toast 5s). Calorie number tweens on serving change.

## 5.5 Barcode (S-042)

Full camera, corner-bracket zone, torch, manual entry. Detect → freeze + haptic + the adopted
**result card**: product image/emoji + name; big "95 / Calories" left; nutrient column right
(Total fat, Sat fat, Cholesterol, Sodium, Total carbs, Fiber, Sugars, Protein); serving
stepper; meal selector; [Log it] + [Save food] (pointer into `off_foods` — the only place a
barcode food can be saved; ODbL attribution line on the card [BUILT containment, retained]).
Miss states: not-found → create-manual prefilled with the code; rate-limited; offline — each
with "Scan again". **Free forever** (§14 graveyard).

## 5.6 PhotoSnap (S-043–S-045)

Camera-first [BUILT] with additions: multi-photo (up to 6, thumbnail strip), optional
description and total-weight fields before Analyze. Results: photo banner, confidence badge,
total card, itemised list. **Edit table (S-045):** per row — editable name, qty stepper, unit,
auto kcal, "Match to database food" (mini search; matched rows get a verified tick and the
matched food's numbers), delete; add-item; sticky totals; [Log all] / [Log as single food].
Confirm-before-write always, except under Auto-Track (D15) where review is post-hoc via the
gallery.

## 5.7 Snap Gallery (S-055) + Auto-Track (D15)

Header "Snap Gallery" + **Auto-Track toggle**. Grid of date-grouped meal photo cards with
recognised names ("Kidney bean veggie rice & dal"); auto-tracked cards carry an ✨ Auto-tracked
badge; tap → full-screen viewer with macro overlay, edit (reopens S-045), delete. Enabling
Auto-Track: disclosure sheet (what is analysed, where photos live — per-user RLS storage,
budget note) with pinned accept/decline [pattern from BUILT consent sheet]. Filter chips: All /
per-slot / date ranges.

## 5.8 Recipes (S-048–S-050) — the adopted recipe screen

Create: name, servings stepper, photo, ingredient rows via mini-search (swipe-delete, drag
reorder), instructions, auto nutrition summary (per-serving + total; kcal-vs-macro consistency
check with auto-fix offer). Detail: header card (name, servings), Ingredients list with per-item
kcal, **Nutrition facts card** (big kcal tile + full column, "View all nutrients ›"), Recipe
notes, share and delete actions in the footer. Import from URL (Mealie/Tandoor-style parse)
[PLANNED P2].

## 5.9 Meals (templates) and the licence rule [BUILT, retained verbatim]

Meals group **saved foods only**, store ids + portions and zero nutrition; logging resolves
into `food_logs` and nowhere else; honest logged/skipped snackbar. Long-press a meal: Rename /
Edit / Delete. "Save day-slot as meal" from Diary. This containment is what keeps one-tap meals
legal; no v2 change may cache nutrition onto meal rows.

## 5.10 Library (S-056)

Title "Library". **Create** tile grid: Food (manual entry) · Meal (group foods) · Exercise
(manual) · Preset (workout routine). Count rows: Foods N › · Meals N › · Exercises N › ·
Workout presets N › — each opens a searchable managed list (edit, delete with
dependency-awareness: "used by 'usual breakfast'"). **Recent** section below. Reached from the
[+] sheet and Settings.

# 6. Workout Logging — Forensic Breakdown

## 6.1 Exercise library (S-060) and detail (S-061)

Search + muscle-group chips (All/Chest/Back/Shoulders/Arms/Legs/Core/Cardio/Stretching) +
equipment filter sheet. Rows: 48px illustration, name, muscle tags, equipment tag, [+ Add].
Detail sheet: muscle diagram (primary/secondary highlight), equipment + difficulty pills, tabs
Instructions / History (volume chart, session list) / Records (max weight, reps, volume, est.
1RM). Dataset must pass licence-guard before ingestion (free-exercise-db is public domain;
wger's data is not cleared) [GUARDRAIL].

## 6.2 Active session (S-062) — the adopted set-by-set screen

Header: editable workout name + date row + elapsed timer + Finish. Per-exercise card:
thumbnail, name, "strength · kg", **Rest · 1:30** chip (tap to edit), then the grid:

```
SET    PREVIOUS      KG      REPS    ✓
1      60 × 10      [60]    [10]    (✓)
2      60 × 10      [62.5]  [8]     ( )
+ Add Set
```

Ghost values from the last completed session (abandoned sessions ignored); tapping a ghost
copies it in. Set-number chip → type menu (Warm-up W / Drop D / Failure F; warm-ups excluded
from PRs; drops skip rest). ✓ = quiet fill + haptic + **rest timer** as a pinned bottom bar
(countdown, −15s/+15s, Skip; local notification if backgrounded). Numeric keyboards carry
+2.5/−2.5 and +1/−1 toolbars. Every keystroke persists to Drift; process death resumes the
session. In-session context line per exercise from the insight engine: "6 days ago · 60kg ×
10" (pillar 2).

## 6.3 Finish → Summary (S-065)

Confirmation ("End workout? 9 sets completed") → summary: duration, stats grid (sets, volume,
exercises, burn — blank when uncomputable [BUILT rule]), per-exercise best sets, **PR rows**
highlighted, notes, [Done]. A one-second celebration on PR days, skipped under reduced motion;
copy stays factual. Editable date for backdating.

## 6.4 History, presets, plans

History (S-066): calendar-dotted strip + week-grouped session cards → read-only detail with
Edit (no timers) and Repeat (prefilled, ghosts updated). Presets (S-067–069): built in Library
or by saving a finished session ("Save as preset"); Vita can draft presets via the confirm
card and never auto-starts one [BUILT contract].

# 7. Vita Chat (S-100)

Header: back · "Vita — AI Health Coach" · history · settings. **Context pill** under the
header: "Vita knows your last 28 days" — tap expands the exact context list (matches the Diary
window so the two never disagree [BUILT]). Conversation: date separators; Vita bubbles left
(surface, avatar, timestamp, markdown: bold/lists), user bubbles right (brand fill); streaming
text with stop control; typing dots while waiting.

**Rich cards in replies:** food suggestion (name, kcal, protein, [Log this]), workout draft
(exercise list, [Save preset] / [Start workout]), mini chart card, progress summary card.
Every [Log this]/[Start] routes through the **action confirmation card**: "Vita wants to: Log
'Paneer bhurji' (420 kcal) to Breakfast — [Confirm] [Cancel] [Edit]". Confirm executes through
the same repositories as manual entry (provenance `vita`, Estimate badge); Edit opens the
relevant sheet prefilled; bounds-checking precedes the card; multi-item drafts list every line
with per-line remove [BUILT contract + v2 additions].

**Suggested prompts** above the composer, time-aware (morning: "Log breakfast", "How did I
sleep?"; evening: "Summarize my day", "Plan tomorrow"). Composer: mic (→ S-101) · text field ·
attachment (photo, one vision call [BUILT]) · send. Errors: inline "Vita couldn't respond
right now [Retry]"; budget-exhausted keeps text chat alive when only photos are capped
[BUILT]; offline: transcript readable, send disabled with reason. Threads persist locally;
history sheet lists and deletes them [BUILT].

**Proactive surfaces** (D4): the Home InsightCard, in-search context lines, in-workout ghost
context, the morning push nudge (one per day, from yesterday's real rows, opt-in, silenced in
one tap), the Sunday Weekly Digest. Nothing else pushes.

# 8. Voice Interface (S-101)

Activation: mic in the [+] sheet, mic in chat, long-press on [+]. Full-screen overlay, dark
ground — the adopted layout: "Listening…" title + close; **live transcript line** at top;
centre 160px concentric pulsing circle with stop control (amplitude-reactive; static ring
under reduced motion).

States: Listening (recording starts on entry; auto-stop after 2s silence once speech exists) →
Processing (circle → spinner, transcript dims) → **Confirm** (the S-045 edit table for foods;
the standard confirm card for water/weight/workout) → logged. Errors: "Couldn't hear you —
Try again / Type instead"; parse and budget failures reuse the AI error taxonomy; mic
permission denied → explanation + Settings link. Recording never continues in background;
leaving cancels. On-device transcription; one text-parse AI call for foods [BUILT dictation
stack, promoted]. Supported grammar includes free speech ("I had one apple with two
tablespoons of peanut butter") with conversational follow-ups ("How many rotis?") rather than
command syntax. No wake word (D9 stands).

## 8.1 Voice-first Vita — the conversational mode (D16, owner ruling)

Vita is both a voice-first agent and chat; one Vita, one thread. Entered from the mic in Coach
or by long-pressing [+]. Adds two states to the overlay:

- **Speaking**: Vita's reply streams as text AND is spoken by on-device TTS; the pulse circle
  animates with output; a mute chip ("🔇 Voice off") sits below; captions always on.
- **Barge-in**: the mic stays open on voice-activity detection while Vita speaks; the user
  starting to talk stops TTS within ~100ms and begins the next turn. "Tap to interrupt" also
  works. The turn loop continues until 30s of silence or close.
- **Spoken confirmation**: when Vita proposes a write, the confirm card renders as always and
  Vita asks aloud ("Log 2 rotis and dal, about 320 calories?"). Saying "yes"/"haan" maps to
  the visible card's confirm; silence or "no" dismisses. **A spoken yes is a gesture on a
  visible card, never an invisible write** — the propose-confirm contract is unchanged.
- Voice sessions persist into the same chat thread; a conversation started by voice continues
  in text and back. Settings: "Vita speaks replies" (on in voice mode, off in text chat).
- Engineering contract and latency budget: SYSTEM-DESIGN-2.0.md §3 (on-device STT + fast-tier
  agent turn + on-device TTS ≈ under 2s perceived; no voice server in 2.0).

# 9. Secondary Tracking (S-080 — S-088)

One grammar: hero visual → quick actions → today's log → 7-day trend. All reachable from Diary
sections and Quick Stats; sleep/mood/fasting/cycle also collapse into a single **"Today's
check-in" card** on Diary for one-sheet multi-metric logging.

- **Water (S-080):** animated bottle/glass fill with % label; `+150 · +250 · +350 · +500 ·
  Custom` pills; named containers ("My bottle") switchable [pattern from screenshots]; per-entry
  history with undo; goal editable inline.
- **Weight (S-081):** big current number + trend line ("↓ 0.3kg this week" in ink, not
  status colour — direction is not universally good); 30-day chart with goal line; entry form
  (value, unit, date, notes); history with deltas.
- **Measurements (S-082):** site pills (Waist · Hip · Chest · Arm · Thigh · custom), per-site
  charts, progress photos (per-user RLS storage, comparison view), feeds the recomposition
  card.
- **Sleep (S-083):** duration hero + bedtime/wake pickers + 5-emoji quality + stages chart
  when a wearable provides one [PLANNED M9]; manual first.
- **Mood (S-084):** five glyphs (tap = instant log + undo), energy slider, tags, note; 7-day
  emoji timeline. Mood values carry no status colours.
- **Fasting (S-085):** dual ring (fasting arc + eating window), protocol pills (16:8 · 18:6 ·
  20:4 · custom), Start/End with confirmation, last-fast line, 7-day bars. **No metabolic-stage
  claims** — the timer shows time, not asserted ketosis [pillar 3].
- **Cycle (S-086):** monthly calendar (period fill, predicted outline, fertile window,
  ovulation dot), phase card with day-in-cycle, symptom logging sheet, settings. Ships dark
  behind `flag.cycle` until reviewed [PLANNED M8].
- **Check-in (S-088):** the multi-metric sheet: weight, water top-up, mood, sleep, note in one
  scroll, one save.

# 10. Settings (S-110 — S-121, via avatar)

Grouped list: **Account** (profile, Goals & targets — recalculation preview on change, Diet
preferences) · **App** (Notifications: per-module toggles with exact-behaviour subtitles;
Appearance: theme, units; Language) · **Integrations** (wearables per M9: connected list with
last-sync + available grid; Family per D10: members, seven permission chips, invite/revoke
with typed confirmation) · **AI** (Vita settings, AI & privacy [BUILT sheet retained], BYOK
[BUILT], memory [BUILT]) · **Data** (Data & privacy, Export, Data sources & licences [BUILT],
Delete account — red, typed confirmation) · **Support** (Help, Feedback, About). Subscription
(S-120) appears only when the Plus decision lands; cap states point at BYOK meanwhile
[BUILT].

# 11. Design System v2

## 11.1 Colour (D3)

```
Brand:      primary #0D7377 · light #14A085 · pale tint #E8F5F4
Semantic:   success #4CAF50 · warning #FF9800 · error #F44336 · info #2196F3
Macros:     protein #4CAF50 · carbs #FF9800 · fat #9C27B0 · fiber #795548
            water #2196F3 · sugar #E91E63 · sodium #607D8B
Light:      bg #F5F7FA · surface #FFFFFF · border #E8ECF0
            text #1A1D23 / #6B7280 / #9CA3AF
Dark:       bg #0F1117 · surface #1A1D23 · elevated #242830 · border #2D3139
            text #F9FAFB / #9CA3AF / #6B7280
```

Dark-mode macro/semantic tones get lifted variants tuned for AA on dark surfaces; every
pairing is contrast-tested in `theme_test.dart` (the test survives the repaint). "Over budget"
uses the warning orange, not error red; error red is reserved for destructive actions and
failures.

## 11.2 Type

**Inter** (bundled — offline-first applies to typography) + **Noto Sans Devanagari** fallback.
Scale: Display 36/700/−0.5 · H1 28/700 · H2 22/600 · H3 18/600 · Body 16 and 14/400/1.5 ·
Caption 11 · Metric 48/700/−1. Tabular figures on every aligned number (kcal columns, timers,
set grids).

## 11.3 Space, shape, elevation

4px base scale (4/8/12/16/24/32/48). Page padding 16. Cards radius 16 (12 compact), shadow
`0 2px 8px rgba(0,0,0,.06)`. Buttons 52px/radius 12 (primary filled, outlined, ghost,
destructive; 36px small). Inputs 52px/radius 12, floating labels; search pill 48px/radius 24.
Bottom nav 56px + safe area; [+] 56px circle, elevated. Bottom sheets radius 20 top, drag
handle, snap 50/90%.

## 11.4 Components

Ring (120/80/48px, spring), linear bars (4/6/8px, pill), the tri-stat calorie card, MacroCard
cells, InsightCard, WeekStrip, StreakCard, stat cards, meal cards, food rows, source chips,
serving stepper, set grid + rest bar, confirm card, voice overlay, skeleton shimmer (1.5s), 
toasts (success 3s / error 5s + retry / undo 5s), empty-state illustration blocks. Icons:
Lucide-style outlined, filled variant for active tab; 16/20/24/32/48 sizes. ✨ reserved for AI
provenance; ✓ verified provenance [BUILT semantics retained].

## 11.5 Motion

Push/pop slide 300ms; sheets spring 350ms; tab cross-fade 200ms. Ring spring 400ms; bar width
250ms; counter count-up 500ms; set-check pop 200ms + haptic; card press scale .98. Vita text
streams. Celebrations: single 1s confetti burst at streak milestones, onboarding complete, PR
workouts — **never on ordinary logs**, always skipped under reduced motion. Every animation
checks `disableAnimations`.

# 12. States & Micro-interactions

Skeleton shimmer for anything network-bound (AI, OFF lookup, sync-dependent charts); local
Drift reads render synchronously and never skeleton. Empty states: 80px illustration + heading
+ one line + one CTA (each module's empty state is its teach state). Errors: specific, plain,
one helpful action; offline note on network errors says "You can still log — it syncs later."
Undo on every delete and every log (5s). Confirmation dialogs only for irreversible things
(entry remove, meal/preset/plan delete, memory forget-all, family revoke, end-workout).
Haptics: light/medium/heavy per §1.4; success double-tap on logged food and finished workout.
Pull-to-refresh spins the logo and re-runs the insight pass. Offline: per-surface states +
a quiet yellow banner only when sync has been pending >24h.

# 13. Responsive

Breakpoints: ≤479 phone (single column, bottom nav, sheets) · 768–1023 tablet (collapsible
240px side nav, two-column diary, centred modals 480px, 14-day strip, search+detail split) ·
≥1024 desktop (fixed sidebar, 800px content column, 320px detail panel, hover states,
shortcuts: N log food · W workout · V Vita · / search · Esc close). The M11 React web client
implements the ≥768 projections; phone stays the design target.

# 14. Guardrails (non-negotiable, unchanged by the redesign)

1. **Licence:** no INDB ever (D7); OFF rows contained + attributed [BUILT]; meals carry no
   nutrition [BUILT]; food rows keep `source`/`licence`/`confidence`; licence-guard before any
   new dataset (exercises included); SparkyFitness is patterns-only (D14).
2. **AI safety:** consent sheet before first transmission; confirm-before-write everywhere
   except explicit Auto-Track opt-in (D15); bounds-checks before cards; budget caps surface
   honestly and text chat survives photo exhaustion; BYOK keys never leave the device
   [all BUILT].
3. **Honesty:** blank over zero; burns shown, netted only by opt-in (D13); confidence badges
   keep their semantics (verified / estimate / none for saved+meal) [BUILT]; copy never
   scolds.
4. **Offline-first:** every daily-loop surface reads Drift; no login wall (D8); sync
   reconciles silently.
5. **Mobile realities:** kill switches + min-version gate stay [BUILT]; new risky surfaces
   ship dark behind `flag.*`; migration tests per schema change; stable `Semantics`
   identifiers on every interactive widget.

# 15. Migration & Build Order

**Phase A — the reaction layer on the shipped app (fastest felt change):** deterministic
insight engine + InsightCard + in-search/in-workout context lines · WeekStrip · CalorieRing
card (tri-stat) + MacroCard on the current Home · streak card · undo toasts everywhere.
**Phase B — logging completeness:** [+] universal sheet with natural-language row · voice mode
· capture-time serving stepper · source chips · Library · recipes · copy-yesterday · swipe
actions.
**Phase C — the redesign proper:** new palette/type applied through the token layer · new IA
(Progress tab, settings behind avatar, Diary sections for all modules) · workout UI · gallery
+ Auto-Track · secondary modules (sleep, mood, fasting; cycle dark) · date navigator.
**Phase D — reach:** morning nudge + Weekly Digest · wearables (M9) · family (M10, gated) ·
web client (M11) · localisation (M12).
Each phase leaves the app shippable; Drift schema changes ride the four-file sync contract
with migration tests [CLAUDE.md].

# 16. Key User Flows (tap-counted)

1. **Onboard:** Welcome (3 slides) → 7 steps → plan reveal → Home. No account, no paywall,
   works in airplane mode.
2. **Log breakfast by search (5 actions):** [Log] on Breakfast → type "poha" → tap result →
   adjust stepper → Add. Toast + ring updates + insight reacts ("protein gap −12g").
3. **Photo (3 actions + confirm):** [+] → Photo → shoot → review table → Log all.
4. **Voice (2 actions + confirm):** [+] → Voice → speak → auto-stop → confirm table → done.
5. **Barcode (4 actions):** [+] → Barcode → aim → Log it.
6. **Repeat meal (2 actions):** [Log] → meal pill. **Yesterday (1):** ghost row tap.
7. **Natural language (2 + confirm):** [+] → type "dal chawal and 30 min walk" → two confirm
   cards → confirm both.
8. **Workout:** Home stat card → preset → session (ghost values, checkmarks, rest bar) →
   Finish → summary with PRs → Diary + burn update. Kill the app mid-session → reopen →
   resumed.
9. **Ask Vita to act:** "log 2 rotis and dal for lunch" → action card → Confirm → logged with
   `vita` provenance.
10. **Offline day:** everything logs from local data; AI tiles disabled with reason; scan says
    offline; reconnect syncs silently.
(The full 22-flow inventory from v1 remains valid where it does not conflict; conflicts
resolve in favour of this section.)

# 17. Implementation Notes

- **Feature-first Flutter** [BUILT convention]. New: `lib/core/insights/` (the engine: pure
  functions over Drift streams, exhaustively unit-tested; INSIGHT types as sealed classes),
  `features/{progress,workouts,voice,library,gallery,fasting,sleep,mood,cycle,family}`.
- **Theme as tokens:** the v2 palette lands in one `theme.dart` rewrite + golden tests in both
  modes at 1.0/1.35 text scale; contrast assertions extended to the new tones.
- **Riverpod:** date-keyed `diaryProvider.family`, `activeWorkoutProvider` (Drift-persisted
  state machine), `insightProvider` (recomputes on any log stream event), `voiceFlowProvider`
  (sealed states), delegate `activeProfileProvider` for M10.
- **Charts:** fl_chart; per-chart semantic text summaries.
- **Sync:** every new table rides the four-files-and-one-line contract (Drift + bump +
  preservation test · powersync_schema · SQL + RLS + `alter publication powersync add table`
  block · sync-streams.yaml; migration first, sync rules second) [CLAUDE.md].
- **Performance floors:** cold start < 2s on iOS 15 hardware; 60fps Home scroll; ring/insight
  recompute off the UI thread; wakelock only in-session and opt-in.
- **Accessibility:** WCAG 2.1 AA; 44px targets (52 primary); Dynamic Type to 1.35× minimum;
  focus-visible everywhere on web; announcements for errors and confirmations; Indian number
  formatting (1,00,000) and ₹ where money appears.

## Appendix — provenance

Research base: SparkyFitness teardown (patterns only, custom non-commercial licence), eleven
competitor studies with cited primary sources (v1 §11 of this document's history holds the
full sourced comparison), the shipped-app inventory @ `bfe689f`, and the owner's reference
screenshots (2026-08-31). Claims from competitor marketing are treated as [INFERRED] unless
independently verified.

*End of specification v2.*
