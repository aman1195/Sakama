# Sakama — Build Roadmap

> **Revised after the 2026-07 grilling session** (see [adr/README.md](adr/README.md), ADRs 0009–0013).
> The north star is still the full vision. Build milestone-by-milestone; never breadth-first. Each
> milestone leaves the app shippable and dogfoodable.

> **⚠ RELEASE STRATEGY UPDATED 2026-07-31.** The original plan drew the store-release line after M3 (a
> wedge launch, M4–M7 as fast-follow). That is superseded: **the app is released only when it is fully
> complete — M4–M7 first, then submit.** The M3.5 launch artefacts (privacy policy, store-form sheet,
> [launch-checklist](legal/launch-checklist.md), anon-abuse monitoring) are DONE and simply wait for
> that point; do not treat them as an imminent submission gate. The milestone build order below is
> unchanged; only the release point moved.

## Sequencing principle

**Prove the moat → foundation → daily-usable core → the moat itself → complete the vision → LAUNCH.**

The build order (Phase 0 → M7) is unchanged. What changed (2026-07-31) is the release point: it is drawn
**after the app is fully complete**, not after M3. M3 remains the point where the AI moat is done and the
app is fully dogfoodable, but store submission waits for M4–M7.

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

## M3 — The AI moat  (AI complete + fully dogfoodable; release deferred to post-M7) · [ADR 0011](adr/0011-serverless-ai-gateway.md) · [ADR 0009](adr/0009-freemium-monetization.md)
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
- **► M3 outcome:** the AI moat is done and the app is fully dogfoodable. Store submission is **deferred
  to post-M7** per the release-strategy update above; the M3.5 launch artefacts are built and parked.
  (Much of the M7 hardening was already pulled forward into M3.)

---
## M4–M7 — complete the vision (build BEFORE release, per the 2026-07-31 strategy update)
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

## M8+ — the 2.0 vision (added 2026-08-27)

The milestones above take Sakama to a complete Indian mobile product. The 2.0 vision adds three
things that do not exist in v1 at all: **the whole-health modules** (mood, cycle, richer sleep),
**the household** (family sharing), and **the second deployment** (self-hosted, web, MCP).

These are sequenced after M7 deliberately. Each one is a new isolation boundary, and an isolation
bug in any of them leaks health data. None of them block M3 dogfooding.

## M8 — Whole-health modules
- **Mood**: daily 1–5 check-in with notes; trend charts; correlation against sleep and nutrition.
- **Cycle hub**: period, ovulation and symptom logging; phase-aware nutrition guidance; Vita reads
  the phase.
- **Body measurements**: custom sites beyond weight; optional progress photos in per-user storage.
- **Long-term reports**: custom ranges, cross-module correlation, CSV export.
- **Exit test:** a low-mood + poor-sleep + under-eating day produces a materially different Vita
  reply from a good one, and the difference is traceable to real rows.

## M9 — Wearables and sensors
- Ten integrations: Apple Health, Google Health Connect, Google Health API, Fitbit, Garmin (its own
  microservice), Withings, Polar, Oura, Strava, Hevy.
- Background sync, OAuth refresh, rate-limit handling, per-provider `sync_logs`.
- Wearable data (HRV, sleep stages, body battery) enters the Vita context.
- **Exit test:** a provider returning 401 shows "not syncing, reconnect" and never presents stale
  data as current. Strava specifically is expected to break without notice; it must degrade, not
  crash.

## M10 — Family and multi-user
- Seven granular read permissions; write never granted by default.
- Invitation, acceptance and revocation flows. Family dashboard. Family-aware Vita.
- **Gate:** an RLS audit and cross-user integration tests **before** this ships. This is the
  highest-consequence feature in the product — a permission bug here leaks one person's health data
  to someone who knows them personally. It stays in beta until the audit passes.

## M11 — Second deployment: self-hosted, web, MCP · [ADR 0017](adr/0017-dual-deployment-cloud-and-self-hosted.md)
- React web client, functional without the mobile app.
- Node API server; Docker Compose; Helm chart; shared migration runner so cloud and self-hosted
  cannot drift.
- **Shared AI code path.** Budget enforcement, BYOK handling and key redaction live in one module
  both entry points import. Two copies will drift, and the drift would be in a security control.
- MCP server (read + write) through the same RLS as every other client.
- TOTP, Passkey, instance-level MFA.
- **The moat boundary must be documented before the Docker release, not after** (ADR 0017): curated
  Indian data reaches self-hosted instances over an authenticated lookup, never seeded into the
  image, and degrades to USDA + OFF when the user runs air-gapped.
- **Exit test:** a fresh `docker compose up` reaches a working tracking app in under ten minutes,
  and a deliberately misconfigured instance fails closed rather than open.

## M12 — Localisation and launch hardening
- Hindi, Tamil, Telugu, Kannada, Bengali. Weblate for community translation.
- Accessibility audit (WCAG 2.1 AA). Security audit and penetration test. Load and migration
  testing. Beta across Indian users and global self-hosters.
- Store submission.

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
- **One-tap meal logging is a LICENCE-SENSITIVE review, not a UI formality.** The meals table
  (#144) holds `user_foods` ids and portions and no nutrition, which is what keeps it out of ADR
  0014's stricter category. The follow-up that logs a meal resolves nutrition from `user_foods` into
  `food_logs`, and that write is permitted — a food_logs row is a historical record behind RLS. The
  containment holds **only if that path writes to `food_logs` and nowhere else.** Caching resolved
  nutrition back onto the meal row to avoid a join would look like a sensible optimisation in a diff
  and would turn `meals` into the OFF-derived branded-food catalogue the design exists to prevent.
  If Vita can log a meal, it also needs propose-confirm, since one tool call would write several
  diary rows.
- **Competitor gap backlog** — eight ranked items in
  [competitor-teardown-2026-08.md §4](research/competitor-teardown-2026-08.md). The first four are
  small and block on nothing: entry date, serving multiplier, confidence badge, burn on Home.
- **OpenRouter top-up checklist** — five ordered steps in
  [model-bakeoff-2026-08.md §5](research/model-bakeoff-2026-08.md). Two of them fail SILENTLY if
  skipped: the paid path still pins `google/gemini-2.5-flash`, which Google retired for new direct
  API accounts, and the dev-only Gemini free-tier secrets must come out before any real user's
  photo is sent to a tier whose terms permit human review.
- Subscription tooling (RevenueCat vs. native billing) for Sakama Plus.
- Privacy-respecting analytics (no health PII).
- Melos (multi-package) — defer until feature count justifies it.
