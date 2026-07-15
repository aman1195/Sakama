# Architecture Decision Records

Records of significant architectural decisions for Sakama, in the format from the `domain-modeling`
skill (`.agents/skills/domain-modeling/ADR-FORMAT.md`).

| # | Decision | Status |
|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-flutter-client-ios-first.md) | Flutter client, iOS-primary, Android-capable | Accepted |
| [0003](0003-supabase-offline-first-drift-powersync.md) | Supabase backend + offline-first Drift/PowerSync | Accepted |
| [0004](0004-closed-source-licence-stance.md) | Sakama is closed-source and commercial | Accepted |
| [0005](0005-build-fresh-no-fork.md) | Fork nothing; build fresh from a permissive assembly kit | Accepted |
| [0006](0006-litellm-gateway-byok-hybrid.md) | LiteLLM gateway with hybrid BYOK | ⚠️ Superseded by 0011 |
| [0007](0007-plan-engine-as-json-data.md) | Plans are JSON data, never hardcoded logic | Accepted |
| [0008](0008-indian-food-database-strategy.md) | Indian food DB: INDB + USDA + OFF, never IFCT | ⚠️ Partly superseded by 0012 |
| [0009](0009-freemium-monetization.md) | Freemium — core free, expensive AI metered | Accepted |
| [0010](0010-wedge-v1-scope-solo.md) | Wedge v1 (M0–M3), solo builder; launch at M3 | Accepted |
| [0011](0011-serverless-ai-gateway.md) | Serverless AI gateway (Edge Fn + managed gateway) | Accepted |
| [0012](0012-ship-bundled-food-data.md) | Ship-bundled food data for v1 (defer recompute) | Accepted |
| [0013](0013-validate-photosnap-before-build.md) | Validate PhotoSnap before build (spike-first) | Accepted |

**Grilling session (2026-07):** 0009–0013 came out of a `/grilling` pass that pressure-tested the plan
for a solo builder. It reversed/sharpened five decisions and reaffirmed one (PowerSync, 0003).
