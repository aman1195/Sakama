# Evaluation: Fud AI as a base for Sakama

> Deep-dive July 2026: cloned https://github.com/apoorvdarshan/fud-ai and read the source.
> Companion to [eval-opennutritracker.md](eval-opennutritracker.md) and [research/base-decision.md](base-decision.md).

## Verdict up front

**Do NOT fork it. Port it as a blueprint.** (MIT explicitly permits both; the blueprint path is
strictly better.)

Judged on its README and feature list, Fud AI wins. **Judged on its source code, it loses.** The deep
dive is exactly what surfaced the difference.

## What it is

| Metric | Value |
|---|---|
| License | **MIT** (verified: `Copyright (c) 2026 Apoorv Darshan`) — genuinely forkable, closeable, sellable |
| iOS | Swift/SwiftUI — **94 files, 27,665 lines** |
| Android | Kotlin/Compose — **110 files, 29,748 lines** |
| Total | ~57k lines across **two separate codebases** |
| Extras | Apple Watch app, widgets, share extension, Siri logging, web landing |
| Shipped | Live on App Store + Play Store, 47 releases |

## The genuinely excellent parts (worth taking)

### 1. The AI provider abstraction — `Models/AIProvider.swift`
A clean enum over **13 providers**, each with `baseURL`, model list, and icon:
Gemini, OpenAI, Anthropic, xAI, OpenRouter, Together, Groq, Hugging Face, Fireworks, DeepInfra,
Mistral, **Ollama (local)**, and **Custom OpenAI-compatible**. Most are OpenAI-compatible so they share
one code path; Gemini/Anthropic are special-cased. There is **provider fallback** logic
(`fallback.baseURL` / `fallback.apiKey`) for resilience.

This is essentially **LiteLLM reimplemented client-side**, and it is precisely the BYOK multi-provider
architecture we specified. Excellent reference.

### 2. The prompts — `Services/GeminiService.swift` (1,248 lines) — **the crown jewel**
Months of hard-won last-mile refinement that we would otherwise pay for in trial and error. Examples of
real accumulated wisdom in the food-analysis prompt:
- A strict JSON shape (`foodAnalysisJSONShape`) with separate variants for photo / text / nutrition-label.
- Sophisticated **portion semantics**: `unit_options` for slice/piece (pizza, cake, bread), ml/cup/fl-oz
  (drinks, soup), tbsp/tsp (spooned foods), can/packet (packaged).
- *"For a whole or mostly-whole divisible food like cake, pie, or pizza, **count the visible
  pieces/slices** and derive `grams_per_unit` from `serving_size_grams / quantity`. If N slices are
  visible, return quantity N."*
- Explicit guards against the model copying sample numbers from the schema.

This is exactly the class of problem we must solve for Indian portions (katori, roti, idli, dosa). The
*structure* transfers directly; we swap the Western unit vocabulary for the Indian one.

### 3. Other reusable design
- `KeychainHelper` — API keys in the Keychain, not UserDefaults. Correct.
- `HealthKitManager` (834 lines, 45 HK type references) — substantial, bidirectional HealthKit mapping.
- `CoachTools` — tool-use for the coach. `WeightAnalysisService` — trend forecasting.

## The disqualifying parts (why we must not fork)

### 1. ⛔ No backend at all — and this breaks our core promise
Grep for any server (`supabase|firebase|backend|amplify`) returns **nothing**. Every AI call goes
**device → provider directly**, authenticated with **the user's own API key** from the Keychain.

That means Fud AI's product model is **BYOK-only: every user must bring an API key.**

**Sakama's core promise is the opposite** — "free forever, better AI than HealthifyMe" — which
requires *us* to pay for AI for users who do not BYOK, routed through our own metered proxy
([architecture/02-ai-layer.md](../architecture/02-ai-layer.md)). Fud AI's architecture **structurally cannot support a free tier.**
Forking it means rebuilding the AI routing through our LiteLLM proxy anyway — which is the main thing
we would have been forking it *for*.

### 2. ⛔ Storage is `UserDefaults`. There is no database.
Verified: **UserDefaults referenced in 30 files. Zero** CoreData, zero SwiftData, zero SQLite, zero GRDB.

`UserDefaults` is a preferences store, not a database. Persisting years of food logs as JSON blobs means
whole-blob rewrites on every save, no indexes, no queries, no migrations, and performance that degrades
with the very engagement we are trying to create. **This must be rewritten on day one** — and it is the
foundation everything else sits on.

### 3. ⛔ Effectively no tests
**210 lines of test code for a 27,665-line app.** For a health product handling personal data and
nutrition math, inheriting 57k lines with no safety net is a large, permanent maintenance liability.

### 4. ⛔ Architecture debt
`ContentView.swift` is **4,389 lines**. A SwiftUI god-file at that size is the opposite of the clean,
extensible layering we need to bolt on a sync engine, a plan engine, and an Indian food database.

### 5. ⛔ Two native codebases, forever
Every feature built twice (Swift + Kotlin). Android already trails iOS. This permanently doubles our
delivery cost and contradicts the one-codebase rationale for Flutter.

## The trap in the "70% coverage" number

The 70% figure is real but **misleading**, because that 70% **sits on foundations we must replace**:

| Layer | Fork gives us | Reality |
|---|---|---|
| AI prompts + provider abstraction | ✅ genuinely valuable | **Portable without forking** |
| AI routing / architecture | ⛔ BYOK-only, no server | Must rebuild for our free tier |
| Persistence | ⛔ UserDefaults | Must rewrite day one |
| Backend / accounts / sync | ⛔ none | Build regardless |
| Indian food DB, plan engine | ⛔ none | Build regardless |
| Tests | ⛔ ~none | Inherit the debt |
| Language | ⛔ Swift + Kotlin ×2 | Wrong stack, doubled forever |

Strip out what we must replace, and **what actually remains reusable is the prompts and the provider
enum** — both of which we can port legally in **days**, under MIT, **without inheriting a single line of
the debt**.

**A fork buys us the liabilities and leaves the value on the table. A port takes the value and leaves the
liabilities.**

## DECISION: Hybrid — stay on Flutter, use Fud AI as the AI blueprint

1. **Keep Flutter + Supabase + Riverpod + Drift/PowerSync** ([ARCHITECTURE.md](../ARCHITECTURE.md)).
   Unchanged.
2. **Port Fud AI's AI design into Dart** (MIT permits this; retain the copyright notice in our
   open-source-licenses screen):
   - the **13-provider abstraction** → our LiteLLM proxy config + a Dart provider enum for BYOK
   - the **food-analysis JSON schema** and the **portion-semantics prompt logic** → re-vocabularized for
     Indian units (katori, roti, idli, dosa, phulka)
   - the photo / text / nutrition-label prompt variants, and provider fallback
   - `HealthKitManager`'s type mapping → the Flutter `health` package
3. **Route AI through our own proxy** so non-BYOK users get AI free (our differentiator over Fud AI),
   with BYOK as an option (their model as our power-user tier).

## What this costs us versus forking
Forking would have "saved" the tracking UI. But we would have paid with: the wrong language ×2, a storage
rewrite, no tests, a god-file, and an AI architecture that cannot serve a free tier. The blueprint path
gives us the single most valuable asset in the repo — **the prompts** — for the cost of reading them.

## Attribution
MIT requires we retain the copyright notice. Ship an **Open Source Licenses** screen crediting
`Fud AI — Copyright (c) 2026 Apoorv Darshan (MIT)` for any ported design.
