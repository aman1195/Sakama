-- Widen food_logs.logged_via to the vocabulary the client actually writes.
--
-- THIS FIXES SILENT DATA LOSS, found by dogfooding on 2026-08-31.
--
-- The constraint shipped with the original table allowed six values. Since
-- then the client learned six more as new logging paths landed: `recent` and
-- `saved` and `manual` (quick add), `meal` (#146), `ai_estimate` (the
-- name-based estimator) and `vita` (coach tool calls).
--
-- Nothing failed loudly, because nothing failed anywhere the user could see:
--
--   1. Drift enforces no CHECK, so the local insert succeeded.
--   2. The UI showed "Logged <food>".
--   3. PowerSync uploaded it; Postgres rejected it with 23514.
--   4. 23514 matches the connector's fatal set (^(22...|23...|42501)$), so the
--      op was DISCARDED rather than retried — correct behaviour for a poison
--      message, and exactly wrong here.
--   5. With the op gone, the next sync checkpoint reconciled the local database
--      back to server state, and the row the user had just created disappeared.
--
-- The evidence: every food_logs row on the server carried `photo` or `search`,
-- the only two of the shipped six the app still emitted, and the newest was
-- three weeks old. Every meal logged from a recent, a saved food, a saved meal,
-- an AI estimate or Vita in that window was lost.
--
-- Rows already lost cannot be recovered; they were reverted on-device. This
-- stops the bleeding.
--
-- The vocabulary is kept in step by test/db/logged_via_vocabulary_test.dart,
-- which parses this file and fails if the client can write a value the server
-- would reject.
alter table public.food_logs drop constraint if exists food_logs_logged_via_check;

alter table public.food_logs
  add constraint food_logs_logged_via_check check (
    logged_via in (
      -- original six
      'search', 'photo', 'voice', 'barcode', 'template', 'quick_add',
      -- shipped since, and rejected until now
      'recent', 'saved', 'manual', 'meal', 'ai_estimate', 'vita'
    )
  );
