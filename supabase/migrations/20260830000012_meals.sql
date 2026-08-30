-- Named groups of saved foods, logged in one tap — "my usual breakfast".
--
-- LICENCE-CRITICAL: `items` holds user_foods IDS and portions, never nutrition.
--
-- A meal is a REUSABLE DEFINITION, not a historical record, which puts it under
-- the stricter standard in docs/architecture/08 §3 alongside user_foods. Storing
-- macros here would rebuild, across all users, an OFF-derived branded-food table
-- on our infrastructure — the explicit non-goal of ADR 0014. Referencing
-- user_foods inherits that containment structurally, because the
-- pointer-versus-custom split is already solved there.
create table public.meals (
  id           text primary key,
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name         text not null,
  items        text not null default '[]',   -- JSON: [{user_food_id, serving_qty}]
  default_meal text,                          -- breakfast|lunch|dinner|snack
  use_count    integer not null default 0,
  created_at   bigint not null,
  updated_at   bigint not null               -- LWW key
);

alter table public.meals enable row level security;
alter table public.meals force row level security;

create policy "meals: select own" on public.meals
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "meals: insert own" on public.meals
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "meals: update own" on public.meals
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "meals: delete own" on public.meals
  for delete to authenticated using ((select auth.uid()) = user_id);

-- A meal slot is a closed vocabulary, or absent.
alter table public.meals
  add constraint meals_default_meal_known check (
    default_meal is null
    or default_meal in ('breakfast', 'lunch', 'dinner', 'snack')
  );

create index meals_user_used_idx on public.meals (user_id, use_count desc);

-- PowerSync publication must include the table.
--
-- Not optional and not implied by the sync stream: the publication was created
-- `for table ...`, never FOR ALL TABLES, so membership is opt-in per table.
-- Without this the upload side works but the download side has nothing to
-- replicate, so a meal saved on one phone never reaches another.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'powersync') then
    create publication powersync for table public.meals;
  else
    alter publication powersync add table public.meals;
  end if;
end $$;
