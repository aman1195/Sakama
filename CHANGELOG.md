# Changelog

All notable changes to Sakama. Format: [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Project foundation: product spec, architecture, data model, AI layer, food-database strategy, roadmap.
- Architecture Decision Records 0001–0008.
- UI/UX design system informed by Fud AI and HealthifyMe.
- Agent superpowers: 26 skills, `licence-guard` agent, `block-push-to-main` hook, Kiro steering.
- `docs/MOBILE.md` — mobile realities (no hotfix; on-device migrations destroy data; store review).
- `ASSET_CREDITS.md`, `APPSTORE.md`, `PLAYSTORE.md`, `justfile`, `LICENSE` (proprietary), `.gitignore`.

### Removed
- Web-only skills inherited from the web reference repos: `benchmark` (Core Web Vitals / Next.js) and
  `web-design-guidelines` (Web Interface Guidelines).
- `.kiro/steering/identity-drift.md` (AWS Cognito — Sakama uses Supabase Auth).

### Decided
- Flutter client, iOS-primary (ADR 0002). Supabase + Drift/PowerSync offline-first (ADR 0003).
- Closed-source commercial (ADR 0004). Fork nothing; build fresh (ADR 0005).
- LiteLLM gateway with hybrid BYOK (ADR 0006). Plans as JSON data (ADR 0007).
- Food DB: INDB + USDA + Open Food Facts; never IFCT (ADR 0008).

### Reversed (recorded for honesty)
- An interim "fork Fud AI" recommendation, overturned by a source-code teardown (ADR 0005).
- An earlier "recompute the food DB from IFCT 2017" plan, overturned on licensing (ADR 0008).
