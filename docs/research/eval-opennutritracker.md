# Evaluation: OpenNutriTracker as a base for Sakama

> Deep-dive conducted July 2026 by cloning and reading the actual repository
> (https://github.com/simonoppowa/OpenNutriTracker), not its GitHub summary. Reviewed: `LICENSE`,
> `pubspec.yaml`/`pubspec.lock`, the project's own `CLAUDE.md` architecture doc, `README.md`, and the
> `lib/` source tree.

## 1. What it actually is

A mature, genuinely active Flutter calorie/nutrition tracker.

| Metric | Value |
|---|---|
| Codebase | **66,489 LOC**, 391 Dart files (`lib/core` 190, `lib/features` 201) |
| Stars / contributors | ~2,000★, 34 contributors |
| Latest release | **v1.5.0 (28 May 2026)**, build 58 — active |
| Flutter | 3.41.7 (via FVM) |
| Architecture | **Clean Architecture**, feature-based, three-layer (`data`/`domain`/`presentation`) |
| Platforms | iOS + Android |

It is a serious, well-engineered project with localization (9 languages), integration tests, an ADB
UI-driver test harness, accessibility identifiers, and CI. Not a toy.

## 2. Its actual stack (this is the crux)

| Concern | OpenNutriTracker | Sakama plan | Aligned? |
|---|---|---|---|
| State management | **flutter_bloc** (+ provider) | Riverpod | ✗ diverges |
| Dependency injection | GetIt | GetIt / Riverpod | ~ partial |
| Local database | **hive_ce** (NoSQL, AES-256, local) | Drift (SQLite) | ✗ diverges |
| **Cloud sync** | **NONE — local-only** | PowerSync offline-first sync | ✗ **fundamental** |
| **User accounts / auth** | **NONE** | Supabase Auth (email/Apple/Google) | ✗ **fundamental** |
| Supabase usage | **read-only food-search CDN only** (a hosted USDA FDC subset with full-text search) | full backend: auth + user data + storage + edge functions | ✗ **fundamental** |
| Barcode | mobile_scanner 7.2 | mobile_scanner 7.2 | ✓ |
| Charts | fl_chart | fl_chart | ✓ |
| Crash reporting | Sentry (opt-in) | TBD | ~ |
| **AI** | **NONE** | AI coach + PhotoSnap + plan gen (the moat) | ✗ **fundamental** |
| Food DB | OFF + USDA FDC | OFF + **Indian** (IFCT/INDB) curated | partial |
| Plan engine | none | flexible JSON plan engine (Type 1/2 users) | ✗ |

### Precise note on "scanning" (verified against source, re-scanned July 2026)
The app has **two kinds of code scanner**, and **no image/AI food recognition**:
- **Barcode scanner** (`lib/features/scanner/scanner_screen.dart`, `search_product_by_barcode_usecase`)
  — scan a packaged item to look it up; manual barcode paste fallback; attach a barcode to a custom
  meal for future recognition. This is a real, headline feature.
- **QR scanners** (`import_meal_scanner_screen.dart`, `import_activity_scanner_screen.dart`,
  `import_recipe_scanner_screen.dart`) — import a meal/recipe/activity another phone shared as a QR.
- **Meal/recipe photo** (`UserImagePickerTile` → `user_image_storage.dart`) — a **cosmetic, local-only
  image attachment**. No upload, no recognition.
- **No AI photo food recognition.** `pubspec.yaml` declares **zero** AI/ML/vision dependencies
  (no openai/gemini/anthropic/mlkit/tflite/tensorflow/google_ml). Every camera use reads a barcode or
  QR code. Photographing a plate to auto-derive nutrition (Sakama's "PhotoSnap") does **not** exist
  here and remains our differentiator.

### The single most important finding
**OpenNutriTracker is a local-only app.** All user data lives in an on-device, AES-encrypted Hive
database and is only movable via a manual zip export/import. Supabase is used **solely** as a
read-only backend to full-text-search a hosted USDA FDC food table (`SpFdcDataSource` →
`fdc_food`). There is **no user cloud storage, no authentication, no multi-device sync.**

This is a deliberate "privacy by locality" design, and it is elegant for what it is. But it is a
different architecture from Sakama, which requires cloud accounts, multi-device sync, and a
server-side AI layer. The parts of ONT that look reusable (the diary, the data model) sit on top of
Hive-local + Bloc foundations we are not using.

## 3. License — the hard blocker (confirmed by reading the file)

The `LICENSE` file is the **full, unmodified GNU GPL-3.0** (35 KB, standard text). Unlike wger, there
is **no App Store exception clause**. Consequences for a closed, commercial, store-distributed product:

1. **GPL-3.0 is incompatible with the Apple App Store.** The FSF has stated GPL software cannot be
   distributed through Apple's App Store (Apple's DRM/usage terms conflict with GPL freedoms).
2. **Copyleft is viral.** Forking ONT would force Sakama's entire source to be released under
   GPL-3.0 — incompatible with a proprietary product.
3. **Derivative-work risk on "clean-room" reuse.** Reading GPL code and closely reimplementing its
   structure/class design can still create a derivative work. Only genuine facts (scientific
   formulas) are safe to reuse; expression (code, file layout, class design) is not.

Forking or copying code is therefore off the table. Full stop.

## 4. What is genuinely valuable to LEARN (not copy)

The deep-dive is not wasted — ONT is the best available **reference** for the tracking core.

1. **Scope validation.** ONT already ships almost our entire M1+M2+M5 tracking core: calendar diary,
   macro + micronutrient panel (with DRI targets), barcode, custom meals, recipes, water tracker,
   fasting timer, weight trend chart, activity logging with MET calories, export/import. This proves
   our tracking-core milestones are very achievable and gives a concrete completeness checklist.
2. **Nutrition math (facts, safe to reference).** `lib/core/utils/calc/`: TDEE via the **IOM 2005**
   gender-specific equation; calorie goal = TDEE ± weight-goal adjustment (±500 kcal) + user offset +
   burned activity kcal; macro default split 60/25/15 carb/fat/protein; **MET** calc for activity
   burn. These are public scientific methods — we can use the same formulas (our plan currently
   specifies Mifflin–St Jeor; IOM 2005 is a documented alternative worth comparing).
3. **Data-model reference.** Their Hive box list (Config, Intake, UserActivity, User, TrackedDay,
   CustomMeal, Recipe, CachedOffMeal, WeightLog, WaterIntake, FastingSession) maps almost 1:1 onto our
   Postgres/Drift tables in [architecture/01-data-model.md](../architecture/01-data-model.md) — a useful cross-check that our schema
   is complete. Note their `TrackedDay` == our `diary_days` rollup; same idea.
4. **The hosted food-search pattern.** Their `SpFdcDataSource` (Supabase full-text search over a food
   table) validates our plan to serve food search from a hosted table. We extend it with Indian data.
5. **Engineering practices worth emulating** (as ideas, not code): stable accessibility identifiers
   for UI-driver tests, an ADB test harness, `envied` compile-time secret obfuscation, opt-in crash
   reporting with an App Store privacy manifest.

## 5. What it does NOT give us

Everything that defines Sakama, plus our core architecture:
- **No AI** — coach, PhotoSnap, plan generation: our entire moat, built from zero regardless.
- **No cloud sync / accounts / multi-device** — a core architectural pillar we chose.
- **No Indian food focus** — no IFCT/INDB, no katori/roti serving units.
- **No plan engine** — nothing for Type 1 (plan followers) or Type 2 (goal setters).
- **Different foundations** — Bloc (not Riverpod), Hive (not Drift+PowerSync), so even the parts that
  overlap would need reimplementing on our stack anyway.

## 6. Verdict

**The deep-dive strengthens the "do not fork" conclusion, and adds nuance.**

- ONT is the **best reference implementation of the tracking core** we will find. Use it to validate
  scope, cross-check our data model, and reference nutrition formulas. This is real, concrete value.
- But it cannot be a **base**: GPL-3.0 blocks store distribution and forces copyleft; it is local-only
  (missing sync, accounts, and the server-side AI layer that are pillars of our design); and it is
  built on Bloc + Hive rather than our Riverpod + Drift + PowerSync.
- **Posture:** treat ONT as **domain knowledge and UX/design reference only** — read for understanding,
  reimplement independently on our stack. Do not copy code, class design, or file structure (GPL
  derivative risk). Reuse only public formulas.

### One honest product question this surfaces
ONT proves a **local-only, no-account, privacy-by-locality** tracker is viable and simpler to ship.
Sakama deliberately chose cloud sync + accounts — partly because the AI layer needs a backend
anyway, and multi-device + backup are in the vision. That decision stands, but it is worth being
explicit that we are taking on more backend complexity than ONT precisely to enable AI, sync, and
accounts. If any of those were dropped, the local-only model would be materially simpler.

## 7. Concrete actions

- Keep our from-scratch scaffold decision ([README.md](../README.md)). Do not fork.
- Add ONT to references for: tracking-core feature completeness, data-model cross-check, and nutrition
  math (compare IOM 2005 vs Mifflin–St Jeor before finalizing default-target computation in
  [architecture/04-plan-engine.md](../architecture/04-plan-engine.md)).
- Continue harvesting only permissive code: `openfoodfacts-dart` + Smooth App barcode (Apache-2.0);
  IFCT/INDB datasets (verify terms); Fud AI (MIT) for the BYOK multi-LLM PhotoSnap pattern.
- Do **not** ingest ONT's hosted FDC Supabase table or any of its code.
