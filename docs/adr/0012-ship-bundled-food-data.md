# 0012. Ship-bundled food data for v1 — bundle USDA now; Indian dishes via AI + commercial licence

**Status:** Accepted (amended 2026-07-22) · **Date:** 2026-07 · **Grilling outcome** ·
**Supersedes:** the recompute-pipeline strategy in [0008](0008-indian-food-database-strategy.md)
(the source list and ODbL/IFCT rules in 0008 still stand)

> **⚠ AMENDED 2026-07-22 — the INDB half of this decision is VOID.** This ADR originally said "bundle
> INDB (CC BY 4.0) + USDA." Verified from primary sources: **INDB is NOT CC BY 4.0** (the dataset has no
> licence — all-rights-reserved) **and is derived from IFCT 2017**, so bundling it would redistribute
> all-rights-reserved data and re-import the rule-6 IFCT risk. See CLAUDE.md rule 6 and
> [research/base-decision.md](../research/base-decision.md). **Do not bundle INDB.** USDA (CC0) still
> ships; Indian-dish coverage moves to AI estimation + a commercially licensed dataset (below).

## Context
ADR 0008 had us **recomputing** a seed DB with yield/retention factors and cross-validation. That is a
multi-week **data-engineering project** on its own — the wrong place for a solo dev to spend the wedge's
time ([ADR 0010](0010-wedge-v1-scope-solo.md)), before a single screen exists. So v1 bundles ready data
rather than recomputing. (The original plan named INDB as that ready data; that is now void — see banner.)

## Decision
**For v1, bundle ready data as-is; skip the recompute pipeline.**

- Ship **USDA FoodData Central** (CC0) as the bundled generic-ingredient seed. ✅ done (M2.2a).
- **Indian dishes** (the wedge): NOT from INDB. Covered by **AI estimation** (confidence-scored,
  M2.4) plus a **commercially licensed** dataset (FatSecret / Bon Happetee — a business action), and
  **OFF** (ODbL, isolated) for branded packaged foods.
- **Unchanged from 0008:** never ingest **IFCT 2017** (NIN prohibition); keep **Open Food Facts** rows in
  a separate, source-tagged table (**ODbL** containment); every row carries `source`/`licence`/
  `confidence`.

## Consequences
- A real Indian food DB ships in **days, not weeks**.
- Data quality is "good enough to test the wedge", not "gold-standard recomputed". Acceptable pre-launch.
- **Deferred (post-launch, if quality is the blocker):** the recompute pipeline, and commercial coverage
  via **FatSecret** (free under $1M revenue, India locale) or **Bon Happetee** (India-native dump).
- **CLOSED ([ADR 0014](0014-off-live-lookup-only.md), 2026-07-22):** Open Food Facts is
  **live-lookup-only with a per-scan cache**. No OFF snapshot is bundled, so no derived database is
  distributed. Logging copies values into `food_logs`, so the diary still renders offline.
