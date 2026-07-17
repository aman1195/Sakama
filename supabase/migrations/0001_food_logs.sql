-- 0001: food_logs — the first user table, mirroring the client Drift schema v1
-- (app/lib/core/db/database.dart). Column names are snake_case here, camelCase
-- in Drift; PowerSync maps between them via sync rules.
--
-- NON-NEGOTIABLES (CLAUDE.md rules 1-2):
--   * RLS on and FORCED, auth.uid() = user_id — the primary isolation boundary.
--   * Client-generated text UUID PK (rows are born offline on the device).
--   * updated_at drives last-write-wins conflict resolution (ADR 0003).

create table public.food_logs (
  id          text primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date        text not null,                    -- yyyy-MM-dd in the USER'S local day (day-boundary rule)
  meal        text not null check (meal in ('breakfast', 'lunch', 'dinner', 'snack')),
  name        text not null,
  grams       double precision,
  energy_kcal double precision not null,
  protein_g   double precision not null default 0,
  carb_g      double precision not null default 0,
  fat_g       double precision not null default 0,
  logged_via  text not null default 'search'
              check (logged_via in ('search', 'photo', 'voice', 'barcode', 'template', 'quick_add')),
  created_at  bigint not null,                  -- epoch ms, client clock (offline-born rows)
  updated_at  bigint not null                   -- epoch ms — LWW key
);

comment on table public.food_logs is
  'One logged food entry. Offline-first: rows are created on-device in Drift and synced up via PowerSync.';

-- The dashboard/diary read path: one user, one day.
create index food_logs_user_date_idx on public.food_logs (user_id, date);

-- RLS: own rows only, for every verb. FORCE so even the table owner cannot bypass.
alter table public.food_logs enable row level security;
alter table public.food_logs force row level security;

-- (select auth.uid()) — NOT bare auth.uid(): the subquery form is evaluated once
-- per QUERY (initPlan) instead of once per ROW. Supabase's documented RLS-perf
-- pattern; on an unboundedly-growing table a per-row policy is a stalled sync.
-- `to authenticated`: anon never even evaluates the policy.
-- THIS BLOCK IS THE TEMPLATE for every future user table.
create policy "own rows: select" on public.food_logs
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "own rows: insert" on public.food_logs
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "own rows: update" on public.food_logs
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own rows: delete" on public.food_logs
  for delete to authenticated using ((select auth.uid()) = user_id);

-- PowerSync replicates via logical replication; its publication must cover the table.
-- (Supabase creates the powersync publication when following the official guide; this
-- is idempotent-safe on a fresh project.)
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'powersync') then
    create publication powersync for table public.food_logs;
  else
    alter publication powersync add table public.food_logs;
  end if;
end $$;
