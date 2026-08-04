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
