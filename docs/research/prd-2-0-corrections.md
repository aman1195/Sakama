# Corrections to the Sakama 2.0 PRD

Reviewed 2026-08-27 against the repository and against primary sources. The 2.0 vision is adopted
into `PRODUCT.md`, `docs/CONTEXT.md`, `docs/ROADMAP.md`, `docs/ARCHITECTURE.md` and
[ADR 0017](../adr/0017-dual-deployment-cloud-and-self-hosted.md), **with the corrections below
applied**. Where this file and the PRD disagree, this file is correct.

---

## 1. INDB is not usable. This is the important one.

**PRD §7.4** lists INDB (Indian Nutrient Databank) as licence "Usable", priority "P0 — primary
Indian source". **PRD §8** then builds the entire primary-moat section on it. **PRD §14** does not
list it as a risk.

All of that is wrong, and it reverses a decision already taken and verified.

Verified from source on 2026-07-22 (see [base-decision.md](base-decision.md)):

- The INDB **dataset carries no licence at all**. No licence means all rights reserved, not
  permissive. It is not CC BY 4.0; documents claiming otherwise are wrong.
- INDB is **derived from IFCT 2017**. NIN forbids electronic reproduction of IFCT in a commercial
  product without written permission, so bundling INDB re-imports precisely the risk that
  prohibition creates.

This is the single largest legal exposure in the stack, and it is not a theoretical one: it sits
inside a closed-source commercial product headed for two app stores.

**The correct sourcing, unchanged from CLAUDE.md rule 6:**

| Need | Source | Licence |
|---|---|---|
| Generic base | USDA FoodData Central | CC0 |
| Indian dishes | AI estimation (M2.4) + a commercially licensed dataset (Bon Happetee / FatSecret) | Commercial, per contract |
| Barcode / packaged | Open Food Facts, **live lookup only** ([ADR 0014](../adr/0014-off-live-lookup-only.md)) | ODbL, isolated in `off_foods` |

Read IFCT and INDB for domain understanding. Never ingest either.

## 2. ODbL isolation is stricter than the PRD describes

**PRD §8.4** describes keeping OFF data in a separate `off_foods` table. Correct, but incomplete.

[ADR 0014](../adr/0014-off-live-lookup-only.md) goes further: OFF is **live lookup only**, and no
OFF-derived database is distributed at all. The PRD's §7.4 line implying a bundled OFF barcode
corpus would create exactly the derived database ADR 0014 exists to avoid.

`off_foods` is a local cache of what the user personally looked up, not a shipped dataset.

## 3. Self-hosting gives the moat away unless it is bounded

**PRD §6.1** makes self-hosted Docker and Helm first-class. **PRD §8** calls the Indian food
database the primary moat. **PRD §11** keeps the licence closed-source commercial.

Those three are in tension and the PRD does not resolve it. A self-hosted deployment is a container
running on hardware we do not control. Seed the curated Indian table into it and the moat is
redistributable by anyone who pulls the image; a closed-source licence does not practically stop a
competitor extracting a Postgres table they legitimately possess.

Resolved in [ADR 0017](../adr/0017-dual-deployment-cloud-and-self-hosted.md): curated Indian data
reaches self-hosted instances over an authenticated lookup, never seeded, degrading to USDA plus
OFF for an air-gapped instance. **This must be documented before the Docker release.** A
self-hoster who discovers it after installing will reasonably feel misled.

## 4. Exercise calories: the PRD does not say where the number comes from

**PRD §7.1** lists "calories burned" under the Exercise module without specifying its source.

That number is subtracted from the day's calorie target, so a wrong one changes what somebody eats.
Two common approaches are both wrong:

- Asking the LLM for a burn. It invents a plausible number with no measurement behind it.
- A per-activity kcal/hour constant. Weight-blind: at 40 minutes of running a 55 kg and a 95 kg
  user differ by roughly 270 kcal.

Implemented instead (`app/lib/features/workouts/domain/energy_burn.dart`): the standard MET form
against the user's most recent weigh-in, returning **null — never 0** — when the activity is
unknown, the duration missing, or the body weight unknown. The `log_workout` tool schema has no
`energy_kcal` field and the parser would not read it if it did.

## 5. Milestone numbering

**PRD §13** renumbers the milestones (M4 plan engine + cycle, M5 wearables, M6 family + MCP +
self-hosting, M7 polish, M8 hardening). The repository already has M0–M7 with different contents,
and shipped work references those numbers in ADRs, commits and PR history.

Renumbering would invalidate every existing reference. `docs/ROADMAP.md` therefore keeps M0–M7 as
they are and appends **M8 whole-health, M9 wearables, M10 family, M11 second deployment, M12
localisation and launch**. The content matches the PRD; only the labels differ.

## 6. Smaller items

- **§4.2 and §11** say "10 concurrent family users without degradation" for self-hosted. Worth
  pinning to a load test rather than an assertion; a Postgres with PowerSync replication and ten
  active sync clients on 2 vCPU is not obviously fine.
- **§15** targets 500+ self-hosted instances within 6 months, measured by Docker Hub pulls. Pull
  counts measure pulls, including CI and re-pulls, not instances. Either accept it as a directional
  proxy or add opt-in telemetry, which conflicts with the privacy promise. Accepting the proxy is
  the honest choice.
- **§9.2** shows BYOK keys fetched from Vault into the Edge Function. Correct, and the redaction
  requirement (OWASP M1) should be stated there too, not only in §11.
