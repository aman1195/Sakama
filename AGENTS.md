# AGENTS.md

The agent capabilities ("superpowers") installed in this repository, and when to reach for each.

Engineering context and hard rules are in [CLAUDE.md](CLAUDE.md). Product and brand are in
[PRODUCT.md](PRODUCT.md).

---

## Skills — `.agents/skills/`

**26 skills**, merged from two internal reference repos: **ModelBeat** (the `mattpocock/skills` set,
tracked in [skills-lock.json](skills-lock.json)) and **he2-beta / Helium**. React/Next-specific skills
from Helium (`next-best-practices`, `vercel-react-best-practices`, `transitions-dev`, `react-doctor`,
`composio`) were **deliberately not copied** — they are inert for a Flutter client. Two web-only skills that
*were* copied have since been **deleted**: `benchmark` (Core Web Vitals / Next.js) and
`web-design-guidelines` (Web Interface Guidelines). See [docs/MOBILE.md](docs/MOBILE.md).

> **Sakama is a MOBILE app.** ModelBeat and Helium are **web** projects — take their *process* (git, ADRs,
> TDD, review), never their platform tooling. For **mobile** conventions the references are
> **OpenNutriTracker** and **Fud AI**.

### From Helium (he2-beta)
| Skill | Use when |
|---|---|
| **system-design** | Designing a system end to end. Pairs with `codebase-design`. |
| **zoom-out** | You are lost in the weeds and need to re-anchor on the goal. Use it when a decision starts feeling circular. |
| **diagnose** | Structured diagnosis of a failure. |
| **compress** | Condensing a large context or document without losing signal. |
| **skill-creator** | Authoring a new skill for this repo. |
| **caveman** / **caveman-commit** / **caveman-review** | Blunt, no-ceremony commit and review passes. |
| **emil-design-eng** | Design-engineering judgement (UI polish, motion, the invisible details). **Web examples — take the taste, not the CSS.** Pair with `impeccable` and [docs/DESIGN.md](docs/DESIGN.md). |

### From ModelBeat (mattpocock/skills)

### Design & architecture
| Skill | Use when |
|---|---|
| **codebase-design** | Designing a new subsystem. Includes `DESIGN-IT-TWICE.md` (produce two designs before choosing) and `DEEPENING.md`. Use for the plan engine, the sync layer, the AI gateway. |
| **domain-modeling** | Modelling the domain properly. Ships `ADR-FORMAT.md` and `CONTEXT-FORMAT.md` — **this is the format `docs/adr/` follows.** |
| **improve-codebase-architecture** | Periodic architecture health check. Emits an HTML report. |
| **prototype** | Spiking something quickly. Has separate `UI.md` and `LOGIC.md` tracks — use `UI.md` for capture-flow experiments. |

### Quality
| Skill | Use when |
|---|---|
| **tdd** | Writing tests. Ships `tests.md`, `mocking.md`, `refactoring.md`. Sakama's nutrition math and plan engine are pure logic — **TDD them.** |
| **diagnosing-bugs** | A bug is non-obvious. Forces a hypothesis-driven approach instead of guess-and-patch. |

### Thinking & pressure-testing
| Skill | Use when |
|---|---|
| **grilling** / **grill-me** / **grill-with-docs** | **Before committing to a plan.** Interrogates a design relentlessly. Given how much this project's assumptions have already shifted under research, use this on any big call. |
| **ask-matt** | Second opinion on an engineering judgement. |
| **teach** | Building understanding of an unfamiliar area (ships glossary/mission/learning-record formats). |

### Workflow
| Skill | Use when |
|---|---|
| **to-prd** | Turning an idea into a product requirements doc. |
| **to-issues** | Breaking a plan into tracked issues. |
| **triage** | Sorting an incoming pile of bugs/requests. |
| **handoff** | Ending a session cleanly so the next one resumes fast. |
| **writing-great-skills** | Authoring a new skill. |
| **setup-matt-pocock-skills** | Re-syncing / installing the skill set. |

## Design skill — `.claude/skills/impeccable/`

A deep visual-craft skill with a large reference library (`brand`, `craft`, `critique`, `colorize`,
`animate`, `delight`, `harden`, `distill`, `audit`, and more).

**Use it for the client UI.** Sakama's differentiator is partly *feel* — the capture flow must be
effortless and the coach must feel warm, not clinical. Pair it with [docs/DESIGN.md](docs/DESIGN.md)
(which records what we take from Fud AI and HealthifyMe) and [PRODUCT.md](PRODUCT.md) (brand,
anti-references).

## Custom agent — `.claude/agents/licence-guard.md`

**Sakama-specific, and load-bearing.** Sakama is closed-source and commercial, so licence contamination is
an existential risk rather than a hygiene issue. Run this agent **before merging anything that adds a
dependency, vendors third-party code, or touches food data.**

It gates the three hazards this project has actually researched and confirmed:
1. **Copyleft contamination** (GPL/AGPL → would force open-sourcing the entire product).
2. **Open Food Facts ODbL** share-alike on derived databases (keep OFF rows in a separate, tagged table).
3. **IFCT 2017** — NIN forbids electronic reproduction for a product without written permission.

It also checks health-data privacy: no API keys in the client, BYOK keys encrypted and never logged, RLS
on every user table, and no health PII in analytics.

> ModelBeat's `compliance-checker` / `compliance-fixer` agents were **deliberately not copied** — they are
> hard-wired to ModelBeat's `compliances/STEERING.md` and its hook scripts, and encode SOC2/PCI concerns
> for an AI gateway. Sakama's risks are different. `licence-guard` replaces them.

---

## Suggested usage patterns

- **Starting a subsystem** → `codebase-design` (design it twice) → `domain-modeling` (write the ADR) →
  `tdd`.
- **About to commit to a big decision** → `grilling` first. This project has already reversed two
  confident conclusions under scrutiny; assume the third is lurking.
- **Touching the UI** → `impeccable` + `docs/DESIGN.md`.
- **Adding any package or food data** → `licence-guard` before merge. No exceptions.
- **Ending a session** → `handoff`.
