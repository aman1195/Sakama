# Sakama — System Architecture

> Grounded in July 2026 research (see [research-sources.md](research/sources.md)). Product context is
> in [CONTEXT.md](CONTEXT.md).

## 1. High-level topology

```
┌──────────────────────────────────────────────────────────────────┐
│  FLUTTER APP  (iOS-primary, Android-capable)                       │
│  Riverpod state · go_router · feature-first layers                 │
│                                                                    │
│  ┌────────────┐   reads/writes    ┌──────────────────────────┐     │
│  │ Presentation│ ───────────────▶ │ Local SQLite (Drift)      │     │
│  │ (widgets)   │ ◀─ reactive ─────│  = single source of truth │     │
│  └────────────┘   streams          └───────────┬──────────────┘     │
│                                                │                    │
│                       PowerSync replication ↕ (upload queue + pull) │
└────────────────────────────────────────────────┼───────────────────┘
                                                  │ HTTPS (Supabase JWT)
                       ┌──────────────────────────▼──────────────────┐
                       │  SUPABASE                                     │
                       │  · Postgres (RLS on every user table)         │
                       │  · Auth (email + Apple + Google)              │
                       │  · Storage (meal photos, per-user path)       │
                       │  · Edge Functions (Deno) = AI entry + BFF     │
                       │  · Vault/KMS (encrypted BYOK keys)            │
                       └───────────────┬───────────────────────────────┘
                                       │ HTTPS (usage-metered in the Edge Fn)
                       ┌───────────────▼───────────────────────────────┐
                       │  MANAGED AI GATEWAY (Cloudflare AI Gateway /   │
                       │  OpenRouter) — caching · rate-limit · routing  │
                       │  · multi-provider · BYOK. No self-hosted proxy │
                       └──┬───────────────┬───────────────┬─────────────┘
                          ▼               ▼               ▼
                   Gemini Flash      Claude Sonnet    OpenAI (fallback / BYOK)
                   (PhotoSnap)       (Vita coach)     — all on a PAID tier
```

> **⚠️ Superseded design note:** an earlier version of this doc put a **self-hosted LiteLLM proxy** at the
> centre. [ADR 0011](adr/0011-serverless-ai-gateway.md) replaced it with the serverless design above
> (Edge Function meters usage → managed gateway → provider). The metering that the proxy's "virtual keys"
> would have done now lives in the **Edge Function against the `ai_usage` table**. Section 5 below still
> describes the old proxy and will be rewritten when the AI layer is built (M3).

Three tiers: **Flutter client** (offline-first), **Supabase** (data + auth + Edge Function AI entry +
metering), **managed AI gateway**. Detail on the AI tier is in
[architecture/02-ai-layer.md](architecture/02-ai-layer.md).

## 2. Client architecture (Flutter)

**Confirmed stack (versions to re-pin at setup):**

| Concern | Choice | Version |
|---|---|---|
| State management | Riverpod (+ codegen) | 3.x |
| Routing | go_router (+ go_router_builder) | 17.3.0 |
| Local DB | Drift (SQLite) | latest |
| Offline sync | PowerSync (Supabase-endorsed) | latest |
| Backend SDK | supabase_flutter | 2.15.4 |
| Barcode | mobile_scanner | 7.2.0 |
| Food (OFF) client | openfoodfacts (Dart) | latest |
| Health / HealthKit | health | 13.3.1 |
| Steps | pedometer | latest |
| DI | get_it + injectable (or Riverpod) | latest |
| Monorepo (optional) | melos | latest |

**Feature-first layering** — each feature owns `data/ domain/ presentation/`:

```
lib/
  app/          router, root widget, provider/DI setup, theme
  core/         constants, env, error handling, base classes, nutrition math
  shared/       reusable widgets, cross-feature services & models
  features/
    onboarding/  auth/  dashboard/  diary/  photosnap/  barcode/
    water/  fasting/  weight/  workouts/  steps/  sleep/
    plan/  coach/  food_search/  settings/
      data/         models, data_sources (Drift DAO + Supabase), repository_impl
      domain/       entities, repository interfaces, use_cases
      presentation/ Riverpod notifiers, pages, widgets
```

## 3. Offline-first data flow (the core rule)

**Local SQLite is the single source of truth. The UI never reads the network directly.**

1. UI reads reactive Drift streams → instant, works offline.
2. Writes go to local Drift first, then into PowerSync's upload queue.
3. When online, PowerSync pushes mutations to Supabase Postgres.
4. PowerSync pulls server changes and merges into local SQLite.
5. **Conflict policy:** last-write-wins via per-row `updated_at`; server-side merge for sensitive
   aggregates (daily nutrition totals, weight). Logs are append-mostly, which minimizes conflicts.

Supabase's own SDK has **no** full offline mode — PowerSync is the layer that provides it. This is
why the food barcode cache, food search, and all logging must resolve from local Drift first.

## 4. Backend (Supabase)

- **Postgres** holds the canonical relational model ([architecture/01-data-model.md](architecture/01-data-model.md)).
- **RLS is mandatory** on every user-data table: `user_id uuid default auth.uid()` with
  `auth.uid() = user_id` policies for all of select/insert/update/delete. RLS is the primary
  data-isolation boundary for a multi-user health app.
- **Auth:** email/password + Sign in with Apple (required by Apple when any 3rd-party login is
  offered on iOS) + Google, via native flows → `signInWithIdToken`.
- **Storage:** meal photos at `meals/{user_id}/{uuid}.jpg`, protected by storage RLS. Client
  uploads compressed images and stores the returned path on the food-log row.
- **Edge Functions (Deno):** the backend-for-frontend and the single entry point to AI. They verify
  the JWT, enforce RLS-safe access, fetch/inject BYOK keys from Vault, shape requests, call the
  LiteLLM proxy, and persist results. They are **not** the AI gateway themselves (short-lived,
  stateless) — they front it.

## 5. AI tier (summary; full detail in 03)

- **LiteLLM proxy**, self-hosted on one small always-on instance (Fly.io / small VM / Cloud Run),
  is the gateway: virtual keys, hard budgets + RPM caps, BYOK header passthrough, provider routing,
  prompt caching, and a Postgres spend ledger.
- **Provider policy:** cheap model by default (Gemini Flash-class for PhotoSnap vision), escalate to
  Claude Sonnet for quality-sensitive coaching turns, all switchable by config. Benchmark vision
  models on a labeled Indian-food set before committing — portion estimation is the hard part.
- **BYOK hybrid:** non-BYOK users get a budgeted virtual key (keeps "free forever" viable and cost
  bounded); BYOK users' keys are stored encrypted (Vault/KMS) and forwarded per request, costing us
  ~$0. Keys never ship in or return to the client; scrub from all logs (OWASP M1).

## 6. Cross-cutting concerns

- **Privacy:** health data is sensitive. Self-hostable Supabase, no data selling, minimal
  permissions requested, BYOK for users who want full control. Aligns with the product promise.
- **Environments:** local (Supabase CLI + local Postgres) → staging → prod. Secrets via env, never
  committed. LiteLLM `config.yaml` holds provider keys server-side only.
- **Observability:** LiteLLM spend/latency logs to Supabase Postgres; client crash/analytics with a
  privacy-respecting tool (no PII, no health data in analytics events).
- **Testing:** Riverpod provider overrides for unit/widget tests; Drift in-memory DB for repository
  tests; golden tests for key screens; integration tests for the log→sync→pull loop.
- **CI/CD:** Flutter build + test on PR; Supabase migrations via CLI; store builds via Xcode/
  fastlane (iOS) and Play Console (Android).
