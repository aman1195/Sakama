-- 0007: user_plans — a user's saved plans (M4, ADR 0007). Mirrors the Drift +
-- PowerSync user_plans definitions (three-file sync contract). Same RLS template
-- as profiles/food_logs (0001 is THE TEMPLATE for every user table).
--
-- Plans are DATA: `config` holds the whole Plan JSON, interpreted client-side by
-- the plan engine. A user may keep several plans; exactly one is `active` (the
-- client repository enforces single-active — deliberately NOT a DB constraint,
-- so an offline active-switch can't be rejected mid-sync under LWW).

create table public.user_plans (
  id          text primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name        text not null,
  config      text not null,                         -- Plan JSON
  source      text not null default 'user_imported', -- ai_generated|user_imported|template
  active      boolean not null default false,
  start_date  text,                                  -- yyyy-MM-dd (cyclic schedule / duration)
  created_at  bigint not null,
  updated_at  bigint not null                        -- LWW key
);

comment on table public.user_plans is
  'A user''s saved plans (M4). Offline-first: born on-device, synced via PowerSync. '
  'config is the Plan JSON; the client enforces exactly one active plan per user.';

-- RLS: own rows only, per verb, forced. (select auth.uid()) is per-QUERY
-- (Supabase perf pattern); `to authenticated` skips anon entirely.
alter table public.user_plans enable row level security;
alter table public.user_plans force row level security;

create policy "own rows: select" on public.user_plans
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "own rows: insert" on public.user_plans
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "own rows: update" on public.user_plans
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own rows: delete" on public.user_plans
  for delete to authenticated using ((select auth.uid()) = user_id);

-- PowerSync publication must include the table.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'powersync') then
    create publication powersync for table public.user_plans;
  else
    alter publication powersync add table public.user_plans;
  end if;
end $$;
