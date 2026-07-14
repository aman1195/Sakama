# Contributing to Sakama

Sakama is a **closed-source commercial product**. Contributions are internal.

## Before you start
1. Read [PRODUCT.md](PRODUCT.md) — the brand and the anti-references.
2. Read [CLAUDE.md](CLAUDE.md) — the non-negotiable engineering rules.
3. Read [DEVELOPER_STANDARDS.md](DEVELOPER_STANDARDS.md) — git, commits, PRs, security, testing.
4. Skim [docs/adr/](docs/adr/) — do not relitigate a decision without a new ADR.

## Workflow
1. Branch: `feature/SAK-<n>-<description>`.
2. Design first for anything non-trivial: use the **`codebase-design`** skill (design it twice), then
   record it with **`domain-modeling`** (ADR format).
3. TDD the pure logic (nutrition math, plan engine).
4. Run **`licence-guard`** if you added a dependency, vendored code, or touched food data.
5. Open a PR against `main`. Green CI + review required.

> **Approvals are not enforced today**, and that is a recorded deviation rather than an oversight: we have one
> human contributor, and GitHub rulesets are plan-gated on a free private repo. See the "Approvals" section of
> [DEVELOPER_STANDARDS.md](DEVELOPER_STANDARDS.md) for what actually protects `main`.

## The rules that get PRs rejected
- A GPL/AGPL dependency, or code copied from a copyleft app.
- A user table without RLS.
- A provider API key reachable from the client.
- Open Food Facts data merged into the proprietary food table.
- A feature that does not work offline.
