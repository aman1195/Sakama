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

-- Atomic check-and-increment (review #46 finding 1: the read-check-call-write
-- pattern in the Edge Function was TOCTOU-racy — N concurrent calls could all
-- pass the cap). One statement = one atomic decision in Postgres. Returns the
-- new count, or NO ROW when the cap is already spent. Charge-on-attempt: the
-- increment happens BEFORE the provider call (the safer default for a cost
-- guardrail).
create or replace function public.increment_ai_usage(p_feature text, p_cap int)
returns int
language sql
security definer
set search_path = public
as $$
  insert into public.ai_usage (user_id, day, feature, count)
  values ((select auth.uid()), to_char(now() at time zone 'utc', 'YYYY-MM-DD'), p_feature, 1)
  on conflict (user_id, day, feature)
    do update set count = ai_usage.count + 1
    where ai_usage.count < p_cap
  returning count;
$$;

revoke all on function public.increment_ai_usage(text, int) from public, anon;
grant execute on function public.increment_ai_usage(text, int) to authenticated;
