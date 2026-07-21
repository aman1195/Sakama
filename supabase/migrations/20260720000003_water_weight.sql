-- 0003: water_logs + weight_logs. Same RLS template as food_logs/profiles
-- (the documented template for every user table). Mirrors the Drift + PowerSync
-- definitions (three-file sync contract). Additive.

create table public.water_logs (
  id         text primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date       text not null,           -- yyyy-MM-dd (user's local day)
  amount_ml  bigint not null,
  created_at bigint not null,
  updated_at bigint not null          -- LWW
);
create index water_logs_user_date_idx on public.water_logs (user_id, date);

create table public.weight_logs (
  id         text primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date       text not null,
  weight_kg  double precision not null,
  note       text,
  created_at bigint not null,
  updated_at bigint not null
);
create index weight_logs_user_date_idx on public.weight_logs (user_id, date);

-- RLS: own rows only, per verb, forced. (select auth.uid()) is per-QUERY.
do $$
declare t text;
begin
  foreach t in array array['water_logs','weight_logs'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format($f$create policy "own rows: select" on public.%I for select to authenticated using ((select auth.uid()) = user_id)$f$, t);
    execute format($f$create policy "own rows: insert" on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)$f$, t);
    execute format($f$create policy "own rows: update" on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)$f$, t);
    execute format($f$create policy "own rows: delete" on public.%I for delete to authenticated using ((select auth.uid()) = user_id)$f$, t);
    execute format('alter publication powersync add table public.%I', t);
  end loop;
end $$;
