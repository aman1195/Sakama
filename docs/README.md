# Sakama Documentation

Start with [Sakama-Start-Plan.md](../Sakama-Start-Plan.md) — the direction document.

## Planning & product
- [CONTEXT.md](CONTEXT.md) — product spec: three user types, feature inventory, onboarding
- [../PRODUCT.md](../PRODUCT.md) — users, purpose, brand, anti-references, design principles
- [DESIGN.md](DESIGN.md) — UI/UX system (what we take from Fud AI + HealthifyMe)
- [ROADMAP.md](ROADMAP.md) — milestones M0–M7
- [MOBILE.md](MOBILE.md) — **mobile realities**: no hotfix, on-device migrations, store review, perf targets

## Architecture
- [ARCHITECTURE.md](ARCHITECTURE.md) — system topology, stack, offline-first data flow
- [architecture/01-data-model.md](architecture/01-data-model.md) — Postgres schema, RLS, sync mapping
- [architecture/02-ai-layer.md](architecture/02-ai-layer.md) — LiteLLM, PhotoSnap, Vita, BYOK, cost
- [architecture/03-food-database.md](architecture/03-food-database.md) — three-tier DB, licensing
- [architecture/04-plan-engine.md](architecture/04-plan-engine.md) — the plan JSON contract
- [adr/](adr/) — architecture decision records

## Research (why we decided what we decided)
- [research/base-decision.md](research/base-decision.md) — **why we fork nothing**; the assembly kit
- [research/eval-fud-ai.md](research/eval-fud-ai.md) — Fud AI source teardown
- [research/eval-opennutritracker.md](research/eval-opennutritracker.md) — OpenNutriTracker teardown
- [research/sources.md](research/sources.md) — every source behind these decisions
