# ADR 0017 — Dual deployment: managed cloud and self-hosted

- **Status:** Accepted
- **Date:** 2026-08-27
- **Supersedes:** nothing. **Amends:** [ADR 0002](0002-flutter-client-ios-first.md) scope, [ADR 0011](0011-serverless-ai-gateway.md) deployment assumptions.

## Context

Sakama 1.0 assumed one deployment: a Flutter client against managed Supabase. The
2.0 vision adds a second, first-class deployment — Docker Compose and Helm, running
Postgres and a Node API server on hardware the user controls — and a React web
client that works without the mobile app.

This serves two user types that 1.0 had no answer for: the privacy-conscious
self-hoster (Type 5) and the developer/integrator (Type 6). It is also the
positioning against every commercial competitor, none of whom offer it.

## Decision

Support both deployments from one backend codebase and one data model.

| | Managed cloud | Self-hosted |
|---|---|---|
| Postgres | Supabase | Postgres 15 in Compose/Helm |
| Auth | Supabase Auth + OIDC | Same schema, OIDC-first |
| AI entry point | Edge Function (Deno) | Node endpoint, same contract |
| Sync | PowerSync | PowerSync (self-hosted service) |
| Target | Indian mobile-first users | Homelab, privacy-conscious, global |

The data model, the RLS policies and the AI request contract are identical. A
divergence between the two is a bug, not a variant.

## Consequences

### The moat ships with the image

This is the consequence that matters, and it has to be stated plainly rather than
discovered later.

The Indian food database is named as the primary moat. A self-hosted deployment is
a container the user runs on their own hardware. If the curated Indian table is
seeded into that container, then **the moat is redistributable by anyone who pulls
the image**, and a closed-source commercial licence does not practically prevent a
competitor from extracting a Postgres table they legitimately possess.

Three options were considered:

1. **Ship the full Indian table to self-hosters.** Simplest, best product, and it
   hands the moat away.
2. **Self-hosters get the permissive base only** (USDA CC0, plus live OFF lookup
   under [ADR 0014](0014-off-live-lookup-only.md)), with the curated Indian table
   available to cloud deployments. Preserves the moat; makes self-hosting a
   materially different product for the exact market the moat targets.
3. **Curated Indian data served over an authenticated API** to both deployments,
   never seeded into the self-hosted container. Preserves the moat, keeps one
   product, and breaks the self-hoster's "no cloud dependency" promise for that
   one subsystem.

**Chosen: option 3, with option 2 as the offline fallback.** A self-hosted instance
uses the curated Indian data through an authenticated lookup and degrades to
USDA plus OFF when the user declines that connection or runs fully air-gapped. The
data-sovereignty promise is kept for *user health data*, which is what Type 5
actually cares about, and is explicitly not extended to *our reference data*.

This distinction must be stated in the self-hosting documentation before the Docker
release, not after. A self-hoster who discovers it post-install will reasonably feel
misled.

### Reconciling with ADR 0011

[ADR 0011](0011-serverless-ai-gateway.md) chose a serverless AI gateway and explicitly
rejected a self-hosted proxy. A self-hosted deployment has no Edge Functions, so on its
face this ADR contradicts that one. It does not, and the distinction needs stating before
someone reads the two and picks whichever suits them.

ADR 0011's rejection was of **us operating a proxy** — a long-lived server we run, patch
and pay for, sitting between the client and the provider. That reasoning is unchanged for
the managed cloud, where the Edge Function remains the only AI entry point.

The self-hosted Node endpoint is not that proxy. It is the operator's own server, on their
own infrastructure, holding their own key. It performs the identical job the Edge Function
performs — verify the JWT, apply RLS, assemble context, enforce budget, decrypt BYOK,
redact — by importing the same module, and it is operated by the person whose data flows
through it.

Two consequences follow, and M11 must decide them explicitly rather than inherit them:

- **Whose key pays.** A self-hosted instance has no access to our provider account. Either
  the operator supplies a key (BYOK becomes mandatory rather than optional for self-hosted),
  or they authenticate to our gateway and we meter them. The first is simpler and matches
  the sovereignty promise; assume it unless M11 argues otherwise.
- **An air-gapped instance has no AI at all.** Every AI feature calls a provider over the
  internet. Offline degradation is already the rule for the mobile app ([ARCHITECTURE.md](../ARCHITECTURE.md)),
  so an air-gapped deployment is a permanently-degraded case of a state the product already
  handles, not a new one. It must be documented as such, not discovered.

### Other consequences

- Every schema change is now two migrations to keep in step, or one shared migration
  runner. Choose the shared runner. The four-file sync contract becomes five.
- The AI entry point exists twice (Deno Edge Function, Node endpoint). The request
  shaping, budget enforcement and BYOK handling must live in shared code that both
  import, or they will drift and one of them will lose a security control.
  Rule 3 of CLAUDE.md applies identically to both: no provider key in any client.
- RLS is now the isolation boundary in an environment we do not operate and cannot
  audit. Self-hosted misconfiguration is a support burden and a headline risk.
- Upgrade safety becomes a user-facing problem. Self-hosters upgrade on their own
  schedule with their own data. Pre-upgrade validation and an automated backup step
  are mandatory, and auto-updating containers must be documented as unsupported.

## Alternatives rejected

**Cloud only.** Cheaper to build and operate, and it concedes Types 5 and 6 plus
the entire positioning against commercial competitors.

**Self-hosted only.** Abandons the Indian mobile market, which is the primary
market and the reason the food database is worth building.

**Two codebases.** Would drift within a quarter, and the drift would be in RLS
policies and AI budget enforcement, which are the two places a divergence is a
security incident rather than an inconsistency.
