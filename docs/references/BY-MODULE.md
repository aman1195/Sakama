# Reference Map — What to Look At When Building Each Module

> **When you start a module, or get stuck, come here first.** This maps each part of Sakama to the
> best real-world open-source implementation to learn from — with the exact file to open and, most
> importantly, **what you are legally allowed to do with it.**
>
> This is the actionable companion to the deep-dive evals in [../research/](../research/) (which explain
> *why*). Here we say *where to look and what you may take*.

## How to read the "Posture" column — READ THIS FIRST

| Posture | Meaning |
|---|---|
| ✅ **Copy** | Public domain (CC0). Copy verbatim, zero obligation. |
| ✅ **Adapt** | Permissive (MIT / Apache-2.0 / BSD). Use and modify the code in our closed product; **keep the copyright notice** (see [../../ASSET_CREDITS.md](../../ASSET_CREDITS.md)). |
| ⛔ **READ ONLY** | Copyleft (GPL/AGPL). **Read for understanding; never copy code, class design, or file structure.** Only *facts* (scientific formulas) are reusable. Copying would force all of Sakama to become open-source. |
| ⚠️ **Config only** | Take the *structure* of config/metadata files, not application code. |

> **Attribution ≠ a copyleft unlock.** Crediting a creator on the product website satisfies the
> permissive licences (MIT/Apache/CC0/CC BY) — that is exactly what they ask for. It does **not** grant
> permission to use GPL code. A GPL row flips from READ ONLY to Adapt **only** when the copyright holder
> (and, for multi-contributor projects, *all* contributors) give a **written relicensing grant**. Owner
> outreach for OpenNutriTracker is planned; until a written grant lands, its rows stay READ ONLY.
> When in doubt, run the **`licence-guard`** agent before merging.

---

## The map

### Foundation & architecture
| Building… | Reference | Where exactly | Licence | Posture | Take |
|---|---|---|---|---|---|
| App scaffold, folder layout, Riverpod + freezed + go_router patterns | **deliverzler** | repo root; `lib/` feature layering | MIT | ✅ Adapt | The layered `data/domain/presentation` structure; swap its Firebase for Supabase |
| CI / flavors / l10n scaffolding | **very_good_cli** output | generated project | MIT | ✅ Adapt | Flavor + analysis setup; rip out its bloc bias (we use Riverpod) |

### Offline & data (kept: PowerSync per [ADR 0003](../adr/0003-supabase-offline-first-drift-powersync.md))
| Building… | Reference | Where exactly | Licence | Posture | Take |
|---|---|---|---|---|---|
| Drift + PowerSync + Supabase sync wiring | **powersync.dart** demo | `demos/supabase-todolist-drift/` | **CC0** | ✅ **Copy** | The entire sync setup: schema, `build.yaml`, `database.dart`. Zero obligation. |
| Custom-JWT / auth-to-sync | powersync.dart | `demos/supabase-edge-function-auth/` | CC0 | ✅ Copy | Edge-function-issued token flow |
| Optional/tiered sync (free vs paid) | powersync.dart | `demos/supabase-todolist-optional-sync/` | CC0 | ✅ Copy | Gate sync behind a tier — relevant to freemium |
| Auth screens (email/Apple/Google) | **supabase_auth_ui** | package widgets | MIT | ✅ Adapt | The prebuilt auth UI |

### Food logging & database
| Building… | Reference | Where exactly | Licence | Posture | Take |
|---|---|---|---|---|---|
| Barcode scanner (camera → code) | **Smooth App** | `packages/scanner/` (ml_kit / zxing / shared) | Apache-2.0 | ✅ Adapt | The pluggable two-engine scanner abstraction |
| Open Food Facts API client | **openfoodfacts-dart** | package | Apache-2.0 | ✅ Adapt | Barcode + product lookup, nutriments parsing |
| Scan-to-product-card flow | Smooth App | `packages/smooth_app/lib/pages/scan/` | Apache-2.0 | ✅ Adapt | Continuous scan + camera lifecycle on real devices |
| **Food diary / meal-slot UX** | **OpenNutriTracker** | `lib/features/diary/`, `lib/features/home/` | **GPL-3.0** | ⛔ **READ ONLY** | Layout & interaction *ideas* only — redraw in our own code |
| **Micronutrient panel + DRI bars** | OpenNutriTracker | `lib/features/diary/` (micros), `lib/core/utils/calc/dri_reference.dart` | GPL-3.0 | ⛔ READ ONLY | Which micros to show + DRI *is a fact*; the code is not |
| **Nutrition math** (TDEE, MET, goal calc) | OpenNutriTracker | `lib/core/utils/calc/` | GPL-3.0 | ⛔ READ ONLY | **Formulas are facts, reusable** (IOM 2005 TDEE, MET). Do not copy the Dart. |
| Data-model completeness cross-check | OpenNutriTracker | its Hive box list (see [eval](../research/eval-opennutritracker.md)) | GPL-3.0 | ⛔ READ ONLY | Confirm our tables aren't missing anything |
| Indian dish-name / ingredient corpus | **6000+ Indian Recipes** (Mendeley) | CSV | CC BY 4.0 | ✅ Adapt (names/ingredients/tags) | ⚠️ Do **not** redistribute the scraped *instruction text* (Archana's Kitchen) |

### The AI moat
| Building… | Reference | Where exactly | Licence | Posture | Take |
|---|---|---|---|---|---|
| **PhotoSnap prompt design** | **Fud AI** | `ios/calorietracker/Services/GeminiService.swift` | **MIT** | ✅ **Adapt** (port to Dart) | The food-analysis JSON schema + portion-semantics prompt logic — re-vocabularise for Indian units |
| **Multi-provider / BYOK abstraction** | Fud AI | `ios/calorietracker/Models/AIProvider.swift` | MIT | ✅ Adapt | The provider enum + baseURL/fallback pattern |
| API-key-in-Keychain handling | Fud AI | `ios/calorietracker/Services/KeychainHelper.swift` | MIT | ✅ Adapt | Secure BYOK key storage pattern |
| **AI gateway / tier routing / metering** | **Helium** (he2-beta, own repo) | `backend/infrastructure/llm/tier_router.py`, `cloudflare_gateway.py`, `llm_service.py` | Internal | ✅ Port patterns | Tier→model chain, Cloudflare AI Gateway wiring, per-call BYOK key. **Port the pattern to a Deno Edge Function** ([ADR 0011](../adr/0011-serverless-ai-gateway.md)) |
| Freemium metering / entitlements | Helium | `backend/domain/billing_v3/` | Internal | ✅ Port patterns | Usage metering + tier gating shape |

### Sensors, charts, platform
| Building… | Reference | Where exactly | Licence | Posture | Take |
|---|---|---|---|---|---|
| Charts (weight trend, rings, macro bars) | **fl_chart** | examples | MIT | ✅ Adapt | Chart configs |
| HealthKit / Health Connect (steps, sleep) | **health** package examples + Fud AI | `HealthKitManager.swift` | MIT | ✅ Adapt | Permission flow + type mapping (v1.1 / M5) |
| **UI polish, don't copy** | Best-Flutter-UI-Templates | — | **NOT MIT** | ⛔ **NEVER USE** | Its `fitness_app` looks perfect but the licence is unsafe. Visual inspiration only; redraw. |

### Ship / release / ops
| Building… | Reference | Where exactly | Licence | Posture | Take |
|---|---|---|---|---|---|
| fastlane store metadata layout | **OpenNutriTracker** | `fastlane/metadata/android/en-US/` | GPL-3.0 | ⚠️ Config only | The *structure* of title/description/changelog files, not app code |
| Per-platform release workflows | **Fud AI** | `.github/workflows/ios-release.yml`, `android-release.yml` | MIT | ✅ Adapt | Split iOS/Android release CI |
| Release keystore fingerprint publishing | OpenNutriTracker | `RELEASE.md`, `.github/workflows/update-release-fingerprint.yml` | GPL-3.0 | ⚠️ Config only | The process, not code (see [../MOBILE.md](../MOBILE.md)) |
| CocoaPods-flaky-CI fallback | OpenNutriTracker | `.github/scripts/pod_install_with_targeted_fallback.sh` | GPL-3.0 | ⛔ READ ONLY | Understand the problem; write our own script |

---

## Quick lookup by "I'm building…"

- **the sync layer** → PowerSync `supabase-todolist-drift` demo (CC0, copy it)
- **the AI photo prompt** → Fud AI `GeminiService.swift` (MIT, port it)
- **the AI gateway** → Helium `tier_router.py` + `cloudflare_gateway.py` (port the pattern to Deno)
- **barcode** → Smooth App `packages/scanner` + openfoodfacts-dart (Apache, adapt)
- **the diary / micronutrient UX** → OpenNutriTracker (GPL — look, learn, redraw)
- **nutrition math** → OpenNutriTracker `calc/` (GPL — but the formulas are facts, reuse those)
- **auth screens** → supabase_auth_ui (MIT, adapt)
- **charts** → fl_chart (MIT)
- **release/CI** → Fud AI workflows (MIT) + OpenNutriTracker fastlane structure (config only)

## Maintenance
When a new reference proves useful, add a row **with its licence posture** — that column is not optional.
Credits for every permissive source belong on the product website and in
[../../ASSET_CREDITS.md](../../ASSET_CREDITS.md).
