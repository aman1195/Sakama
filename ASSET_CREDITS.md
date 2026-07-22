# Asset & Data Credits

> **This file is a legal obligation, not a courtesy.** Sakama is closed-source and commercial, so every
> permissively-licensed asset and every open dataset we use must be attributed correctly. Keep this file
> accurate and surface it in-app (Settings → Open Source Licenses).
>
> Convention adopted from Fud AI's `ASSET_CREDITS.md` (MIT).

## Nutrition data

| Source | Licence | Obligation | How we use it |
|---|---|---|---|
| ~~**INDB** (Indian Nutrient Databank)~~ | ❌ **UNLICENSED + IFCT-derived** — NOT CC BY 4.0 (verified 2026-07-22) | **Cannot use** | **NOT bundled, NOT used.** The dataset has no licence (all-rights-reserved) and is derived from IFCT 2017. See docs/research/base-decision.md. Indian dishes come from AI estimation + a commercial licence instead. |
| **USDA FoodData Central** | **CC0 / public domain** | None (attribution requested) | Generic ingredients, nutrient gap-fill. Bundled. |
| **Open Food Facts** | **ODbL** (+ images CC BY-SA) | **Attribution + share-alike on derived databases** | Barcode / packaged-food lookup. **See the critical note below.** |
| **IFCT 2017** (ICMR-NIN) | ❌ **Not licensed for us** | NIN forbids electronic reproduction for a product without written permission | **NOT USED.** Do not ingest. |

### ⚠️ Critical: the Open Food Facts ODbL decision

ODbL's share-alike attaches to the **database**, not to our app code. It triggers when we create and
distribute a **Derivative Database**.

**Fud AI sidesteps this entirely by never bundling OFF data — it queries the API live, per barcode.**
That is a legitimate and materially lower-risk posture, and it is the alternative to our current plan.

Two options, and we must choose deliberately:

| Option | ODbL exposure | Cost |
|---|---|---|
| **A. Live API only** (Fud AI's approach) | **Low.** No derived database is distributed; attribution alone suffices. | Barcode lookup **requires connectivity**, and OFF rate-limits to 15 req/min. Conflicts with our offline-first promise. |
| **B. Bundle a filtered Indian OFF snapshot** (current plan) | **Higher.** We ship an OFF-derived database → share-alike likely applies to *that database*. | Barcode works offline. Must keep OFF rows in a **physically separate, source-tagged table**, never merged into the proprietary table, and be prepared to publish that table as open data. |

**Current decision: Option B, with strict containment** (see
[docs/adr/0008](docs/adr/0008-indian-food-database-strategy.md)). Our proprietary Indian food table stays
clean; only the OFF-derived table carries ODbL. **This requires counsel review before launch.** If counsel
is uncomfortable, fall back to Option A with an on-device cache of only the user's own scans (a cache of
individual lookups is a much weaker claim to a "derivative database" than a shipped snapshot).

**Required in-app attribution (either option):**
> "Barcode and packaged-food data from Open Food Facts contributors, available under the Open Database
> License (ODbL)."

## Code & libraries

Permissive dependencies (MIT / Apache-2.0 / BSD / CC0) — full list generated into the in-app
Open Source Licenses screen at build time. Notable:

| Component | Licence | Note |
|---|---|---|
| **Fud AI** — AI prompt design & multi-provider abstraction | **MIT** © 2026 Apoorv Darshan | **Ported as a blueprint, not forked** ([ADR 0005](docs/adr/0005-build-fresh-no-fork.md)). Retain this notice. |
| PowerSync `supabase-todolist-drift` demo | **CC0-1.0** | Public domain; seeds our sync layer. No obligation. |
| `openfoodfacts-dart`, Smooth App scanner | Apache-2.0 | Preserve NOTICE files. |
| `drift`, `fl_chart`, `supabase_flutter`, `health`, LiteLLM | MIT | Preserve copyright notices. |
| `mobile_scanner` | BSD-3 | |

**Never used** (recorded so nobody re-introduces them): OpenNutriTracker / wger / FoodYou / Waistline
(copyleft), `Best-Flutter-UI-Templates` (not actually MIT), LiteLLM's `enterprise/` directory (proprietary).

## Portion & dietary references
Standard Indian serving sizes (katori, roti, idli) follow **ICMR-NIN Dietary Guidelines for Indians (2024)**.
Cited as a reference; values re-derived, not reproduced.
