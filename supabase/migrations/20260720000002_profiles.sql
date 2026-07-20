-- 0002: profiles — one onboarding profile per user. Mirrors the Drift + PowerSync
-- profiles definitions (three-file sync contract). Same RLS template as food_logs
-- (0001): the block there is explicitly THE TEMPLATE for every user table.

create table public.profiles (
  id                  text primary key,
  user_id             uuid not null default auth.uid() references auth.users (id) on delete cascade,
  dob                 text not null,          -- yyyy-MM-dd; age derived client-side (never store age)
  weight_kg           double precision not null,
  height_cm           double precision not null,
  sex                 text not null,          -- enum .name: male|female|other
  activity            text not null,          -- sedentary|light|moderate|active|veryActive
  goal                text not null,          -- loseWeight|detox|buildMuscle|manageCondition|maintain
  diet                text not null,          -- veg|nonVeg|vegan|eggetarian
  cuisine             text not null,          -- north|south|both|other
  conditions          text not null default '',  -- comma-joined enum names
  onboarding_complete boolean not null default false,
  created_at          bigint not null,
  updated_at          bigint not null            -- LWW key
);

comment on table public.profiles is
  'One onboarding profile per user. Offline-first: born on-device, synced via PowerSync.';

-- One profile per user (the client keeps a single row; this is belt-and-braces).
create unique index profiles_one_per_user on public.profiles (user_id);

-- RLS: own rows only, per verb, forced. (select auth.uid()) is per-QUERY, not
-- per-row (Supabase perf pattern); `to authenticated` skips anon entirely.
alter table public.profiles enable row level security;
alter table public.profiles force row level security;

create policy "own rows: select" on public.profiles
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "own rows: insert" on public.profiles
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "own rows: update" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own rows: delete" on public.profiles
  for delete to authenticated using ((select auth.uid()) = user_id);

-- PowerSync publication must include the table.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'powersync') then
    create publication powersync for table public.profiles;
  else
    alter publication powersync add table public.profiles;
  end if;
end $$;
