# Sakama — Product Specification

> Free, AI-powered personal health and nutrition OS for Indian users.
> Free forever. No ads. No data selling. Better AI than HealthifyMe. Built for India.

This document is the product source of truth. Technical documents (`01`–`05`) reference the
features and user model defined here.

---

## 1. Vision

Sakama is not a prototype or internal tool. It is a real consumer product intended for the
App Store and Play Store. Every decision (architecture, UX, performance, extensibility) is made
for a shipping product.

It must work equally well for:

- a diabetic housewife in Chennai,
- a gym-going 22-year-old in Delhi,
- a 45-year-old executive managing fatty liver in Bengaluru.

The wedge versus HealthifyMe is the **AI coaching layer**. Modern LLMs are far more capable than
the models most health apps run, so a coach that knows the user's exact plan, today's logs, streak
data, and weekly progress can give hyper-specific guidance that generic coaches cannot.

**Core promise to users:** Free forever. No ads. No data selling. Better AI than HealthifyMe.
Built for India.

---

## 2. The three user types

The product must serve three distinct users. Every feature is evaluated against all three.

| Type | Who | Core need |
|---|---|---|
| **Type 1 — Plan followers** | Has a specific plan (custom meal plan, fasting window, weekly reset day, detox protocol) | App must **enforce and track** the plan faithfully |
| **Type 2 — Goal setters** | Says "lose 10 kg" / "improve liver health" / "build muscle" | App **generates** a plan via AI, then tracks it |
| **Type 3 — Casual trackers** | Just wants to log food, see macros, get nudges | Low-friction logging + **gentle coaching**, no rigid plan |

HealthifyMe serves all three but charges heavily. Sakama serves all three for free and does the
AI layer better.

---

## 3. Feature inventory

### 3.1 Tracking core
- Calorie tracking
- Macro tracking (protein / carbohydrate / fat / fiber)
- Micronutrient panel (iron, calcium, key vitamins, sodium, etc.)
- Water tracker
- Intermittent-fasting timer (eating-window enforcement)
- Weight chart (trend over time)
- Workout logging (type, duration, calories burned) with calorie-target adjustment
- Step counter (device pedometer)
- Sleep logging (manual for v1; HealthKit/Apple Health in a later phase)

### 3.2 Food logging (multi-modal — kill the friction of manual entry)
- **PhotoSnap** — photograph a meal; LLM vision identifies all foods, estimates Indian portion
  sizes, returns macro + micro breakdown. Highest-impact feature.
- Voice logging
- Text logging
- Barcode scanner (Open Food Facts lookup)
- Quick templates / custom meals
- Food search over the Indian food database

### 3.3 AI layer
- **Vita** — LLM coach that knows the user's plan, today's logs, streaks, and weekly progress, and
  gives hyper-specific, Indian-context-aware advice. (Name is a placeholder: Vita / Veda / nameless.)
- **Personalized plan generation** — from goals, food preferences, dietary restriction, health
  conditions, and cuisine preference, the LLM produces a 7-day plan in seconds, for free.
- **AI food estimation** — when a food is not in the database, the LLM estimates its nutrition.

### 3.4 Plan layer (flexible, never hardcoded)
Plans are stored as **JSON config in the database**, not hardcoded in the app. See
[architecture/01-data-model.md](architecture/01-data-model.md) for the schema. Each plan defines:
- day types,
- calorie targets per day type,
- allowed foods per day type,
- fasting window,
- checklist items,
- special rules (e.g. "Tuesday reset", detox protocol).

A 4-week plan is one config. A diabetic-friendly plan is another. A muscle-gain plan is another.
The LLM can generate new plan configs on demand. Users can also import a custom plan via text or
document upload.

### 3.5 Onboarding flow
1. Goal selection — lose weight / detox / build muscle / manage condition / just track
2. Basic profile — age, weight, height, gender
3. Dietary preference — veg / non-veg / vegan / eggetarian
4. Health conditions (optional) — diabetes, thyroid, liver, PCOD, etc.
5. Cuisine preference — North Indian / South Indian / both / other
6. Activity level
7. → LLM generates a personalized 7-day plan instantly
8. → User can alternatively import a custom plan via text or document upload

---

## 4. Explicitly out of scope

Copied here so we never drift into building them:
- Paid nutritionist coaching (Vita replaces it, free)
- GLP-1 medication program (HealthifyRx equivalent)
- Physical gyms ("Healthify Centres")
- Any premium wall that locks **basic** features

Monetization, if ever, must never touch the core promise (free core, no ads, no data selling).

---

## 5. Product principles (decision filters)

1. **Free at the core.** Core tracking + AI basics never sit behind a wall.
2. **Privacy-first.** No data selling; health data is sensitive and treated as such. Drives the
   backend choice (self-hostable Supabase) and BYOK option for AI.
3. **India-first.** Indian foods, portion units (katori, roti, idli), cuisines, and conditions
   (PCOD, thyroid, fatty liver, diabetes) are first-class, not afterthoughts.
4. **Friction is the enemy.** PhotoSnap / voice / barcode exist so logging takes seconds.
5. **AI is the moat.** The coaching, plan generation, and estimation quality is what beats
   HealthifyMe. Invest there.
6. **Offline-tolerant.** Logging must work on a train with no signal; sync reconciles later.
7. **Everything for everyone.** The flexible JSON plan engine means the app fits any protocol, not
   just one hardcoded program.

---

## 6. How the pieces connect (one-paragraph mental model)

A user onboards and either brings a plan (Type 1), asks AI to generate one (Type 2), or skips
planning (Type 3). Every day they log food (photo/voice/text/barcode/search), water, workouts,
weight, steps, and sleep. Logs roll up into calorie/macro/micro totals compared against the day's
targets (from the active plan or a computed default). Vita reads all of this — plan, today's logs,
streaks, weekly trend — and coaches specifically. Data lives locally first for instant, offline use
and syncs to Supabase for backup and multi-device continuity.
