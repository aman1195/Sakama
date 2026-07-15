# 0012. Ship-bundled food data for v1 — bundle INDB + USDA, defer the recompute pipeline

**Status:** Accepted · **Date:** 2026-07 · **Grilling outcome** ·
**Supersedes:** the recompute-pipeline strategy in [0008](0008-indian-food-database-strategy.md)
(the source list and ODbL/IFCT rules in 0008 still stand)

## Context
ADR 0008 had us **recomputing** a seed DB from INDB + USDA with yield/retention factors and
cross-validation. That is a multi-week **data-engineering project** on its own — the wrong place for a
solo dev to spend the wedge's time ([ADR 0010](0010-wedge-v1-scope-solo.md)), before a single screen
exists. INDB is already **CC BY 4.0** and usable largely as-is.

## Decision
**For v1, bundle the data as-is; skip the recompute pipeline.**

- Ship **INDB** (CC BY 4.0, ~1,000 Indian recipes, per-100g + per-serving, with attribution) + **USDA
  FoodData Central** (CC0) as the bundled seed.
- **AI estimation** fills the long tail (confidence-scored) — this covers gaps the seed lacks.
- Optionally enrich search/grounding with the **6000+ Indian Recipes** name/ingredient corpus (CC BY;
  names/ingredients/tags only, **not** the scraped instruction text).
- **Unchanged from 0008:** never ingest **IFCT 2017** (NIN prohibition); keep **Open Food Facts** rows in
  a separate, source-tagged table (**ODbL** containment); every row carries `source`/`licence`/
  `confidence`.

## Consequences
- A real Indian food DB ships in **days, not weeks**.
- Data quality is "good enough to test the wedge", not "gold-standard recomputed". Acceptable pre-launch.
- **Deferred (post-launch, if quality is the blocker):** the recompute pipeline, and commercial coverage
  via **FatSecret** (free under $1M revenue, India locale) or **Bon Happetee** (India-native dump).
- **Open M2 decision:** Open Food Facts **live-lookup-only** (ODbL-safe, needs connectivity) vs. a
  **bundled Indian OFF snapshot** (works offline, but is a derived database with ODbL share-alike). Fud
  AI avoids it by live-lookup-only. Settle when building M2.
