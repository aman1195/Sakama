# Decision: No White-Label Base. Build the Client, Buy the Data.

> **Status: DECIDED** (July 2026). Supersedes the "should we fork something?" question.
> Context: [eval-opennutritracker.md](eval-opennutritracker.md). Licensing detail:
> [architecture/03-food-database.md](../architecture/03-food-database.md).

## The constraint that drives everything

**Sakama is closed-source** (product owner decision). Therefore any base we adopt must be
**permissive (MIT / Apache-2.0 / BSD / CC0)** or a **paid commercial license**. All strong copyleft
is disqualified by definition: OpenNutriTracker (GPL-3.0), wger (AGPL), FoodYou (GPL), Waistline
(GPL).

## What we searched, and what we found

Three independent research sweeps (permissive OSS apps; permissive assembly components; paid
templates + data APIs) converged on the same conclusion.

### 1. Permissive open-source apps: the category is nearly empty
| Project | Stack | License | Verdict |
|---|---|---|---|
| **Fud AI** | **native Swift + Kotlin** | MIT | Only production-grade permissive tracker. **Not Flutter** — cannot lift code. No backend, no accounts, storage is `UserDefaults`/JSON. Bus factor 1. Author sells a competing premium tier. |
| FitBook | Flutter | MIT | Thin logger (~25% surface). No iOS build, no micros, no AI. |
| Smooth App | Flutter | Apache-2.0 | Not a tracker. **Harvest**, do not fork. |

**Fud AI is the only real candidate and we reject it**: adopting it means abandoning Flutter,
maintaining two native codebases forever, rewriting its persistence layer on day one, building the
entire backend anyway, and competing against a free, feature-identical original.

### 2. Paid templates / white-label SaaS: rejected
- **CodeCanyon Flutter nutrition templates**: items have **2–45 lifetime sales** (no production
  hardening). Mostly thin GPT-vision wrappers. The only one with a real backend ships **Laravel +
  MySQL** (we are Supabase). Typical architecture — `setState` god-widgets, logic in the UI layer, no
  tests, no CI, no offline strategy — costs more to untangle than to write fresh.
- **License gotcha**: Envato's **Regular License requires the end product be distributed free of
  charge**; any paid tier requires the **Extended License** (a multiple of the sticker price), one
  license per app. Instaflutter's "commercial rights **while active**" subscription is unacceptable
  for a shipped product.
- **White-label fitness SaaS** (Trainerize, FitBudd, Virtuagym, Passion.io): **no source code**, tenant
  on their backend, no differentiated AI possible. Built for gyms, not product companies. Skip.

### 3. The reframe
**The tracking core is not the bottleneck** — it is ~3–6 weeks of competent Flutter + Supabase work.
The real moats are:
1. the **Indian food database** with correct **portion semantics** (1 katori dal, 2 phulka, medium dosa),
2. **search relevance** over messy Indian food names,
3. the **AI layer** (PhotoSnap, Vita, plan generation).

**No template and no API supplies any of the three.** So: **build the code, buy the data.**

## DECISION

1. **Build the Flutter client ourselves**, assembled from permissive components (below). Do not fork
   any app. Do not buy a template as a foundation.
2. **Buy/licence the food data** rather than the code — that is where money and time actually convert
   into product.
3. Optionally spend ~$60 on 2–3 templates as **UI/UX design reference only**. Study the flows, then
   close the folder and never import from it. (Note: shipping any of their code would still require an
   Extended License.)

## The permissive assembly kit (~30–40% head start, zero copyleft exposure)

| Layer | Component | License | Why |
|---|---|---|---|
| **Offline core** | PowerSync demo **`supabase-todolist-drift`** | **CC0-1.0** | **Public domain, zero obligations.** Exactly our stack (PowerSync + Drift + Supabase) with schema + build config. Our hardest infra problem, seeded free. |
| Sync SDK | `powersync` | Apache-2.0 | Client SDK |
| Local DB | `drift` | MIT | SQLite |
| **Architecture** | **deliverzler** | MIT | Best permissive **Riverpod + layered DDD** reference (freezed, go_router, fpdart, full tests). Swap its Firebase data layer for Supabase, keep the architecture. |
| Shell / CI | `very_good_cli`, `very_good_workflows` | MIT | Flavors, l10n, analysis, CI. (Bloc-opinionated — rip that out.) |
| Auth | `supabase_auth_ui` + `supabase-flutter` | MIT | Email / Apple / Google screens, fastest legit path |
| Barcode + food lookup | `openfoodfacts-dart`; Smooth App `packages/scanner` | Apache-2.0 | Typed OFF API wrapper; pluggable ML Kit/zxing scanner abstraction |
| Charts | `fl_chart` | MIT | Weight trend, calorie rings, macro bars |
| Health/sensors | `health`, `mobile_scanner` | MIT / BSD-3 | HealthKit + Health Connect; barcode |
| **AI gateway** | **LiteLLM** | **MIT (except `enterprise/`)** | Deploy the OSS proxy via Docker; **never vendor `enterprise/`** (proprietary). Alt: Portkey gateway (MIT). Observability: Helicone (Apache-2.0). |

### Traps identified — do NOT use
- **Best-Flutter-UI-Templates** (22.7k★, its `fitness_app` is almost exactly our dashboard): **NOT MIT.**
  The raw LICENSE deletes "sell" from the grant and appends a non-commercial-flavoured clause. Ambiguous
  and unsafe for a commercial product. **Visual inspiration only — redraw.**
- **Syncfusion** Flutter charts: proprietary revenue-capped "community" licence, not permissive.
- Any repo with **no LICENSE file** = all rights reserved = unusable (several popular Flutter/Supabase
  starters fall here).

### Strategic dependency to accept knowingly
**PowerSync's self-hosted sync *service*** is **FSL-1.1-ALv2** (source-available, not OSI; converts to
Apache-2.0 after 2 years). It does **not** contaminate our app code (separate server process) and
explicitly permits commercial use — it only forbids building a competing sync service. But we either
pay **PowerSync Cloud** or self-host under a non-OSI licence. Accepted, with eyes open.

## Data strategy: buy the data (see [architecture/03-food-database.md](../architecture/03-food-database.md))

| Source | Licence / terms | Action |
|---|---|---|
| **INDB** (Indian Nutrient Databank) | ❌ **UNLICENSED (all-rights-reserved) AND derived from IFCT 2017** — verified from source 2026-07-22 (see below). NOT CC BY 4.0. | **DO NOT bundle.** The CC BY badge is on the *paper*, not the data; the GitHub dataset has no licence, and its base table is IFCT 2017 (re-imports the rule-6 risk). |
| **USDA FoodData Central** | **CC0 / public domain** | Free generic-ingredient base layer. Take it. |
| **Open Food Facts** | **ODbL** (attribution + share-alike **on the derived database**) | Barcodes / Indian packaged goods. **Keep in a physically separate schema**, never merged into our proprietary table. |
| **FatSecret Platform** | **Caching permitted.** Premier **free for startups under $1M revenue**, India locale | **Open here.** Best terms in the category. |
| **Bon Happetee** (Indian) | Sells a **full data licence (CSV/DB dump)** | **Negotiate.** India-native, 20k items, condition-tagged (diabetes, PCOS). Used by Swiggy, Apollo 24/7. Solves the India DB problem outright. |
| **IFCT 2017 (NIN)** | ⚠ **"No part ... can be stored or reproduced in any electronic format for creating a product without prior written permission."** | **DO NOT ingest.** Get written NIN permission. (INDB is NOT a way around this — it is itself IFCT-derived; see the INDB row.) |
| Edamam / Spoonacular / Nutritionix | ⚠ **Caching prohibited or 1-hour max; delete all data on cancellation** | **Structurally disqualified for a diary app.** A meal logged in March must render in December, offline. |
| Passio Nutrition-AI SDK | $99 / $599 / $2,999 per month, token-metered | Benchmark against our own vision model first; likely too costly for a free Indian-market tier. |

## Consequences
- The Flutter + Supabase + Riverpod + Drift/PowerSync + LiteLLM architecture in
  [ARCHITECTURE.md](../ARCHITECTURE.md) **stands unchanged**. This research validates it.
- [ROADMAP.md](../ROADMAP.md) M0 is now **seeded** rather than blank: start from the CC0 PowerSync/Drift
  demo and the deliverzler architecture instead of `flutter create`.
- **M2 (food database) changes materially**: generic base = **USDA (CC0)**, branded = **OFF (ODbL,
  isolated)**. The **Indian-dish** wedge does NOT come from INDB (unlicensed + IFCT-derived — see the
  data table and the correction note below); it comes from **AI estimation** (M2.4, confidence-tagged)
  plus a **commercially licensed** Indian dataset — open a conversation with **Bon Happetee** / confirm
  **FatSecret** India. UK CoFID (OGL v3.0) is a clean generic gap-fill, sourced direct from gov.uk.
- Ship an **Open Source Licenses** screen (Apache-2.0 requires preserving NOTICE files; MIT/BSD require
  the copyright notice). Wire `very_good_cli`'s licence checker into CI to catch any accidental
  GPL/AGPL transitive dependency.

## Must-verify before launch (legal)
1. ~~**INDB licence** — confirm CC BY 4.0 in writing.~~ **RESOLVED 2026-07-22: INDB is unusable.**
   Verified from primary sources — the dataset (GitHub `lindsayjaacks/Indian-Nutrient-Databank-INDB-`)
   has **no licence** (`license: None`, `/license` → 404) so it is all-rights-reserved, and its README
   shows it is **built from IFCT 2017** ("a master IFCT"). The CC BY 4.0 badge is on the *journal
   article* only. Bundling it would both redistribute all-rights-reserved data and re-import the IFCT
   rule-6 risk. **Do not bundle INDB.** Indian-dish coverage → AI estimation + a commercial licence.
2. **IFCT** — written NIN permission, or do not touch it (and INDB does not sidestep this).
3. **Open Food Facts ODbL** — counsel review of our derived-database posture (this is the single
   biggest legal risk in the stack, and it has nothing to do with GPL).
4. **FatSecret** — confirm India locale coverage and Premier Free eligibility in writing.
