# Food seed pipeline

Re-runnable scripts that build the bundled food reference data
(`app/assets/seed/`). Loaded once into the local `foods` table by
`FoodRepository.ensureSeeded` (version-gated — bump `FoodRepository.seedVersion`
when the data changes so existing installs reload).

## USDA SR Legacy — `usda_ingest.py`

**Licence: CC0 (public domain).** No attribution or share-alike obligation.

```sh
# 1. Download the bulk dataset (public, no API key):
curl -O https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip
unzip FoodData_Central_sr_legacy_food_json_2018-04.zip
# 2. Transform -> compact, source-tagged asset:
python3 usda_ingest.py FoodData_Central_sr_legacy_food_json_2018-04.json \
    ../../app/assets/seed/foods_usda.json
```

Emits ~7,756 rows tagged `source='usda_fdc', licence='CC0', confidence=0.9`.
source/licence/confidence are constant for USDA, so they are set by the app
loader, not repeated per row in the asset.

## Not yet ingested

- **Indian dishes** (the wedge) — NOT from INDB (unlicensed + IFCT-derived; do not bundle, see
  CLAUDE.md rule 6). Covered by **AI estimation** (M2.4) + a **commercially licensed** dataset
  (FatSecret / Bon Happetee — a business action).
- **Open Food Facts** (ODbL) — branded/barcode. Kept in the SEPARATE
  `off_foods` table (CLAUDE.md rule 5). Lands in M2.3.
- **IFCT 2017** — NEVER ingest (NIN prohibition, CLAUDE.md rule 6).
