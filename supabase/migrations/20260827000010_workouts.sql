-- 0010: workouts. Exercise logging (PRD 7.1), synced per-user.
--
-- Sets live as JSONB on the row rather than in a child table: they are never
-- queried independently of their workout, and a child table would mean a join
-- on every read plus a second RLS policy for no benefit.
--
-- energy_kcal is NULLABLE on purpose. An unknown burn must never become 0,
-- because 0 is indistinguishable from "this burned nothing" and it feeds the
-- calorie target.

create table public.workouts (
  id           text primary key,
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date         text not null,                       -- yyyy-MM-dd, user's local day
  name         text not null,
  kind         text not null default 'strength',
  duration_min integer,
  energy_kcal  real,
  sets         jsonb not null default '[]'::jsonb,
  notes        text,
  logged_via   text not null default 'manual',
  created_at   bigint not null,
  updated_at   bigint not null,

  constraint workouts_kind_known check (
    kind in ('strength', 'cardio', 'mobility', 'sport', 'other')
  ),
  -- Neither a negative burn nor a negative duration is a thing that happened.
  constraint workouts_energy_sane check (energy_kcal is null or energy_kcal >= 0),
  constraint workouts_duration_sane check (duration_min is null or duration_min > 0)
);

alter table public.workouts enable row level security;
alter table public.workouts force row level security;

create policy "workouts: read own" on public.workouts
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "workouts: insert own" on public.workouts
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "workouts: update own" on public.workouts
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "workouts: delete own" on public.workouts
  for delete to authenticated using ((select auth.uid()) = user_id);

create index workouts_user_date_idx on public.workouts (user_id, date desc);
