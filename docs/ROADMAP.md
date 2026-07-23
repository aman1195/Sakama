# Sakama — Build Roadmap

> **Revised after the 2026-07 grilling session** (see [adr/README.md](adr/README.md), ADRs 0009–0013).
> The north star is still the full vision, but **v1 is a wedge: Phase 0 → M3.** Build
> milestone-by-milestone; never breadth-first. Each milestone leaves the app shippable and dogfoodable.

## Sequencing principle

**Prove the moat → foundation → daily-usable core → the moat itself → LAUNCH → fast-follow the rest.**

The v1 launch line is drawn **after M3**, not M7. M4–M7 ship to users who are already on the app.

```
Phase 0   M0          M1            M2           M3          │  M4        M5         M6        M7
validate  foundation  tracking      food DB      AI moat     │  plan      sensors    polish    hardening
PhotoSnap             core                       (LAUNCH ►)  │  engine
└──────────────── v1 (wedge) ──────────────────────────────┘   └──── fast-follow (v1.1+) ────┘
```

---

## Phase 0 — Validate PhotoSnap (before any app code) · [ADR 0013](adr/0013-validate-photosnap-before-build.md)
The whole thesis rests on "a VLM estimates an Indian meal's macros usefully." Test that in a day, with
**no app** — just API calls.
- 20–30 photos of real Indian meals, each with a best-estimate "true" macro figure.
- Run 2–3 VLMs (Gemini Flash, Claude, optionally GPT) with the **ported Fud AI prompt**
  ([references/BY-MODULE.md](references/BY-MODULE.md)) adapted to Indian units (katori, roti, idli).
- Free provider tiers are fine here — it is our own test data, not user health data.
- **Exit test:** estimates land within ±25–30% on most dishes → **go**, and the model is chosen. If not →
  pivot the wedge before building. Write findings to `docs/research/`.

## M0 — Foundation
- Install Flutter + CocoaPods (⚠️ ~1 GB SDK download — needs go-ahead; see [MOBILE.md](MOBILE.md)).
- Scaffold: feature-first, Riverpod, go_router, theme ([DESIGN.md](DESIGN.md)). Seed the sync layer from
  the **CC0** `supabase-todolist-drift` demo; adopt **deliverzler**'s layering
  ([references/BY-MODULE.md](references/BY-MODULE.md)).
- Supabase: Postgres schema + **RLS on every table** ([architecture/01-data-model.md](architecture/01-data-model.md)),
  auth (email + Apple + Google), storage bucket, migrations.
- Drift local schema; **PowerSync** wired ([ADR 0003](adr/0003-supabase-offline-first-drift-powersync.md)).
- CI (already scaffolded) + **Drift migration tests** from the first migration ([MOBILE.md](MOBILE.md)).
- **Exit test:** sign in, write a row offline, see it sync to Supabase and back to a second device.

## M1 — Onboarding + tracking core (the daily-usable app)
- Onboarding (goal → profile → diet → conditions → cuisine → activity).
- Default target computation (Mifflin–St Jeor) for no-plan users.
- Dashboard: calorie budget + macros vs. target; meal-slot cards ([DESIGN.md](DESIGN.md)).
- Manual food logging via search; `food_logs` + `diary_days` rollup. Water + weight + weight chart.
- **Min-version gate + a server-side feature-flag/kill-switch mechanism** — mandatory because we cannot
  hotfix ([MOBILE.md](MOBILE.md)).
- **Exit test:** a casual tracker onboards and logs a full day; totals and chart correct **offline**.

## M2 — Food database v1 + barcode · [ADR 0012](adr/0012-ship-bundled-food-data.md)
- **Bundle USDA (CC0) as-is** as the generic seed (done, M2.2a) — **not** the recompute pipeline.
  **NOT INDB** — it is unlicensed + IFCT-derived (see ADR 0012 banner / CLAUDE.md rule 6). Indian-dish
  coverage = **AI estimation (M2.4)** + a **commercially licensed** dataset (FatSecret / Bon Happetee).
- Barcode scanning (`mobile_scanner` + openfoodfacts-dart / Smooth App scanner) → lookup + cache +
  attribution.
- Custom meals / favourites / quick-add.
- **SETTLED ([ADR 0014](adr/0014-off-live-lookup-only.md)):** Open Food Facts is **live-lookup-only
  with a per-scan cache**. We do NOT bundle an OFF snapshot, so no derived database is distributed.
  Every food row carries `source`/`licence`/`confidence`; OFF stays in its own table.
- **Exit test:** search finds Indian dishes offline; a real barcode resolves and logs correctly.

## M3 — The AI moat  →  **v1 LAUNCH** · [ADR 0011](adr/0011-serverless-ai-gateway.md) · [ADR 0009](adr/0009-freemium-monetization.md)
- AI entry = **Supabase Edge Function (Deno)** → **Cloudflare AI Gateway / OpenRouter** → provider on a
  **paid tier** (no training on health data). **No self-hosted proxy.** Port Helium's `tier_router` pattern.
- **PhotoSnap**: photo → structured items → confirm sheet → log; confidence + correction capture.
- **Vita coach**: context assembly (plan + today + streak) → streaming chat → history.
- **AI estimation** for food-DB gaps, confidence-scored.
- **Freemium metering** enforced in the Edge Function against `ai_usage`: PhotoSnap daily cap, Vita
  monthly budget, plan-gen rate limit; **Sakama Plus** (subscription) + **BYOK** unlock. This is the
  launch monetization surface.
- **Exit test:** photograph a thali → useful macros; Vita answers with today's real data; a free user
  hits the cap and sees the Plus/BYOK prompt; a Plus user is unlimited.
- **► This is the v1 launch: TestFlight → App Store.** (Pull the M7 hardening items forward for this.)

---
## Fast-follow (v1.1+) — to users already on the app
---

## M4 — Plan engine (plan followers + goal setters) · [ADR 0007](adr/0007-plan-engine-as-json-data.md)
- Plan JSON interpreter: resolve day type, targets, fasting window, allowed/blocked foods, rules, checklist.
- **AI plan generation** from onboarding (schema-validated, rate-limited per [ADR 0009](adr/0009-freemium-monetization.md)).
- **Plan import** (paste/upload → Plan JSON). Enforcement surfaces + Vita reads plan context.
- **Exit test:** a "Tuesday reset" day changes targets/checklist and Vita references it; an imported plan
  enforces its eating window.

## M5 — Fasting, workouts, sensors + on-device AI
- IF fasting timer; workout logging + calorie adjustment; steps (`pedometer`); manual sleep + optional
  HealthKit/Health Connect.
- **On-device AI cost/privacy layer** ([ADR 0011](adr/0011-serverless-ai-gateway.md)): nutrition-label
  OCR (Apple Vision / ML Kit), voice→text on-device — free, private, offline; keeps the paid VLM for
  photo estimation only.
- **Exit test:** a fast completes; a workout raises the calorie target; a label scans on-device with no
  network.

## M6 — Voice logging, micronutrient panel, polish
- Voice food logging; micronutrient panel view; streaks + weekly progress + gentle nudges; accessibility,
  Hindi localization, performance pass.

## M7 — Ongoing hardening (much pulled into M3 for launch)
- Security review (RLS coverage, key redaction, storage policies, OWASP M1).
- **Licensing:** finalize permissive attributions + creator credits on the product website.
  (OFF ODbL posture resolved by [ADR 0014](adr/0014-off-live-lookup-only.md): live-only, no derived
  database distributed. INDB resolved: unusable — do not bundle.)
- Privacy policy, App Store / Play data-safety, DPDP/GDPR alignment.

---

## Cross-cutting, every milestone
- **Offline-first**: every feature reads local Drift first, then syncs.
- **RLS** on every new table; tests for provider overrides + in-memory Drift + the sync loop.
- **Migration test** for every Drift schema change (a bad migration destroys user data — [MOBILE.md](MOBILE.md)).
- Food data carries `source`/`licence`/`confidence`; OFF stays source-tagged and contained.
- AI: cheap default + escalation, prompt caching, per-user budgets; **paid tier for real user data**.
- Run **`licence-guard`** before merging anything that adds a dependency or touches food data.

## Known decisions still open (tracked)
- Vision model — decided by the **Phase 0 spike**.
- ~~Open Food Facts live vs. bundled~~ SETTLED: live-only (ADR 0014). Indian-dish source: AI estimation + which commercial
  licence (FatSecret vs Bon Happetee). (INDB is closed: unusable — unlicensed + IFCT-derived.)
- Subscription tooling (RevenueCat vs. native billing) for Sakama Plus.
- Privacy-respecting analytics (no health PII).
- Melos (multi-package) — defer until feature count justifies it.
