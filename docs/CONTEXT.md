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
- a 45-year-old executive managing fatty liver in Bengaluru,
- a mother in Mumbai running her own, her husband's and her teenager's profiles,
- a software engineer in Berlin who will not put health data on someone else's server,
- a developer pointing their own LLM client at their data over MCP.

The wedge versus HealthifyMe is the **AI coaching layer**. Modern LLMs are far more capable than
the models most health apps run, so a coach that knows the user's exact plan, today's logs, streak
data, wearable recovery, mood trend and weekly progress can give hyper-specific guidance that
generic coaches cannot.

The second wedge, added by the 2.0 vision, is **deployment**. Sakama runs on managed cloud for
people who want zero setup and on their own Docker or Kubernetes for people who want their health
data on their own hardware ([ADR 0017](adr/0017-dual-deployment-cloud-and-self-hosted.md)). No
commercial competitor offers this; no self-hosted platform has the AI layer or the Indian food
database.

**Core promise to users:** Free forever. No ads. No data selling. Better AI than HealthifyMe.
Built for India. Open to the world.

---

## 2. The six user types

The product must serve six distinct users. Every feature is evaluated against all six. A feature
that serves one type at the expense of another is not acceptable.

Types 1–3 are the Indian mobile market and the reason the food database exists. Types 4–6 arrived
with the 2.0 vision and are what separate Sakama from every commercial competitor.

| Type | Who | Core need |
|---|---|---|
| **Type 1 — Plan followers** | Has a specific plan (custom meal plan, fasting window, weekly reset day, detox protocol) | App must **enforce and track** the plan faithfully |
| **Type 2 — Goal setters** | Says "lose 10 kg" / "improve liver health" / "build muscle" | App **generates** a plan via AI, then tracks it |
| **Type 3 — Casual trackers** | Just wants to log food, see macros, get nudges | Low-friction logging + **gentle coaching**, no rigid plan |
| **Type 4 — Family health managers** | A parent or household lead running health goals for themselves and their family | Multi-profile with **granular permissions**, family dashboard, Vita that can answer about any member they may view |
| **Type 5 — Privacy-conscious self-hosters** | Runs Nextcloud or Home Assistant already; will not put health data on someone else's server | Docker Compose or Helm, **full sovereignty over their own health data**, no cloud dependency for tracking |
| **Type 6 — Developers and integrators** | Wants to build on the platform or point their own LLM client at their data | Documented API, **MCP server**, stable contracts |

Concretely: a diabetic housewife in Chennai, a gym-going 22-year-old in Delhi, a 45-year-old
executive managing fatty liver in Bengaluru, a mother in Mumbai running three profiles, a software
engineer in Berlin with a homelab, a developer building a daily-briefing agent.

HealthifyMe serves Types 1–3 and charges heavily. It has no answer at all for 4–6.

**One boundary, stated up front.** The sovereignty promise in Type 5 covers *the user's health
data*. It does not extend to *our curated Indian reference data*, which reaches self-hosted
instances over an authenticated lookup rather than seeded into the container — see
[ADR 0017](adr/0017-dual-deployment-cloud-and-self-hosted.md). Shipping the moat inside a
redistributable image would give it away.

---

## 3. Feature inventory

### 3.1 Tracking modules (twelve)

Every module writes to local Drift first and syncs in the background. All twelve must be fully
usable with no connection.

| Module | What it holds | Priority |
|---|---|---|
| **Nutrition** | Calories, macros (protein/carb/fat/fibre), micronutrients (iron, calcium, key vitamins, sodium), per meal and per day | P0 |
| **Exercise** | Type, duration, sets, reps, weight, calories burned. Custom exercises. Adjusts the calorie target | P0 |
| **Hydration** | Water with quick-add amounts, daily target, optional reminders | P0 |
| **Sleep** | Manual entry in v1; HealthKit and Health Connect later. Duration, quality, stages from wearables | P0 |
| **Fasting** | Timer with 16:8 / 18:6 / 24h and custom windows. History and streaks. Eating-window enforcement for Type 1 | P0 |
| **Weight and body measurements** | Weight trend, body fat, custom sites (waist, hips, arms, chest, thighs), goal marker, optional progress photos | P0 |
| **Steps** | Device pedometer or manual, daily goal, wearable sync | P0 |
| **Mood** | Daily 1–5 check-in with notes. Trend charts. Correlation against sleep and nutrition | P1 |
| **Cycle** | Period, ovulation, symptoms. Phase awareness feeds nutrition guidance and Vita | P1 |
| **Goals and check-ins** | Per-module daily and weekly goals, one daily check-in flow, completion streaks | P1 |
| **Long-term reports** | Custom date ranges, cross-module correlation, CSV export, full history with no paywall | P1 |
| **Family dashboard** | Household view with permission, family goals, shared household meal logging | P2 |

**Calories burned are computed, never asked of a model.** Exercise energy comes from the MET
formula against the user's most recent body weight, and is null — never 0 — when it cannot be
computed. The number is subtracted from the day's target, so a guessed one changes what somebody
eats. See `app/lib/features/workouts/domain/energy_burn.dart`.

### 3.2 Food logging (multi-modal — kill the friction of manual entry)
- **PhotoSnap** — photograph a meal; LLM vision identifies all foods, estimates Indian portion
  sizes, returns macro + micro breakdown. Highest-impact feature.
- Voice logging
- Text logging
- Barcode scanner (Open Food Facts lookup)
- Quick templates / custom meals
- Food search over the Indian food database
- **Chat logging** — food, water, weight and exercise through Vita, as an alternative to the
  structured screens. Natural language in, a confirm card out: *"I did 3 sets of 10 bench press at
  80kg"* becomes a workout entry the user taps to accept
- Recipe import from a connected Mealie or Tandoor instance (P2)

### 3.3 AI layer
- **Vita** — LLM coach that knows the user's plan, today's logs, streaks, and weekly progress, and
  gives hyper-specific, Indian-context-aware advice. (Name is a placeholder: Vita / Veda / nameless.)
- **Personalized plan generation** — from goals, food preferences, dietary restriction, health
  conditions, and cuisine preference, the LLM produces a 7-day plan in seconds, for free.
- **AI food estimation** — when a food is not in the database, the LLM estimates its nutrition.
- **Progress review** — "how many calories did I average this week?" and "show me my weight trend
  for the last month" are answered from real rows, not impressions.
- **Mood-, cycle- and wearable-aware coaching** — Vita reads the mood trend, the cycle phase, and
  HRV/sleep/body-battery from a connected wearable, and factors recovery into what it suggests.
- **Family coaching** — Vita can answer about any family member the asker has permission to view,
  and no others.

Vita **proposes; it never writes**. Every tool call is bounds-checked before it can become a
draft, and the user taps to confirm ([ADR 0016](adr/0016-vita-as-assistant.md)). An absurd value
must never reach the confirm card, because propose-confirm guards intent and not magnitude.

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

### 3.6 Integrations

Ten wearable and health platforms, each with background sync, OAuth refresh, rate-limit handling
and graceful degradation when a provider breaks: Apple Health, Google Health Connect, Google
Health API, Fitbit, Garmin (its own microservice), Withings, Polar, Oura, Strava, Hevy.

A broken integration must degrade to "not syncing, here is why" and never to silently stale data
presented as current.

### 3.7 MCP server

Exposes health data and actions to external LLM clients (Claude Desktop, Cursor, custom agents)
for Type 6. Read: today's nutrition, weekly and monthly summaries, weight and measurements, sleep
and HRV, steps and workouts, the active plan, the food database. Write: food, water, weight.

Writes authenticate and pass through **the same RLS policies as everything else**. The MCP server
is another client, never a bypass.

### 3.8 Family and multi-user

Seven granular permissions: nutrition, exercise, measurements, sleep, mood, cycle, and full read.
**Write access is never granted by default** and must be explicitly enabled. Invitation by email;
the invitee creates their own account. The owner can revoke at any time.

This is the highest-consequence feature in the product. A permission bug here leaks one person's
health data to another person who knows them. It stays behind an RLS audit and cross-user
integration tests before it ships.

### 3.9 Authentication

Email and password, Apple, Google, OIDC (Authentik / Keycloak / Auth0), TOTP, Passkey, and
instance-level MFA enforcement. All configurable by environment variable, no code change.

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
   BYOK option for AI and the self-hosted deployment. Data sovereignty is a feature, not a
   footnote — a self-hosted instance gets the same features as a cloud one, not a degraded
   version.
3. **India-first.** Indian foods, portion units (katori, roti, idli), cuisines, and conditions
   (PCOD, thyroid, fatty liver, diabetes) are first-class, not afterthoughts.
4. **Friction is the enemy.** PhotoSnap / voice / barcode exist so logging takes seconds.
5. **AI is the moat.** The coaching, plan generation, and estimation quality is what beats
   HealthifyMe. Invest there.
6. **Offline-tolerant.** Logging must work on a train with no signal; sync reconciles later.
7. **Everything for everyone.** The flexible JSON plan engine means the app fits any protocol, not
   just one hardcoded program.
8. **The household, not just the individual.** Family sharing, household meal logging and
   family-aware coaching are core, not add-ons.
9. **Never invent a number.** An unknown value stays null and renders as blank. A stored 0 reads
   as a measurement somebody took. This binds hardest where a number feeds a target the user then
   eats against.

---

## 6. How the pieces connect (one-paragraph mental model)

A user onboards and either brings a plan (Type 1), asks AI to generate one (Type 2), or skips
planning (Type 3). Every day they open to today's dashboard — calories remaining, macros, water,
steps, and the fasting timer if one is running — log meals as they eat, log a workout, and finish
with the daily check-in. Logging happens through the structured screens or through Vita, whichever
is closer to hand. Logs roll up into calorie/macro/micro totals against the day's targets (from
the active plan or a computed default). Vita reads all of it — plan, today's logs, streaks,
wearable recovery, mood, cycle phase, weekly trend — and coaches specifically. Data lives locally
first for instant offline use and syncs to Postgres, whether that Postgres is ours or theirs. A
family manager (Type 4) sees the same for anyone who has granted them permission. A developer
(Type 6) reaches the same data over MCP, through the same RLS.

**The daily loop, in order:** dashboard → log meals → log a workout → daily check-in. Every step
must be reachable with minimal navigation, and chat sits in the main navigation as a peer to the
structured screens rather than a novelty tucked behind a menu.
