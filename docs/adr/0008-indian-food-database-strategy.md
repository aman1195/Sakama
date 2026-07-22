# 0008. Indian food DB: USDA + Open Food Facts + AI/commercial. Never IFCT, never INDB.

**Status:** ⚠️ **Partly superseded by [0012](0012-ship-bundled-food-data.md)** and **amended
2026-07-22.** The **ODbL containment** and **IFCT prohibition** below still stand. But **INDB is NOT a
source** — verified from primary sources that it is unlicensed (all-rights-reserved) AND derived from
IFCT 2017 (see CLAUDE.md rule 6 / [research/base-decision.md](../research/base-decision.md)). Wherever
this ADR says "INDB (CC BY 4.0)" below, that is VOID: USDA (CC0) is the generic base, and Indian dishes
come from AI estimation + a commercial licence, not INDB. · **Date:** 2026-07 ·
**Supersedes:** an earlier "recompute from IFCT 2017" plan

## Context
The Indian food database is the real moat (HealthifyMe's biggest advantage). An earlier plan proposed
recomputing our seed database from **IFCT 2017**. Later research found NIN's stated terms:

> "No part of this publication can be stored or reproduced in any electronic format for creating a product
> without the prior written permission of the National Institute of Nutrition."

That makes the original plan legally unsafe. **INDB was considered as the substitute but is also ruled
out** (amended 2026-07-22): its dataset is unlicensed (all-rights-reserved) and itself IFCT-2017-derived,
so it is neither CC BY nor IFCT-independent.

## Decision
Three-tier strategy:
1. **Curated seed** — **USDA FoodData Central** (CC0) as the generic base. Indian dishes come from **AI
   estimation** + a **commercially licensed** dataset (FatSecret / Bon Happetee), NOT INDB. **Do NOT
   ingest IFCT 2017** (no written NIN permission) **and do NOT bundle INDB** (IFCT-derived + unlicensed).
2. **Open Food Facts** for barcodes/packaged goods — **ODbL**, kept in a **physically separate,
   source-tagged table**, never merged into the proprietary table, with attribution shown.
3. **AI estimation** for the long tail, retrieval-grounded, `confidence`-scored, with a promotion queue to
   human review.

Portion units follow **NIN Dietary Guidelines 2024** (katori, roti, idli...). Every row carries
`source`, `licence`, `confidence`.

## Consequences
- **ODbL is the single biggest legal risk in the stack** — and it has nothing to do with GPL. Counsel review
  before launch.
- Commercial options worth pursuing: **FatSecret** (caching permitted, free under $1M revenue, India locale)
  and **Bon Happetee** (India-native, sells a full data dump).
- **Edamam / Spoonacular / Nutritionix are structurally disqualified** — they prohibit persistent caching,
  and a diary must render a March meal in December, offline.
- ✅ **Resolved 2026-07-22:** INDB is unusable (unlicensed + IFCT-derived) — do not bundle it. The
  Indian-dish gap is filled by AI estimation + a commercial licence instead.
