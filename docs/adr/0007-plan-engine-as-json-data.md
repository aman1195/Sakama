# 0007. Plans are JSON data, never hardcoded logic

**Status:** Accepted · **Date:** 2026-07

## Context
Sakama must serve three user types: plan-followers (bring a protocol), goal-setters (want AI to generate
one), and casual trackers (no plan). A hardcoded "4-week detox" would serve exactly one person.

## Decision
A plan is a **JSON config stored in the database** (`user_plans.config`) and *interpreted* by the app. It
defines day types, per-day-type targets, allowed/blocked foods, fasting windows, checklists, and
declarative rules. A diabetic plan, a muscle-gain plan, and a Tuesday-reset detox are the **same engine
reading different JSON**.

## Consequences
- The LLM can generate entirely new plans, and users can import their own, with **zero app changes**.
- `schema_version` gates the interpreter; unknown fields and unknown rule effects are **skipped, never
  fatal** — so AI can propose richer plans than the current client understands without breaking it.
- The only nutrition logic in code is default-target computation (Mifflin–St Jeor + activity factor) for
  users with no active plan.
