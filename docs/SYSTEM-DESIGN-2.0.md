# Sakama 2.0 — System Design (Reconciled)

> **v1, 2026-08-31.** The adopted system design for Sakama 2.0, reconciling the owner-supplied
> system design document (the "source design": a Node.js modular monolith with PostgreSQL, Redis,
> BullMQ, Typesense, and a custom AI gateway) with the shipped architecture (offline-first Flutter
> + Drift + PowerSync + Supabase serverless, ADRs 0003/0011/0014/0017). Companion to
> [UX-SPEC-2.0.md](UX-SPEC-2.0.md); where this document and an ADR disagree, the ADR wins until
> amended.

## Decision log

| # | Topic | Ruling |
|---|---|---|
| S1 | Overall architecture now | **Adapted.** The source design's own ADR-004 (offline-first mobile, SQLite/Drift, sync queue, idempotency) is the shipped architecture. Its server-centric request paths (`GET /dashboard`, server summaries, Redis caches) are replaced by local Drift reads; PowerSync IS the sync queue, retry loop, and idempotency layer the source design specifies by hand. |
| S2 | Food data model | **Refused — owner-confirmed licence violation.** No single federated `foods` table, no caching external providers into the main catalogue, no provenance-free rows. The shipped model stands: separated `off_foods`, pointer-only saves, `source`/`licence`/`confidence` on every row, meals with zero nutrition. |
| S3 | Vita voice | **Adopted — voice-first agent + chat (owner ruling).** Full conversational loop: speech in, agent reasoning with tools, spoken reply, barge-in interruption. Adapted to the stack: on-device STT and on-device TTS, agent through the existing gateway (§3). Cloud STT/TTS and the WebSocket voice server are the M11/premium path. |
| S4 | AI gateway | **Kept serverless (ADR 0011).** The source design's gateway responsibilities (model tiering, fallback, retry, timeout, token/cost tracking, budget caps) are adopted as requirements on the existing Edge Function + OpenRouter path, not as a self-hosted proxy. Several already exist (`ai_usage` budgets, accurate-model-first fallback #134). |
| S5 | Custom JWT auth, Redis, BullMQ, Typesense, K8s, multi-region | **Deferred to M11+.** Not built for the mobile product; filed as the second-deployment scale path (§6). Supabase Auth + anonymous-first stands. |
| S6 | Server-side analytics workers | **Adapted to local-first.** Pre-aggregation, streaks, and the weekly digest compute on device from Drift (the UX spec's insight engine). Server analytics appear only with the M11 web client. |
| S7 | Notification service | **Adapted to local-first.** Reminders and the morning nudge are computed on device and scheduled as local notifications. No FCM/APNs, no push tokens, no server dispatch in 2.0. |
| S8 | Canonical health data model | **Adopted for M9.** The `HealthMetric` / `SleepSession` / `WearableActivity` normalization schema and the manual-beats-wearable priority rule become the M9 wearables schema draft. |
| S9 | AI security section | **Adopted now.** Threat model, userId-from-auth-only injection, tool schema validation, per-conversation tool caps, implausible-value confirmation, medical guardrails (§4). |
| S10 | Date-versioned goals | **Adopted now.** Fixes a verified honesty bug: Diary currently judges all 28 days against today's single target (`diary_page.dart` uses one `targetsProvider` value). |

Tags: **[BUILT]** exists · **[NOW]** 2.0 work item · **[M9]/[M11]** filed to that milestone ·
**[REFUSED]** with reason.

---

## 1. The governing architecture (now through M8)

```
 Flutter app (iOS 15+)
 ├── Drift (SQLite) ........... source of truth; every screen reads local streams [BUILT]
 ├── Insight engine ........... pure functions over Drift; reactions, streaks,
 │                              trends, weekly digest, reminder computation [NOW]
 ├── On-device voice .......... STT (speech framework) + TTS (AVSpeech/Android TTS) [NOW]
 ├── Local notifications ...... scheduled from local state, quiet-hours aware [NOW]
 └── PowerSync client ......... upload queue, retry, resume, conflict handling [BUILT]
        │  (sync — the ONLY background network path)
        ▼
 Supabase
 ├── Postgres + RLS ........... per-user isolation, adversarially tested [BUILT]
 ├── Auth ..................... anonymous-first; email; Apple/Google planned [BUILT]
 ├── Storage .................. photos (progress, gallery) behind RLS [NOW]
 └── Edge Functions ........... the AI entry point [BUILT]
        │
        ▼
 OpenRouter (paid tier, no training) → provider models      [BUILT, ADR 0011]
   budgets enforced against ai_usage; BYOK keys stay on device
```

Properties this buys, which the source design spends thirty sections engineering around:
read-your-writes is trivial (reads are local); idempotency is structural (client-generated UUIDs
are the row ids; sync replays are upserts); the dashboard "cache" is the database itself; offline
is not a degraded mode but the primary one. The source design's Section 40 describes this exact
end state and is hereby marked satisfied by construction.

**Consistency model** (replacing the source design's Section 9): local Drift writes are strongly
consistent on device; cross-device convergence is eventual via PowerSync; server RLS is the
isolation boundary; AI reads a device-local context snapshot (the same 28-day window Diary
shows, so the two never disagree [BUILT]).

## 2. Adopted now — the 2.0 backend work items

**A1 — Date-versioned targets [NOW, first].** New synced table `target_history(user_id,
effective_date, calories, protein, carbs, fat, source)` written whenever targets change
(profile edit, plan activation/deactivation, manual override). Diary, Trends, and the insight
engine join each day to its effective target. Rides the four-file sync contract (Drift + bump +
preservation test · powersync_schema · SQL + RLS + `alter publication powersync add table` ·
sync-streams.yaml; migration first, sync rules second).

**A2 — Safety floors [NOW].** Target computation and plan generation enforce: minimum 1,200
kcal (female) / 1,500 (male) / max(floor, BMR × 0.8); weekly-rate warnings past ±1 kg/week;
auto-switch to maintenance when the goal weight is reached. Copy stays neutral ("Adjusted to
1,500 for safety"). Vita's system prompt carries the same floor.

**A3 — Gateway hardening [NOW, S4/S9].** On the Edge Function: `user_id` derives only from the
verified JWT, never from request bodies or model output (audit the current function and add a
test); tool arguments validated against schemas server-side, not only client-side; per-request
tool-call iteration cap; implausible-value gate (>5,000 kcal single entry, >10,000/day → the
draft is refused back to a confirm question); timeout + one retry + model fallback chain
(extends #134); structured error taxonomy preserved (budget / provider / auth) so client copy
stays honest [BUILT #104/#105]. Injection-pattern flagging on inbound text (log, never block
silently). Medical-topic guardrails in the system prompt: no diagnosis, no dosages, no eating
disorder coaching, redirect to a doctor; "not medical advice" caption stays on plan generation
[BUILT].

**A4 — Model tiering registry [NOW].** The source design's model registry pattern, applied to
the existing path: named tiers (`fast` for voice/log parsing, `standard` for chat,
`vision` for photo) mapped to OpenRouter model ids in the Edge Function config, switchable
without app release (remote config), each with a fallback id. Cost per tier tracked in
`ai_usage` (extend with model + token columns if absent).

**A5 — Voice-first Vita [NOW, S3].** §3 below.

**A6 — Local analytics [NOW, S6].** The insight engine owns pre-aggregation on device: daily
rollups, streak state (gap-day semantics), weekly digest text. No server workers. The only
server-side aggregate is `ai_usage` (already server-owned by necessity).

**A7 — Media pipeline [NOW].** Supabase Storage buckets `progress-photos`, `meal-photos`
(gallery, opt-in D6/D15): client-side resize before upload (1200px, ~85% JPEG) and thumbnail
generation; per-user RLS on object paths; **signed URLs with short expiry for progress photos**
(sensitive class, adopted rule), plain authenticated access for meal photos; upload rides the
existing offline queue and never blocks logging.

**A8 — Local notifications [NOW, S7].** Reminder engine on device: per-slot meal reminders
(only when the slot is empty at the configured time), weigh-in day, fasting-window edges,
morning nudge (composed from yesterday's local rows by the insight engine, LLM phrasing only if
a budget-free cached phrase is unavailable — template text otherwise), Sunday digest.
Quiet by default, all opt-in, timezone-correct because computation happens on the device that
owns the timezone.

**A9 — Observability [NOW, right-sized].** Sentry (or equivalent) for Flutter crash + error
reporting with health-data scrubbing; structured JSON logs in the Edge Function (request id,
user hash, model, tokens, latency, outcome — never message content); one dashboard: AI error
rate, p95 latency, budget-refusal count, sync failure count. Alert thresholds: AI error rate
>5% sustained, function cold-failure spike. The Prometheus/Grafana/Jaeger stack is M11.

**A10 — Data lifecycle [NOW policy, M8 export].** Retention: health rows indefinite until
account deletion; chat threads device-local (user-deletable, already); memory facts
user-deletable [BUILT]; photos deleted with account. Account deletion: cascading server delete
+ local wipe, 30-day grace. Export (M8): full JSON/CSV generated on device from Drift — no
server export job needed until M11. DPDP + GDPR alignment documented in the M7 privacy pass.

**A11 — Recipe import [NOW-adjacent, P2].** schema.org/Recipe JSON-LD parse first, LLM
extraction fallback, through the existing gateway; imported rows carry `source='recipe_import'`
with the source URL.

**A12 — Nutrient schema extension [NOW, with the micronutrient panel].** Extend the food
tables with vitamin D, B12, folate, magnesium, and zinc columns (blank-over-zero semantics as
everywhere) when UX spec §3.12's nutrient panel ships; values populate only from sources that
actually carry them (USDA does; AI estimates stay blank for micros).

## 3. Voice architecture — the voice-first agent (S3)

The owner ruling: Vita is both a voice-first AI agent and chat. The source design's Section 20
loop is adopted; the transport is adapted so the loop works today, offline-tolerant and at
near-zero marginal cost:

```
mic (on-device STT, live transcript)                     [BUILT dictation stack]
   │  final transcript
   ▼
agent turn — existing chat pipeline via Edge Function:
   context snapshot + tools + propose-confirm contract   [BUILT]
   model tier: `fast`                                     [A4]
   │  streamed text reply + optional draft (confirm card)
   ▼
on-device TTS speaks the reply (AVSpeechSynthesizer /
Android TextToSpeech; user-selectable voice; rate ~1.05×) [NOW]
   │
   ├─ barge-in: mic stays open on VAD; user speech stops
   │  TTS instantly and starts the next turn              [NOW]
   ├─ confirm cards are ALWAYS visual: Vita says "Want me
   │  to log it?" and the card renders; "yes"/"haan" as a
   │  spoken confirmation maps to the card's confirm      [NOW]
   └─ session ends after 30s silence or close
```

Rules carried over from the UX spec: no wake word (D9 stands); nothing records in background;
recording UI is always visible while the mic is open; the AI consent gate covers the agent call
(TTS and STT are on-device and add no egress); Vita-initiated writes keep the propose-confirm
contract — **a spoken "yes" is a confirmation gesture on a visible card, never a silent write.**
Voice replies have a per-session mute toggle and a global setting ("Vita speaks replies",
default on in voice mode, off in text chat). Latency budget on-device: STT finalize ~0.3s +
first token ~1s (fast tier) + TTS start ~0.2s ≈ under 2s perceived, matching the source
design's target without a voice server. Cloud STT (Whisper/Deepgram), premium TTS
(ElevenLabs-class), and the WebSocket streaming session move to M11/premium [DEFERRED].

Voice sessions are chat turns: they persist into the same thread, so a conversation started by
voice continues in text and vice versa (owner ruling: both, one Vita).

## 4. AI security model (S9, adopted)

Threats: prompt injection, tool abuse, cross-user leakage, data exfiltration, jailbreak-to-
harmful-advice. Defenses, layered:

1. **Identity**: `user_id` only from the verified JWT; RLS as the second wall; tools execute
   with the caller's scope only. The model cannot name another user into existence.
2. **Tool registry**: closed allowlist; schema validation server-side; iteration caps;
   bounds-checks before any draft reaches the user [BUILT + A3].
3. **Write path**: every AI-initiated mutation passes the visible confirm contract (voice
   included, §3). Auto-Track (UX D15) is the single explicit-opt-in exception, badged and
   reviewable.
4. **Content**: medical guardrails + calorie floors in the system prompt and in code (the
   floor is enforced in target math, not only asked of the model); injection patterns logged.
5. **Privacy**: chat content never in logs; memory facts visible and deletable; photos
   discarded after estimation unless gallery is on; BYOK keys never leave the device.

## 5. Wearables (M9) — canonical model adopted (S8)

The source design's normalization layer is filed as the M9 schema draft: `health_metrics`
(user, provider, external_id, metric_type, value, unit, recorded_at; unique on
provider+external_id for dedupe-by-upsert), `sleep_sessions` (stages, score, HRV),
`wearable_activities` (type, duration, calories, HR, raw source_data). Priority rule adopted:
**manual entry beats wearable sync** for the same metric and date. Apple Health reads happen
on-device (HealthKit) and enter Drift directly — for the primary mobile product this makes
most "sync workers" local too; server-side OAuth sync (Fitbit/Garmin/Oura/Strava) lands with
per-provider `sync_logs` and the never-stale-as-current rule (ROADMAP M9). Degradation copy
stands: "not syncing, reconnect."

## 6. The second deployment (M11) — where the source design lives

ADR 0017's self-hosted/web deployment is where the source design's server architecture applies
nearly as written, corrected by three ADR constraints: **shared AI code path** (budget, BYOK,
redaction in one module both entry points import), **shared migration runner** (cloud and
self-hosted schemas cannot drift), and the **moat boundary** (curated Indian data via
authenticated lookup, never seeded into the image; degrade to USDA + OFF air-gapped).

Filed for M11 from the source design: the modular-monolith domain map and extraction triggers;
Express + PgBouncer + Redis + BullMQ with the outbox pattern; SSE streaming and the WebSocket
voice session; Typesense behind the same provenance-preserving food schema (S2 still binds:
search indexes may index the contained tables, never merge them); signed-URL media; the
observability stack; cursor pagination and the API shape; multi-region phasing; the DR runbook
and restore drills; the cost model. The MCP server (M11) runs through the same RLS as every
other client.

## 7. Refused, with reasons (unchanged unless the owner reopens)

- **R1 — Federated food catalogue** (S2, owner-confirmed): licence violation by design.
- **R2 — Custom auth now**: rebuilds Supabase Auth and deletes anonymous-first; the source
  design's auth chapter becomes M11 reference only.
- **R3 — Redis/BullMQ/K8s/Typesense now**: infrastructure for a load that does not exist;
  every 2.0 need they serve is met locally or by Supabase primitives.
- **R4 — Server food search now**: search is local and offline; server search returns with the
  M11 web client.
- **R5 — Cross-user AI response caching**: marginal saving, privacy surface; provider-level
  prompt caching (already doctrine) captures most of the win.
- **R6 — Message-quota free tier**: monetization surfaces remain the settled cap states +
  BYOK (+Plus when the tooling decision lands); basics stay free.

## 8. Work-item summary (ordered)

1. A1 target history table + Diary/Trends join (fixes the verified honesty bug).
2. A3 gateway hardening audit + tests (userId source, tool validation, bounds, fallback chain).
3. A5 voice-first Vita (TTS out, barge-in, spoken-confirm mapping) — pairs with UX spec §8.
4. A2 safety floors in target math + plan gen + prompt.
5. A7 storage buckets + signed-URL rule (unblocks measurements photos + gallery).
6. A8 local reminder engine (unblocks UX Reminders screen).
7. A4 tier registry in remote config; A9 observability; A10 deletion flow.
8. New synced tables for mood / measurements / fasting / gallery via the four-file contract.

*End. Provenance: owner-supplied system design (2026-08-31), reconciled against ADRs 0003,
0011, 0014, 0016, 0017, CLAUDE.md rules 1–9, and the shipped code at `bfe689f`.*
