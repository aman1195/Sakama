-- 0005: ai_usage — per-user AI budget counters (CLAUDE.md rule 9: hard
-- per-user budgets enforced in the Edge Function).
--
-- SERVER-OWNED: written only by the Edge Function via service_role (which
-- bypasses RLS). Clients may READ their own rows (so the UI can show "3/10
-- used today") but never write. NOT synced via PowerSync — not on the
-- publication; it is metering, not user content.

create table public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day     text not null,              -- yyyy-MM-dd (UTC)
  feature text not null,              -- 'estimate' | 'photosnap' | 'vita' ...
  count   integer not null default 0,
  primary key (user_id, day, feature)
);

alter table public.ai_usage enable row level security;
alter table public.ai_usage force row level security;

-- Read own usage only. No insert/update/delete policies: service_role writes.
create policy "ai_usage: read own" on public.ai_usage
  for select to authenticated using ((select auth.uid()) = user_id);
