# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

**Sakama** is a free, AI-powered personal health and nutrition app for Indian users — a HealthifyMe
competitor whose wedge is a genuinely better LLM coaching layer. It is a **real product** headed for the
App Store and Play Store, not a prototype. It is **closed-source and commercial**.

**Status: M0 in progress.** Phase 0 (PhotoSnap validation) passed — GO, model =
`gemini-2.5-flash` (see docs/research/photosnap-spike-findings.md). The Flutter scaffold
lives in `app/` (feature-first, Riverpod, go_router, Drift v1 schema, envied env).
Supabase/PowerSync wiring is stubbed in `lib/core/sync/` pending project credentials in `app/.env`.

Read [PRODUCT.md](PRODUCT.md) before touching anything user-facing.

## Stack (decided — see docs/adr/)

| Layer | Choice |
|---|---|
| Client | **Flutter** (iOS-primary, Android-capable) |
| State | **Riverpod** 3.x (+ codegen) |
| Routing | **go_router** |
| Local DB | **Drift** (SQLite) — the single source of truth |
| Sync | **PowerSync** (offline-first, Supabase-endorsed) |
| Backend | **Supabase** — Postgres + Auth + Storage + Edge Functions |
| AI gateway | **Serverless**: Supabase Edge Function → managed gateway (Cloudflare AI Gateway / OpenRouter). No self-hosted proxy. ([ADR 0011](docs/adr/0011-serverless-ai-gateway.md)) |
| AI providers | Config-swappable. Cheap model default, escalate for hard turns. BYOK supported. |
| Charts | `fl_chart` (MIT) |

## Non-negotiable rules

1. **Offline-first.** The UI reads local Drift, never the network directly. Every feature must work with
   no signal; sync reconciles later.
2. **RLS on every user table.** `user_id uuid default auth.uid()` + `auth.uid() = user_id` policies.
   This is the primary data-isolation boundary for a health app.
3. **No provider API key ever ships in the client.** All LLM calls route through a Supabase Edge Function
   → managed AI gateway → provider on a **paid tier** (free tiers train on data — unacceptable for health
   data; [ADR 0011](docs/adr/0011-serverless-ai-gateway.md)). User BYOK keys are envelope-encrypted at rest
   and redacted from all logs (OWASP M1).
4. **Licence hygiene is load-bearing.** This is a closed-source commercial product.
   - **NEVER copy GPL/AGPL code.** OpenNutriTracker, wger, FoodYou, Waistline are all copyleft — they may
     be read for *domain understanding only*, never copied.
   - **Best-Flutter-UI-Templates is NOT MIT** despite appearances. Do not use it.
   - Permissive only: MIT / Apache-2.0 / BSD / CC0. Keep a licence-checker in CI.
5. **Open Food Facts data is ODbL.** Keep OFF-derived rows in a **physically separate, source-tagged
   table**. Never merge them into the proprietary Indian food table. This is the single biggest legal risk
   in the stack.
6. **Do NOT ingest IFCT 2017.** NIN forbids electronic reproduction for a product without written
   permission. Use **INDB** (CC BY 4.0) + **USDA** (CC0) instead.
7. **Every food row carries `source`, `licence`, `confidence`.** Non-negotiable for provenance audits and
   for ranking verified data above AI estimates.
8. **This is a MOBILE app — read [docs/MOBILE.md](docs/MOBILE.md).**
   - **You cannot hotfix.** App review takes days; a bad build is live until users update. Staged rollout,
     server-side kill switches, and a minimum-version gate are mandatory.
   - **A bad Drift migration destroys user data irrecoverably.** There is no server backup of an on-device
     DB. Every schema change needs a tested, forward-only migration. Migration tests are non-negotiable.
   - Performance means **cold start, jank, app size, battery** — never TTFB/LCP/bundle size.
   - **ModelBeat and Helium are WEB projects.** Take their process (git, ADRs, TDD, review) and nothing
     else. For **mobile** conventions the references are **OpenNutriTracker** and **Fud AI** (both shipping
     health apps) — take their *process*, never OpenNutriTracker's *code* (GPL).
9. **AI cost discipline.** Cheap model by default, prompt-cache long system prompts, hard per-user
   budgets enforced in the Edge Function (against `ai_usage`). Defaulting chat or vision to a flagship
   model is what blows the budget.

## Repository layout

```
PRODUCT.md            brand, users, design principles  ← read first
CLAUDE.md             this file
AGENTS.md             the skills/superpowers available in this repo
Sakama-Start-Plan.md  the executable plan to first build
docs/
  ARCHITECTURE.md     system topology
  CONTEXT.md          product spec: user types, full feature inventory
  DESIGN.md           UI/UX system (what we take from Fud AI + HealthifyMe)
  ROADMAP.md          milestones M0–M7
  MOBILE.md           mobile realities: no hotfix, migrations, store review, perf targets
  adr/                architecture decision records (0011 supersedes 0006; 0012 amends 0008)
  architecture/       01-data-model · 02-ai-layer · 03-food-database · 04-plan-engine
  references/         BY-MODULE.md — which OSS project to look at per module (licence-aware)
  research/           base-decision · eval-fud-ai · eval-opennutritracker · sources
app/                  Flutter app        (empty — created in M0)
supabase/             migrations, edge functions (the AI gateway lives here — M3)
ai-gateway/           SUPERSEDED by ADR 0011 (no self-hosted proxy). Empty; may be removed.
```

## Commands

Run from the repo root via [justfile](justfile), or directly in `app/`:

```
just install    # flutter pub get
just build      # dart run build_runner build (envied + drift codegen — required after clone)
just analyze    # flutter analyze
just test       # flutter test (includes test/migration/ — mandatory per docs/MOBILE.md)
just ci         # all of the above
```

After a fresh clone: `cp app/.env.example app/.env`, then `just install build` before anything else
(generated `*.g.dart` files are gitignored on purpose).

## Conventions (to apply from M0)

- **Feature-first structure**: `lib/features/<feature>/{data,domain,presentation}`.
- Riverpod providers for DI and state; `freezed` for models; `go_router` typed routes.
- Accessibility identifiers on every interactive widget (stable, kebab-case, locale-independent) so UI
  drivers can find them.
- Nutrition stored canonically **per 100 g**; per-serving derived at read time.
- Plans are **JSON data, never hardcoded logic** (see `docs/architecture/04-plan-engine.md`).

## Working style in this repo

- The user is a **direct communicator** and **time-efficient**. Lead with the outcome.
- **Explain any infrastructure/CLI command before running it** (see the global CLAUDE.md rule): what it
  does, what changes, what is irreversible, how to roll back, then ask.
- Research before asserting. This project has already been burned twice by confident claims that turned
  out wrong (an overstated GPL/App-Store incompatibility, and an under-described scanner). **Verify from
  source, then speak.**
