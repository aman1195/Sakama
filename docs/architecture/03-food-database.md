# Sakama — Food Database Strategy

> The Indian food database is HealthifyMe's biggest moat. Ours is a **three-tier** system with a
> defensible, self-computed core. Licensing is called out explicitly because this is a commercial
> product. Grounded in July 2026 research ([research-sources.md](../research/sources.md)).

> ## ⚠️ SUPERSEDED IN PART — read [research/base-decision.md](../research/base-decision.md) first
>
> Later research (July 2026) **inverted two key licensing assumptions** in this document:
>
> 1. **IFCT 2017 is NOT our foundation — do not ingest it.** NIN's stated terms: *"No part of this
>    publication can be stored or reproduced in any electronic format for creating a product without
>    the prior written permission of the National Institute of Nutrition."* The "recompute our seed DB
>    from IFCT" strategy below is **legally unsafe without written NIN permission.**
> 2. ~~**INDB is far better than stated below** — CC BY 4.0, our core Indian seed.~~ **RETRACTED
>    2026-07-22.** Verified from primary sources: the INDB *dataset* (GitHub
>    `lindsayjaacks/Indian-Nutrient-Databank-INDB-`) has **no licence** (`license: None`, `/license`
>    → 404) = all-rights-reserved, and its own README shows it is **built from IFCT 2017** ("a master
>    IFCT"). The CC BY 4.0 badge is on the journal *article*, not the data. **INDB is unusable** — it
>    is neither CC BY nor IFCT-independent. The row below ("Cross-check reference only") was correct all
>    along. Indian-dish coverage comes from AI estimation (M2.4) + a commercial licence, not INDB.
> 3. **New: buy the data.** **FatSecret** (caching permitted, free under $1M revenue, India locale) and
>    **Bon Happetee** (India-native, sells a full data dump) are the commercial options.
>    **Edamam / Spoonacular / Nutritionix are structurally disqualified** — they prohibit persistent
>    caching, and a food diary must render a March meal in December, offline.
>
> The three-tier architecture, the schema, and the ODbL containment strategy below all **remain valid**.

## 1. Three-tier architecture

```
(a) CURATED SEED DB   ~300–800 common Indian dishes + staples   ← our core asset, shipped in-app
        source: recomputed from IFCT 2017 + NIN 2024 portions + USDA (CC0) gap-fill
(b) OPEN FOOD FACTS    barcodes / branded packaged foods         ← source-tagged, ODbL-contained
        LIVE lookup per scan + local cache of the user's own scans; NO bundled snapshot (ADR 0014)
(c) LLM AI ESTIMATION  the long tail (any dish/portion not above) ← retrieval-grounded, confidence-scored
        promote frequently-requested, human-reviewed estimates into (a)
```

## 2. Sources and licensing (decisive for shipping)

| Source | What it gives | License | Ship as-is? |
|---|---|---|---|
| **USDA FoodData Central** | Generic ingredients, full micros, global branded | **CC0 / public domain** | ✅ Freely |
| **Open Food Facts** | Barcodes, Indian branded (~10k, growing, variable quality) | **ODbL** (attribution + share-alike) | ✅ if kept in a **separate source-tagged table** with attribution; do **not** merge into a redistributed proprietary DB |
| **IFCT 2017** (ICMR-NIN) | Authoritative Indian **ingredient** composition, 528 foods × 151 nutrients | ICMR-NIN copyright, "use encouraged", **no explicit open license** | ⚠️ Recompute our own values from it; get **written NIN clearance** before verbatim redistribution |
| **INDB** (Anuvaad) | **1,014 cooked Indian recipes**, per-100g + per-serving, full micros | "open-access", **no explicit commercial license**; inherits UK Crown-copyright data | ⚠️ **Cross-check reference only** until written clearance from Anuvaad |
| `ifct2017` GitHub | Machine-readable IFCT | **AGPL-3.0** (recent), MIT (old only) | ❌ Avoid AGPL build in a proprietary app |
| Kaggle community sets | Various Indian dish macros | Mostly unspecified / non-commercial | ❌ Prototyping cross-check only |
| **NIN "Dietary Guidelines for Indians 2024"** | Standard servings ("My Plate", katori units) | ICMR-NIN reference | ✅ as portion reference (verify grams against the PDF) |

**The defensible core:** build the seed DB by **recomputing** dish nutrition from IFCT 2017 ingredient
values + standard recipes + NIN 2024 serving sizes, filling gaps with USDA (CC0). This makes our
shipped data our **own derived work** with a clean provenance trail, not a wholesale copy of a
copyleft or ambiguously-licensed table. INDB/Kaggle are used only to validate our numbers.

> **Action item before commercial launch:** obtain written commercial clearance from **ICMR-NIN**
> (IFCT-derived values) and optionally **Anuvaad** (`awasthi@anuvaad.org.in`, INDB). USDA needs none.
> A short legal review of our OFF redistribution posture is prudent.

## 3. Food item schema (canonical, per 100 g)

```json
{
  "id": "uuid",
  "name": "Dal Tadka",
  "name_local": { "hi": "दाल तड़का" },
  "type": "dish | ingredient | branded_product",
  "barcode": "8901234567890 | null",
  "cuisine_region": "North Indian | South Indian | ...",
  "food_group": "pulses | cereals | vegetables | ...",   // NIN 2024 groups
  "basis": "per_100g",
  "energy_kcal": 130.0,
  "macros": { "protein_g": 6.2, "carbohydrate_g": 15.0, "sugars_g": 1.1,
              "fat_g": 5.0, "saturated_fat_g": 1.2, "fiber_g": 3.4 },
  "micros": { "iron_mg": 1.8, "calcium_mg": 28.0, "magnesium_mg": 40.0, "zinc_mg": 0.9,
              "sodium_mg": 210.0, "potassium_mg": 300.0, "vitamin_a_ug": 15.0,
              "vitamin_c_mg": 2.0, "vitamin_d_ug": 0.0, "folate_ug": 45.0, "vitamin_b12_ug": 0.0 },
  "serving_units": [ { "unit": "katori", "label": "1 katori", "grams": 150, "is_default": true },
                     { "unit": "bowl", "label": "1 bowl", "grams": 200 } ],
  "source": "curated_ifct | openfoodfacts | usda_fdc | indb | ai_estimate",
  "source_ref": "IFCT2017:C001 | OFF:<barcode> | FDC:<fdcId>",
  "license": "computed_derived | ODbL | CC0 | ...",
  "confidence": 0.0,           // 1.0 measured; lower for AI estimate
  "verified_by_human": true,
  "last_updated": "2026-07-03"
}
```

**Non-negotiable columns for a commercial product:** `source`, `license`, `confidence` on every row.
They (1) prove provenance for licensing audits, (2) quarantine ODbL/AGPL data from proprietary tables,
(3) give users a trust signal and let us rank verified data above AI estimates.

## 4. Serving units (Indian, from NIN 2024)

Encode named units, not hard-coded grams per dish. Verify exact grams against the DGI 2024 PDF:
- 1 katori cooked dal/veg ≈ 150 mL bowl · 1 roti/chapati ≈ 30–40 g flour basis
- 1 idli ≈ 30–35 g · 1 katori cooked rice ≈ 150 g

Store canonically per 100 g; derive per-serving from `serving_units` at read time.

## 5. Runtime behavior

- **Search / autocomplete:** query the **local Drift** seed + cached rows (OFF live search is rate-
  limited to 10 req/min and unfit for as-you-type). Ship the USDA seed as app data. NO OFF snapshot is bundled (ADR 0014).
- **Barcode:** `mobile_scanner` → look up the local **cache of previously scanned barcodes** first →
  otherwise live OFF API (proper `User-Agent` `Sakama/<ver> (contact)`) → cache the result into the
  separate `off_foods` table. No bundled snapshot ([ADR 0014](../adr/0014-off-live-lookup-only.md)).
  Show ODbL attribution on OFF-sourced items.
- **Gap → AI estimate:** if not found in (a)/(b), call the AI estimator ([architecture/02-ai-layer.md](02-ai-layer.md))
  grounded on nearest IFCT/USDA rows; store as `source=ai_estimate` with `confidence`. Queue frequent
  estimates for human review → promotion into the curated seed.

## 6. Build pipeline for the seed DB (offline, one-time + periodic)

1. Acquire IFCT 2017 ingredient table + USDA FDC (API/bulk) + NIN 2024 servings.
2. Define standard recipes for the top ~300–800 dishes (ingredient list + cooking yield/retention).
3. Compute per-100g energy/macros/micros per dish; fill missing nutrients from USDA.
4. Cross-validate against INDB / Kaggle (reference only); flag large deviations for review.
5. Emit `seed_foods.json` (+ a Supabase seed migration) with full `source/license/confidence`.
6. ~~Produce the filtered Indian OFF snapshot from the OFF bulk dump.~~ **NOT DONE — rejected by [ADR 0014](../adr/0014-off-live-lookup-only.md)**: OFF is live-lookup-only with a per-scan cache, so no OFF bulk pipeline exists.

Pipeline scripts live in `supabase/seed/` and are re-runnable as sources update.
