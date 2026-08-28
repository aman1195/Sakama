-- How a food-log portion was EXPRESSED, alongside the grams we derived from it.
--
-- GRAMS REMAIN THE TRUTH. Nutrition is canonically per 100 g and every total is
-- computed from `grams`; these two columns only record the portion the way the
-- user said it, so the diary can show "1.5 katori" rather than "150 g".
--
-- Additive and nullable: every existing row stays valid and none is rewritten.
-- No publication change is needed — food_logs is already a member (see the
-- 20260717000001 migration) and the sync stream is `SELECT *`, so new columns
-- flow without touching sync-streams.yaml.
alter table public.food_logs
  add column if not exists serving_label text,
  add column if not exists serving_qty numeric;

-- A label without a quantity, or the reverse, is not a portion. Written
-- together or not at all.
alter table public.food_logs
  drop constraint if exists food_logs_serving_pair;
alter table public.food_logs
  add constraint food_logs_serving_pair check (
    (serving_label is null and serving_qty is null)
    or (serving_label is not null and serving_qty is not null)
  );

-- A portion is positive and bounded. 0 servings is not an entry, and the upper
-- bound is the same order as the existing grams ceiling.
alter table public.food_logs
  drop constraint if exists food_logs_serving_qty_sane;
alter table public.food_logs
  add constraint food_logs_serving_qty_sane check (
    serving_qty is null or (serving_qty > 0 and serving_qty <= 100)
  );
