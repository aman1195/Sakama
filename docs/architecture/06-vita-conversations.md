# 06 · Vita conversations: persistence + threads (phase 1)

> Design for the first phase of [ADR 0016](../adr/0016-vita-as-assistant.md): making Vita
> conversations survive, and splitting them into threads. **Status: proposed — design only.**
>
> Supersedes the note in `coach_message.dart` that persistence would be "a synced coach_messages
> table": ADR 0016 decision 1 makes conversations **device-local**.

## 1. Why this first

Today the transcript lives only in `CoachState` and is **lost on every app restart** — there is no
messages table at all. Everything else in ADR 0016 assumes a durable transcript: confirm-cards from
tool calls belong in a conversation that persists, and memories cite the thread a fact came from.
It is also the schema work, which is best done once, early, and carefully.

## 2. Schema (local-only)

Two new tables, both `Table.localOnly` in the PowerSync schema — the pattern already used by
`foods`/`off_foods`. **No Supabase mirror, no RLS policy, no sync-streams entry, no server
migration.** Drift owns the DDL.

```
chat_threads
  id            text pk        -- uuid
  user_id       text null      -- scopes threads to the signed-in user on a shared device
  title         text           -- derived from the first user message
  created_at    int
  updated_at    int            -- last activity; the thread list sorts on this

chat_messages
  id            text pk        -- uuid
  thread_id     text           -- FK-by-convention to chat_threads.id (indexed)
  role          text           -- 'user' | 'vita'
  content       text
  synthetic     bool default 0 -- app chrome (budget/error notices), never replayed upstream
  created_at    int
```

`user_id` is included and **filtered on** rather than left out: these are health conversations, and
if one user signs out and another signs in on the same phone, the second must not see the first's
transcript. It is nullable for the same offline-birth reason as every other table.

**Filter semantics (specified, not assumed).** On synced tables Postgres backfills a null `user_id`
via `default auth.uid()` on upload. A local-only row **never uploads**, so a conversation born
pre-auth stays `user_id = null` forever and no server ever fixes it. Therefore:

- Rows are scoped **strictly to the current uid**; a null `user_id` is visible to **no one** once a
  session exists, never treated as "matches everybody".
- The repository **backfills `user_id` locally** for null rows once the anonymous session resolves,
  so a genuinely pre-auth conversation is adopted by the session that created it rather than
  stranded.

Isolation therefore rests on an explicit, tested rule rather than on null-coalescing behaviour.

`synthetic` is preserved from the existing `CoachMessage` so the visible transcript is faithful
while the wire payload stays clean (review #58).

### Migration

`schemaVersion` **5 → 6**, additive only: `createTable(chatThreads)` + `createTable(chatMessages)`.
No existing row is touched. Ships with the mandatory artefacts (docs/MOBILE.md, docs/REVIEW.md §6.1):

- a dumped `drift_schemas/drift_schema_v6.json`,
- regenerated `test/migration/generated/` with `6` in `GeneratedHelper.versions`,
- a **v5 → v6 preservation test** that seeds a row in every existing table, migrates, and asserts
  each survived and the new tables are usable.

Device-local does **not** exempt this from the migration discipline — a bad migration still
destroys user data irrecoverably.

## 2a. Identity transitions — the local-only clearing trap

Verified against `powersync-2.3.3`:
`disconnectAndClear({bool clearLocal = true})` runs `powersync_clear(clearLocal ? 1 : 0)`, and its
docstring states *"To preserve data in local-only tables, set `clearLocal` to false."* Our call site
(`SyncService.disconnectAndClear()`) passes **no argument**, so today **local-only tables are
cleared** on both identity transitions:

- `AuthService.signOut()` — sign out of a real account,
- `AuthService.signInExisting()` — a user switch, which clears **before** attempting sign-in.

Two consequences for this phase:

1. **Sign-out/user-switch would wipe conversations and memory.** For a *switch* that is desirable —
   user B must not inherit user A's health conversations, and clearing is a stronger guarantee than
   the `user_id` filter, which is only a visibility control.
2. **`signInExisting` would destroy them irrecoverably on a failed sign-in.** The #55 fix reattaches
   replication after a mistyped password and notes "the guest's data re-syncs from the server" —
   but **local-only data has no server copy to come back from**. Synced tables recover; chat and
   memory would be gone forever.

**Design:** switch the call sites to `disconnectAndClear(clearLocal: false)` and delete the
conversation + memory tables **explicitly, after a confirmed identity change** (i.e. once
`signInWithPassword` has succeeded, and in `signOut` after the sign-out call). This preserves the
isolation intent while removing the failed-sign-in data-loss path. The existing local-only
*reference* tables (`foods`, `off_foods`) are unaffected either way, since `ensureSeeded` re-seeds
them.

This must ship **with** phase 1 — the trap only becomes harmful once there is irreplaceable
local-only user data.

## 3. Repository

`ChatRepository` over the two tables, tested against real in-memory sqlite (never mocks):

- `watchThreads()` — newest activity first (the thread list).
- `watchMessages(threadId)` — ascending, the transcript.
- `createThread({title})` / `renameThread` / `deleteThread(id)` — delete removes its messages in the
  same transaction (no orphans).
- `appendMessage(threadId, role, content, {synthetic})` — also bumps the thread's `updated_at`.

## 4. Thread lifecycle

- **Creation is lazy.** Opening Coach with no threads shows the empty state; the first message
  creates a thread. No empty threads accumulate.
- **Title is derived from the first user message** (trimmed, ~40 chars). Free — no model call. A
  model-generated title is a possible later refinement, not worth a call now.
- **"New chat"** in the app bar creates a fresh thread and switches to it.
- **Thread list** (drawer or a list screen) shows title + last-activity, with swipe-to-delete
  behind a confirm.
- **Delete** removes the thread and its messages. Per ADR 0016 there is no auto-pruning.

## 5. Controller changes

`CoachController` becomes thread-scoped:

- State gains the active `threadId`; messages come from `watchMessages` rather than living in
  memory.
- `send()` persists the user turn, calls Vita, then persists the reply (and any synthetic notice)
  — so a crash mid-turn cannot lose what the user typed.
- **What goes upstream stays bounded:** only non-synthetic messages **of the active thread**, and
  only the most recent N turns. This is the cost control that threading buys us — an unbounded
  transcript would make every turn more expensive than the last (rule 9).

## 6. What this phase deliberately does NOT do

Tool calls and confirm-cards (phase 2), photo-in-chat (phase 3), memory (phase 4), voice (phase 5).

**Carried forward to phase 2 (design it in, do not bolt it on):** tool-call arguments are
**untrusted model output** and must be validated and bounds-checked *before* they reach the confirm
card — the same discipline `parseEstimate` and `PlanImporter` already apply. Propose-confirm guards
*intent*, but a plausible-looking wrong number can slip past a distracted tap, and an absurd one
should never be offered in the first place.
The message table's `role`/`content` shape is deliberately plain; when confirm-cards arrive they
will need a structured payload column, and that will be its own additive migration rather than
speculative generality now.

## 7. Testing

- **Repository** against real sqlite: create/append/watch ordering, delete cascades, `updated_at`
  bumping, and `user_id` scoping (user B never sees user A's threads).
- **Migration**: the v5 → v6 preservation test described above.
- **Controller**: sending persists both turns; a failed Vita call still leaves the user's message
  stored; only non-synthetic, current-thread, last-N messages reach the wire.
- **Widget**: thread list renders and switches; new-chat creates a thread; delete confirms; the
  transcript survives a controller rebuild (the regression this phase exists to fix).

## 8. Open questions

1. **History window `N`** — how many prior turns to replay upstream. Suggest starting at 20 and
   tuning against real token cost; it is a constant, not a contract.
2. **Thread list placement** — drawer inside Coach, or a separate screen? Drawer keeps the chat
   full-bleed; a screen is easier to reach on small phones.
