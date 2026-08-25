# 0016. Vita as an assistant: tools, threads, and on-device memory

**Status:** Accepted · **Date:** 2026-08

## Context

Vita today is a read-only chat: it assembles a grounding snapshot (profile, targets, today's
logs, active plan) and returns text. It cannot act, it forgets everything on app restart (there is
no messages table — the transcript lives only in `CoachState`), and it learns nothing about the
user over time.

PRODUCT.md/CLAUDE.md put the wedge squarely on "a genuinely better LLM coaching layer" against
HealthifyMe. Conversational logging, image-grounded judgement, and a coach that actually remembers
you are that wedge. Competitors make you fill forms.

The forces in tension:

- **Trust.** The food diary is the artefact every other feature rests on. A hallucinated write
  corrupts it silently, on a platform where [we cannot hotfix](../MOBILE.md).
- **Privacy.** Conversations and distilled memories about health are materially more sensitive than
  a food log. India's DPDP Act treats health data as sensitive personal data.
- **Device cost.** MOBILE.md's targets are cold start < 2 s, zero dropped frames, "no measurable
  drain at idle", and app size "as small as practical". An on-device ML loop threatens all four.
- **AI cost.** Rule 9: cheap model by default, hard per-user budgets. An agentic loop multiplies
  model calls per user message, which silently breaks a cap expressed in "turns".
- **Offline.** Rule 1 says every feature works with no signal; MOBILE.md targets "100% of log paths
  work with airplane mode on". A model call is inherently online.

We resolved these through a structured design interview; the decisions below are its output.

## Decision

**1 · Conversations and memory are device-local.** Threads, messages and memories are
`Table.localOnly` (the precedent set by `foods`/`off_foods`): PowerSync creates them, never syncs
them, and there is no Supabase mirror, no RLS policy, and no sync-streams entry. The line we can
state plainly: *your conversations and what Vita remembers never leave your phone at rest.*

**2 · Vita proposes; the user commits.** Tool calls never write directly. Vita emits a structured
draft, the chat renders a confirm card ("Lunch · dal tadka · 180 kcal — Log it?"), and the user
taps. Every resulting row carries `logged_via: 'vita'`.

**3 · Tool surface (v1):** `log_food`, `log_water`, `log_weight`, corrections/deletes, and history
queries. Deletes are hard deletes guarded by confirm + undo — deliberately *not* a `deleted_at`
column, because that would mean a migration on `food_logs`, the most load-bearing synced table.

**4 · Memory stores structured facts + rolling summaries.** Typed rows
(`preference | constraint | routine | goal | observation`) with confidence, timestamp and the
source thread, plus a per-thread rolling summary. Semantic search over embeddings is **deferred**
behind a Phase-0-style spike on real hardware (see Consequences).

**5 · Extraction is asynchronous and batched** (every N turns / on thread close), not piggybacked
on the reply. The reply turn already has two jobs — converse and decide tool calls; a third
degrades all three on a cheap model.

**6 · Budget meters user-visible exchanges,** not raw model calls: one increment per user message
regardless of internal hops, plus a separate small cap for extraction, a token ceiling, and a
maximum of ~2 tool hops per exchange. A photo message costs **1 exchange + 1 photo**, mapping the
two existing caps onto the two real resources.

**7 · Model policy: `gemini-2.5-flash` everywhere, with an escalation seam** (per-feature `MODEL`
override) and a tool-selection eval fixture set — user message → expected tool + args — to decide
escalation on evidence rather than assumption.

**8 · Vita is an accelerator, not a guaranteed log path.** The offline guarantee stays on the
manual paths (Quick Add, photo, barcode, water/weight), which already work in airplane mode. Vita
says plainly that it needs a connection; it never fakes a queue.

**9 · Retention: keep until the user deletes.** Per-thread delete plus a global reset. Chat text is
~1.5 MB/year; auto-pruning would orphan the memory provenance that cites the thread a fact came
from.

**10 · Memory is browsable, individually deletable, and resettable.** Deletion is the correction
mechanism — Vita re-learns. We do not offer free-text editing of facts, which would make
user-authored and extracted memories indistinguishable downstream. Summaries regenerate.

**11 · PhotoSnap becomes the shared vision service.** Task-parameterised, backward compatible
(`mode` defaults to today's behaviour; new keys are additive siblings to `items`, which the client
already reads by key). One vision call returns `items` (for the log draft) *and* a reusable
`description` (so follow-up turns need not re-send the image) *and* the conversational `answer`.
Any feature needing vision uses it.

**12 · Voice input uses on-device STT** (iOS Speech / Android SpeechRecognizer): free, offline.
**Gate:** the plugin's licence must be permissive (rule 4) and pass the CI licence-checker before
adoption.

> **AMENDED 2026-08-25, on building it.** This decision originally promised "no audio egress"
> unconditionally. That was wrong, and verifying it against `speech_to_text` 7.3.0's source before
> adoption is the only reason it was caught:
>
> - **`onDevice` defaults to FALSE on both platforms.** Dictation without that flag streams audio to
>   Apple or Google. `VoiceInput` therefore always sets it, and a test asserts the source never
>   contains `onDevice: false`.
> - **The two platforms then behave OPPOSITELY.** iOS fails LOUD — `supportsOnDeviceRecognition`
>   false returns a `FlutterError` and captures nothing. Android fails OPEN — when
>   `isOnDeviceRecognitionAvailable()` is false the plugin silently constructs an ordinary network
>   recogniser and uploads the audio, with no error and no signal reachable from Dart.
> - Android's on-device recogniser needs **API 31+**, which a large share of budget Indian handsets
>   do not have — the same minimum-spec reality that ruled out bundling a local model.
>
> So the promise holds unconditionally on **iOS only**. Android gets a one-time disclosure before
> first use, because the honest thing to say is that we cannot tell which path the phone took.
> The licence gate passed independently: BSD-3-Clause, already on the allowlist.

**13 · Sequencing.** Conversation persistence + threads → tools/propose-confirm → photo-in-chat →
memory → voice.

## Consequences

**Easier**

- No RLS, server migration, or sync-rules work for any of this — decision 1 removes the entire
  server surface, and `Table.localOnly` is already proven in this codebase.
- The tool surface maps 1:1 onto existing, tested `add()` methods on three repositories; phase 1
  needs no new persistence logic beyond the chat tables themselves.
- One vision call serves both "should I eat this?" and the log draft — cheaper and richer than
  either recognising-then-discussing or discussing-without-numbers.
- Memory costs essentially nothing on-device: extraction runs server-side where the model call
  already happens, and retrieval is one indexed SQL top-k. No new dependency, no app-size change,
  no thermal load.

**Harder / accepted risks**

- **Reinstall, a new phone, or a user switch wipes conversations and memory.** This is the price of
  device-local, accepted knowingly. A user-initiated export is a possible later escape hatch;
  adding sync later is additive, whereas removing it would not be. Note that PowerSync's
  `disconnectAndClear` clears local-only tables **by default** (`clearLocal: true`), so identity
  transitions need explicit handling — see
  [architecture/06 §2a](../architecture/06-vita-conversations.md) for the failed-sign-in data-loss
  path this creates and its fix.
- **Device-local storage is not device-local processing.** Every turn still sends conversation
  content, images, and retrieved memory facts to the provider. The consent copy (#60/#62) and the
  privacy inventory (#64/#67) MUST say so plainly — this is launch-gating, and the asterisk on
  decision 1.
- **The first destructive tool enters the app.** Confirm + undo mitigate it, but a misparsed
  "remove that" is now possible in a way it was not before.
- **Chat tables are still a Drift migration** — device-local does not exempt them from MOBILE.md's
  rule that a bad migration destroys user data irrecoverably. Forward-only, tested, preservation-
  asserted, like every migration before.
- **Semantic memory is unresolved, not rejected.** Committing to embeddings requires measuring
  model size, inference time and thermals on real hardware first — the same evidence-first bar that
  produced the PhotoSnap GO decision ([ADR 0013](0013-validate-photosnap-before-build.md)).
- **Agentic latency.** Tool hops add round trips on mobile networks; without streaming and
  optimistic UI, conversational logging can feel slower than the form it replaces.

**Committed to**

Vita as the app's primary interaction surface, with a propose-confirm safety contract that we
should not quietly relax later — the confirm step is the reason a hallucination cannot corrupt a
health diary.
