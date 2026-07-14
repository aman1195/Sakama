# 0003. Supabase backend + offline-first via Drift and PowerSync

**Status:** Accepted · **Date:** 2026-07

## Context
Users log meals on trains, in kitchens, and on poor Indian mobile networks. Logging **must** work offline.
Research established that the **Supabase SDK has no true offline mode** — it requires connectivity for all
core operations. So offline-first needs a dedicated layer.

## Decision
- **Supabase** for Postgres, Auth (email/Apple/Google), Storage (meal photos), and Edge Functions.
- **Drift (SQLite)** as the local store and the **single source of truth**. The UI never reads the network
  directly.
- **PowerSync** as the sync engine (Supabase-endorsed): local write → upload queue → push; pull + merge.
- **RLS mandatory** on every user table (`auth.uid() = user_id`).

## Consequences
- Every feature must be designed local-first. This is a hard constraint, not a preference.
- Conflict policy: last-write-wins on `updated_at`; derived aggregates (daily totals) are recomputed, not merged.
- **Accepted dependency:** `powersync-service` (self-hosted) is **FSL-1.1** — source-available, not OSI. It
  does not contaminate our app code and permits commercial use, but we either pay PowerSync Cloud or
  self-host under a non-OSI licence.
- The CC0-licensed `supabase-todolist-drift` PowerSync demo seeds this layer with zero obligations.
