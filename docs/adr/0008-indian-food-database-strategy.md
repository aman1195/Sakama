# 0008. Indian food DB: INDB + USDA + Open Food Facts. Never IFCT.

**Status:** Accepted · **Date:** 2026-07 · **Supersedes:** an earlier "recompute from IFCT 2017" plan

## Context
The Indian food database is the real moat (HealthifyMe's biggest advantage). An earlier plan proposed
recomputing our seed database from **IFCT 2017**. Later research found NIN's stated terms:

> "No part of this publication can be stored or reproduced in any electronic format for creating a product
> without the prior written permission of the National Institute of Nutrition."

That makes the original plan legally unsafe. Meanwhile **INDB** — dismissed earlier as ambiguous — appears
to be **CC BY 4.0** (commercial use permitted with attribution) and contains **1,014 Indian recipes** plus
1,095 raw items, per 100 g **and per serving**. It is a better fit *and* a safer licence.

## Decision
Three-tier strategy:
1. **Curated seed** — **INDB** (CC BY 4.0, attributed) as the core, **USDA FoodData Central** (CC0) to fill
   nutrient gaps. **Do NOT ingest IFCT 2017** without written NIN permission.
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
- ⚠ **Must verify:** INDB's CC BY 4.0 licence in writing (research streams disagreed on it).
