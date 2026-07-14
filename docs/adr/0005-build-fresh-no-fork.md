# 0005. Fork nothing. Build fresh from a permissive assembly kit.

**Status:** Accepted · **Date:** 2026-07 · **Supersedes:** an interim "fork Fud AI" recommendation

## Context
Three independent research sweeps looked for a production-grade base to white-label. Findings:

- **Permissive OSS nutrition apps barely exist.** The only production-grade one is **Fud AI** (MIT).
- **Paid templates are a trap.** The whole CodeCanyon Flutter nutrition category has items with 2–45
  lifetime sales, Laravel backends, no tests, no offline strategy. Envato's Regular Licence also requires
  the end product be distributed *free of charge*.
- **White-label fitness SaaS** gives no source code.

Fud AI was seriously evaluated and, judged on its README, **won**. Judged on its **source code**, it lost:
- **No backend at all.** Every AI call goes device → provider with the *user's own* API key. It is
  **BYOK-only**, which **structurally cannot support Sakama's free tier** — our core promise.
- **Storage is `UserDefaults`** (30 files; zero CoreData/SwiftData/SQLite). Not a database. Rewrite on day one.
- **210 lines of tests** for 27,665 lines of Swift.
- `ContentView.swift` is **4,389 lines**.
- Two native codebases (Swift + Kotlin), forever.

## Decision
**Fork nothing.** Build the Flutter client fresh, assembled from permissive components. **Port** Fud AI's
AI design (MIT permits it) as a **blueprint**, not a fork.

## Consequences
- We take the genuinely valuable part of Fud AI — its **prompts** (hard-won portion-estimation logic) and
  its **13-provider abstraction** — and port them to Dart in days, **without** inheriting the debt.
- We keep our architecture, our tests, and one codebase.
- **The "70% coverage" figure was a trap:** that 70% sat on foundations we would have had to replace.
- Attribution: retain Fud AI's MIT copyright notice in the Open Source Licenses screen.
