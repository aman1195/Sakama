-- What the targets actually WERE on a given date.
--
-- Without this, history lies: the diary judged all 28 of its days against
-- TODAY's targets, so changing a goal silently re-scored weeks the user had
-- already lived. Rows the user cannot change were being scored by a number
-- that moves.
--
-- A row means "from `date` onward these were the targets, until a later row
-- supersedes it" — CHANGES, not one row per day. A year of stable goals costs
-- one row, not 365. Resolution for a date D is the newest row with date <= D.
--
-- `source` is provenance in the spirit of rule 7: a number a user is judged
-- against should say where it came from.
create table public.target_history (
  id         text primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date       text not null,               -- yyyy-MM-dd, the user's local day
  calories   integer not null,
  protein_g  integer not null,
  carb_g     integer not null,
  fat_g      integer not null,
  fiber_g    integer not null,
  water_ml   integer not null,
  source     text not null default 'computed',
  created_at bigint not null,
  updated_at bigint not null              -- LWW key
);

alter table public.target_history enable row level security;
alter table public.target_history force row level security;

create policy "target_history: select own" on public.target_history
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "target_history: insert own" on public.target_history
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "target_history: update own" on public.target_history
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "target_history: delete own" on public.target_history
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Provenance is a closed vocabulary.
alter table public.target_history
  add constraint target_history_source_known check (
    source in ('computed', 'plan', 'seed')
  );

-- A target of zero is not a target; it is a bug that would score every day as
-- "over". The floor is deliberately low (a plan may legitimately set a small
-- fibre or water goal) — this catches nulls-coerced-to-zero, not lifestyle.
alter table public.target_history
  add constraint target_history_calories_positive check (calories > 0);

-- One in-force row per date per user. The client upserts on (user_id, date):
-- changing a goal twice in one day records the day's final answer, not two
-- rows racing to be the newest.
create unique index target_history_user_date_idx
  on public.target_history (user_id, date);

-- Resolution reads the newest row at or before a date; this serves it directly.
create index target_history_user_date_desc_idx
  on public.target_history (user_id, date desc);

-- PowerSync publication must include the table.
--
-- Not optional and not implied by the sync stream: the publication was created
-- `for table ...`, never FOR ALL TABLES, so membership is opt-in per table.
-- Without this the upload side works but the download side has nothing to
-- replicate, so a second device would score the same history differently —
-- the exact bug this table exists to fix.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'powersync') then
    create publication powersync for table public.target_history;
  else
    alter publication powersync add table public.target_history;
  end if;
end $$;
