# Sakama

> Free, AI-powered personal health & nutrition OS for Indian users.
> **Free forever. No ads. No data selling. Better AI than HealthifyMe. Built for India.**

Sakama tracks calories, macros, micronutrients, water, fasting, weight, workouts, steps, and sleep —
logged by **photo, voice, text, barcode, or search** — and wraps it in an AI coach that actually knows your
plan, your day, and your streak.

**Status: planning complete. No application code yet.** Next step is **M0** (see
[Sakama-Start-Plan.md](Sakama-Start-Plan.md)), which begins with a Flutter SDK install.

## Start here

| Doc | What it is |
|---|---|
| **[Sakama-Start-Plan.md](Sakama-Start-Plan.md)** | **The direction document.** What we are building, what is decided, what happens next. |
| [PRODUCT.md](PRODUCT.md) | Users, purpose, brand, anti-references, design principles |
| [CLAUDE.md](CLAUDE.md) | Engineering rules and non-negotiables |
| [AGENTS.md](AGENTS.md) | The skills and agents installed in this repo |
| [DEVELOPER_STANDARDS.md](DEVELOPER_STANDARDS.md) | Git, commits, PRs, security, testing |
| **[docs/MOBILE.md](docs/MOBILE.md)** | **Mobile realities** — you cannot hotfix; a bad migration destroys user data |
| [ASSET_CREDITS.md](ASSET_CREDITS.md) | Attribution — a **legal obligation** (ODbL, CC BY), not a courtesy |
| [APPSTORE.md](APPSTORE.md) · [PLAYSTORE.md](PLAYSTORE.md) | Store listings, kept in version control |

## Documentation

| Doc | Covers |
|---|---|
| [docs/CONTEXT.md](docs/CONTEXT.md) | Product spec: the three user types, full feature inventory, onboarding |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System topology, stack, offline-first data flow |
| [docs/DESIGN.md](docs/DESIGN.md) | UI/UX system — what we take from **Fud AI** and **HealthifyMe** |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Milestones M0–M7 |
| [docs/adr/](docs/adr/) | Architecture decision records |
| [docs/architecture/](docs/architecture/) | Data model · AI layer · Food database · Plan engine |
| [docs/research/](docs/research/) | Why we fork nothing · Fud AI teardown · OpenNutriTracker teardown · sources |
| [docs/references/BY-MODULE.md](docs/references/BY-MODULE.md) | **Reference map** — which OSS project to look at per module, licence-aware |

## Stack

**Flutter** (iOS-primary, Android-capable) · **Riverpod** · **go_router** · **Drift** (local, source of
truth) · **PowerSync** (offline sync) · **Supabase** (Postgres, Auth, Storage, Edge Functions) ·
**serverless AI gateway** (Supabase Edge Function → Cloudflare AI Gateway / OpenRouter, multi-provider + BYOK) · `fl_chart`

## Layout

```
docs/           planning, architecture, design, research
app/            Flutter app          (empty — M0)
supabase/       migrations, edge functions, seed pipeline (empty — M0)
supabase/       AI gateway lives in edge functions (ADR 0011; ai-gateway/ dir superseded)
.agents/skills/ 27 engineering skills
.claude/        agents (licence-guard), hooks, skills
```

## The three things that shape this project

1. **The tracking core is not the bottleneck.** The moats are the Indian food database, portion semantics,
   and the AI layer.
2. **Build the code, buy the data.** No template or API gives you an Indian food database.
3. **The biggest legal risk is Open Food Facts' ODbL**, not GPL. Keep OFF data in a separate, tagged table.
