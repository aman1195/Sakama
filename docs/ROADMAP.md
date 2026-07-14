# Sakama — Build Roadmap

> Scope is "everything in the vision." That is a multi-month build, so it is sequenced into milestones
> that each leave the app in a shippable, dogfoodable state. Do **not** build breadth-first (many
> half-finished features); build milestone-by-milestone.

## Sequencing principle

Foundation → daily-usable core → the AI moat → the plan engine → sensors/health → polish & launch.
Each milestone is independently testable end-to-end.

---

## M0 — Foundation (no features yet, but everything after depends on it)
- Install Flutter + CocoaPods (⚠️ ~1GB SDK download — needs user go-ahead; see README §Setup).
- Scaffold Flutter app: feature-first structure, Riverpod, go_router, theme, env config.
- Supabase project: Postgres schema + RLS ([architecture/01-data-model.md](architecture/01-data-model.md)), auth (email +
  Apple + Google), storage bucket, migrations under `supabase/migrations/`.
- Drift local schema mirroring Postgres; PowerSync wired for the log→sync→pull loop.
- CI: build + test on PR.
- **Exit test:** sign in, write a row offline, see it sync to Supabase and back to a second device.

## M1 — Onboarding + profile + tracking core (the daily-usable app)
- Onboarding flow (goal → profile → diet → conditions → cuisine → activity).
- Default target computation (Mifflin–St Jeor) for Type 3 / no-plan users.
- Dashboard: today's calories/macros vs. targets, ring/summary.
- Manual food logging via **food search** over the seed DB; `food_logs` + `diary_days` rollup.
- Water tracker, weight logging + weight chart.
- **Exit test:** a Type 3 user onboards and logs a full day; totals and chart are correct offline.

## M2 — Food database v1
- Build + ship the curated seed DB (~300–800 dishes) via the pipeline in
  [architecture/03-food-database.md](architecture/03-food-database.md).
- Ship the filtered Indian OFF snapshot (source-tagged) + local search.
- Barcode scanning (`mobile_scanner`) → local snapshot → live OFF fallback + cache + attribution.
- Custom meals / favorites / quick templates.
- **Exit test:** search finds Indian dishes offline; a real barcode resolves and logs correctly.

## M3 — The AI moat
- Stand up the **LiteLLM proxy** + Supabase Edge Function BFF ([architecture/02-ai-layer.md](architecture/02-ai-layer.md)).
- **PhotoSnap**: photo → structured food items → confirm → log. Run the Indian-food portion eval
  first; wire confidence + user correction capture.
- **Vita coach**: context assembly + streaming chat + history persistence + prompt caching.
- **AI food estimation** for gaps, confidence-scored, with promotion queue.
- Virtual-key budgets + rate limits enforced (free-tier cost bound).
- **Exit test:** photograph a thali → reasonable items/macros; ask Vita a plan-aware question and get
  a specific answer; usage is metered and capped.

## M4 — Plan engine (Type 1 + Type 2)
- Plan JSON interpreter ([architecture/04-plan-engine.md](architecture/04-plan-engine.md)): resolve day type, targets,
  fasting window, allowed/blocked foods, rules, checklist.
- **AI plan generation** from onboarding (Type 2); schema-validated → `user_plans`.
- **Plan import** (paste text / upload document) normalized to Plan JSON (Type 1).
- Enforcement surfaces: checklist, eating-window warnings, day-type banner, Vita reads plan context.
- **Exit test:** generate a 7-day plan; a "Tuesday reset" day changes targets/checklist and Vita
  references it; an imported custom plan enforces its eating window.

## M5 — Fasting, workouts, sensors
- IF fasting timer + eating-window enforcement (`fasting_sessions`).
- Workout logging + calorie-target adjustment.
- Step counter (`pedometer`) + `step_days`.
- Sleep manual logging; optional HealthKit read/write via `health` (steps/sleep) with minimal scopes.
- **Exit test:** a fast runs and completes; a workout raises the day's calorie target; steps and a
  sleep entry appear and sync.

## M6 — Voice logging, micronutrient panel, polish
- Voice food logging (speech → text → AI parse → log).
- Micronutrient panel view (iron/calcium/vitamins) from `micros`.
- Streaks, weekly progress, gentle nudges (Type 3 coaching).
- Accessibility, localization scaffold (Hindi first), empty/error states, performance pass.

## M7 — Launch hardening
- Security review (RLS coverage, key handling/redaction, storage policies, OWASP M1).
- **Licensing clearances** finalized (NIN, Anuvaad) and attributions in-app ([04](architecture/03-food-database.md)).
- Privacy policy, App Store / Play data-safety disclosures, ATT if applicable.
- Beta (TestFlight / Play internal) → fix → store submission (iOS first, Android close behind).

---

## Cross-cutting, every milestone
- Offline-first: every feature reads local Drift first and syncs.
- RLS on every new table; tests for provider overrides + in-memory Drift + the sync loop.
- Keep `source/license/confidence` on all food data; keep OFF data source-tagged and contained.
- AI cost discipline: cheap default + escalation, prompt caching, per-user budgets.

## Known decisions still to make (tracked, not blocking M0–M2)
- Concrete vision model after the Indian-food eval.
- Hosting for the LiteLLM proxy (Fly.io vs. small VM vs. Cloud Run).
- Analytics/crash tool that is privacy-respecting (no health PII).
- Whether to adopt melos (multi-package) — defer until feature count justifies it.
