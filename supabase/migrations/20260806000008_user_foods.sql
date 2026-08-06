-- 0008: user_foods — favourites and custom foods (docs/architecture/08-user-foods.md).
-- Mirrors the Drift + PowerSync user_foods definitions (three-file sync contract).
-- Same RLS template as user_plans/profiles (0001 is THE TEMPLATE for every user table).
--
-- LICENCE (CLAUDE.md rule 5): a 'pointer' row stores NO nutrition — only where to
-- read it from, plus the user's portion. That is what keeps ODbL values from Open
-- Food Facts out of this synced table, and therefore off our servers. Only 'custom'
-- rows carry nutrition, and those numbers are the user's own.

create table public.user_foods (
  id             text primary key,
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name           text not null,                 -- what the USER calls it
  kind           text not null,                 -- pointer | custom
  source_table   text,                          -- foods | off_foods   (pointer only)
  source_id      text,                          -- row id there         (pointer only)
  energy_kcal    double precision,              -- per 100 g            (custom only)
  protein_g      double precision,
  carb_g         double precision,
  fat_g          double precision,
  fiber_g        double precision,
  serving_label  text,                          -- "1 katori"
  serving_grams  double precision,              -- the user's usual portion
  use_count      integer not null default 0,    -- most-used ordering
  created_at     bigint not null,
  updated_at     bigint not null,               -- LWW key

  constraint user_foods_kind_valid check (kind in ('pointer', 'custom')),
  -- Belt-and-braces on the licence rule: a pointer may not carry nutrition.
  -- The client API cannot express it (addPointer takes no nutrition arguments);
  -- this makes the same guarantee true at the database level.
  constraint user_foods_pointer_has_no_nutrition check (
    kind <> 'pointer' or (
      energy_kcal is null and protein_g is null and carb_g is null
      and fat_g is null and fiber_g is null
    )
  ),
  constraint user_foods_pointer_has_source check (
    kind <> 'pointer' or (source_table is not null and source_id is not null)
  )
);

comment on table public.user_foods is
  'Favourites and custom foods. A pointer row references foods/off_foods and stores '
  'NO nutrition, so ODbL data never lands here (CLAUDE.md rule 5); custom rows hold '
  'the user''s own per-100g values.';

-- RLS: own rows only, per verb, forced. (select auth.uid()) is per-QUERY
-- (Supabase perf pattern); `to authenticated` skips anon entirely.
alter table public.user_foods enable row level security;
alter table public.user_foods force row level security;

create policy "own rows: select" on public.user_foods
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "own rows: insert" on public.user_foods
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "own rows: update" on public.user_foods
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own rows: delete" on public.user_foods
  for delete to authenticated using ((select auth.uid()) = user_id);

-- PowerSync publication must include the table.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'powersync') then
    create publication powersync for table public.user_foods;
  else
    alter publication powersync add table public.user_foods;
  end if;
end $$;
