# 0001. Record architecture decisions

**Status:** Accepted · **Date:** 2026-07

## Context
Sakama's foundational decisions (stack, licence stance, whether to fork an existing app) were each made
after substantial research, and **two of them reversed under scrutiny**. Without a written record, the
reasoning is lost and the reversals get re-litigated.

## Decision
Record every significant architectural decision as an ADR in `docs/adr/`, numbered and immutable. When a
decision changes, write a **new** ADR that supersedes the old one rather than editing history.

## Consequences
- The "why" survives staff turnover and context loss.
- Reversals are visible and auditable, not silent.
