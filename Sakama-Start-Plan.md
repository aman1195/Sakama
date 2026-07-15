# Sakama — Start Plan

> The executable plan from "empty repo" to "first shippable build". This is the **direction document**:
> what we are building, what is already decided, what is still open, and exactly what happens next.
>
> Product: [PRODUCT.md](PRODUCT.md) · Engineering rules: [CLAUDE.md](CLAUDE.md) · Superpowers:
> [AGENTS.md](AGENTS.md) · Decisions: [docs/adr/](docs/adr/)

---

## 1. What Sakama is

A free, AI-powered personal health and nutrition OS for Indian users. A HealthifyMe competitor whose
wedge is a **genuinely better LLM coaching layer**.

**Core promise: Free forever. No ads. No data selling. Better AI than HealthifyMe. Built for India.**

It serves three users at once: **plan followers** (enforce my protocol), **goal setters** (generate a plan
for me), and **casual trackers** (just log and nudge me). See [docs/CONTEXT.md](docs/CONTEXT.md).

## 2. Where we are

**Planning and research are complete. No application code exists yet.**

Four deep research sweeps and two code-level teardowns (OpenNutriTracker, Fud AI) have settled the
foundations. Two earlier conclusions were **reversed** under scrutiny — that is a feature of the process,
not a failure, and both reversals are recorded in the ADRs.

## 3. What is decided (and will not be relitigated without a new ADR)

| Decision | Answer | ADR |
|---|---|---|
| Client | **Flutter**, iOS-primary, Android-capable | [0002](docs/adr/0002-flutter-client-ios-first.md) |
| Backend + offline | **Supabase** + **Drift/PowerSync** offline-first | [0003](docs/adr/0003-supabase-offline-first-drift-powersync.md) |
| Licence stance | **Closed-source, commercial** | [0004](docs/adr/0004-closed-source-licence-stance.md) |
| Base | **Fork nothing.** Build fresh from a permissive assembly kit | [0005](docs/adr/0005-build-fresh-no-fork.md) |
| AI | **Serverless gateway** (Edge Fn + managed gateway) + hybrid **BYOK** | [0011](docs/adr/0011-serverless-ai-gateway.md) |
| Plans | **JSON data**, never hardcoded | [0007](docs/adr/0007-plan-engine-as-json-data.md) |
| Food data | **INDB + USDA + OFF.** Never IFCT | [0008](docs/adr/0008-indian-food-database-strategy.md) |

### The three findings that shape everything
1. **The tracking core is not the bottleneck** (~3–6 weeks). The moats are the **Indian food DB with
   portion semantics**, **search relevance**, and the **AI layer**. Spend time there.
2. **Build the code, buy the data.** No template or API supplies an Indian food database. That is where
   money converts into product.
3. **The biggest legal risk is not GPL — it is Open Food Facts' ODbL** share-alike on derived databases.
   Keep OFF data in a separate, source-tagged table.

## 4. The permissive assembly kit (start at ~30–40%, not 0%)

| Layer | Take | Licence |
|---|---|---|
| Offline core | PowerSync demo **`supabase-todolist-drift`** — *exactly our stack* | **CC0** (zero obligations) |
| Architecture | **deliverzler** — Riverpod + layered DDD reference | MIT |
| Auth screens | `supabase_auth_ui` | MIT |
| Barcode + food | `openfoodfacts-dart`, Smooth App `packages/scanner` | Apache-2.0 |
| Charts | `fl_chart` | MIT |
| Health/sensors | `health`, `pedometer`, `mobile_scanner` | MIT / BSD |
| AI gateway | **Supabase Edge Fn** + managed gateway (Cloudflare AI Gateway / OpenRouter) | managed |
| AI blueprint | **Fud AI** prompts + provider abstraction; **Helium** tier-router pattern | MIT / first-party |
| Shell / CI | `very_good_cli`, `very_good_workflows` | MIT |

**Never use:** `Best-Flutter-UI-Templates` (not actually MIT), any GPL/AGPL app, any repo with no LICENSE.

## 5. Milestones

Full detail in [docs/ROADMAP.md](docs/ROADMAP.md). Each milestone leaves the app shippable. **Never build
breadth-first.**

| M | Goal | Exit test |
|---|---|---|
| **M0** | Foundation: Flutter scaffold, Supabase schema + RLS, Drift + PowerSync sync loop | Write a row offline; see it sync to Supabase and to a second device |
| **M1** | Onboarding + profile + tracking core + dashboard | A casual tracker logs a full day; totals correct **offline** |
| **M2** | Food database v1 (INDB + USDA + OFF) + barcode + search | Search finds Indian dishes offline; a real barcode resolves |
| **M3** | **The AI moat** — serverless AI gateway (Edge Fn + managed gateway), PhotoSnap, Vita coach, AI estimation | Photograph a thali → sane items/macros; Vita answers with today's real data |
| **M4** | Plan engine — AI generation + import + enforcement | A "Tuesday reset" day changes targets/checklist; Vita references it |
| **M5** | Fasting, workouts, steps, sleep (HealthKit) | A fast completes; a workout raises the calorie target |
| **M6** | Voice logging, micronutrient panel, streaks, polish, Hindi | — |
| **M7** | Launch hardening: security, licences, privacy policy, store submission | TestFlight → App Store |

## 6. What happens next (M0, concretely)

1. ⚠️ **Install Flutter + CocoaPods.** Not installed on this machine. ~1 GB SDK download plus a PATH
   change. **Requires explicit go-ahead** (Xcode, Node, Supabase CLI, and Python are already present).
2. Scaffold `app/` — feature-first structure, Riverpod, go_router, theme from [docs/DESIGN.md](docs/DESIGN.md).
3. Seed the sync layer from the **CC0** `supabase-todolist-drift` demo; adopt **deliverzler**'s layering.
4. Create the Supabase project: schema + **RLS on every table**
   ([docs/architecture/01-data-model.md](docs/architecture/01-data-model.md)), auth, storage bucket.
5. Prove the offline loop end-to-end. **That is M0's only exit test.**

## 7. Open questions (tracked, not blocking M0)

| Question | Owner | Blocks |
|---|---|---|
| **Verify INDB is CC BY 4.0 in writing** (research streams disagreed) | Legal | M2 |
| Counsel review of our **Open Food Facts ODbL** posture | Legal | M7 |
| **Benchmark vision models on Indian food** (portion estimation is workload-dependent) | Eng | M3 |
| Quote from **Bon Happetee** (India-native food data licence) | Product | M2 |
| **FatSecret** Premier Free eligibility + India locale, in writing | Product | M2 |
| Managed AI gateway choice (Cloudflare AI Gateway vs OpenRouter) — ADR 0011 | Eng | M3 |
| Privacy-respecting analytics choice (no health PII) | Eng | M6 |

## 8. How to work in this repo

- **Before a big call**, run the `grilling` skill. This project has already reversed two confident
  conclusions; assume a third is hiding.
- **Before merging anything** that adds a dependency or touches food data, run the **`licence-guard`**
  agent. Copyleft contamination is existential here.
- **Design subsystems twice** (`codebase-design`), then write the ADR (`domain-modeling`).
- **TDD the pure logic** — nutrition math and the plan engine have no excuse for being untested.
