# 0002. Flutter client, iOS-primary, Android-capable

**Status:** Accepted · **Date:** 2026-07

## Context
The product brief contradicted itself: it listed "iOS native app" as a feature while repeatedly citing
Flutter plugins. Both stores are targets. The product owner clarified: **iOS is the primary focus, but
Android matters.**

The alternative seriously considered was forking **Fud AI** (MIT, a shipping native Swift + Kotlin AI
nutrition app covering ~70% of our surface). See [0005](0005-build-fresh-no-fork.md).

## Decision
Build the client in **Flutter**. One codebase serving both stores, iOS-first in polish and release order.

## Consequences
- Every feature ships once, not twice. Fud AI's two-codebase model would have doubled delivery cost forever.
- We forgo native-only niceties (Watch app, deep widgets) at v1; these are post-v1 additions.
- Stack: Riverpod (state), go_router (routing), Drift (local DB), fl_chart (charts).
