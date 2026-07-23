# Sakama — Data Model

> Canonical relational model (Supabase Postgres). Mirrored locally in Drift for offline-first. Plan
> JSON contract is in [architecture/04-plan-engine.md](04-plan-engine.md); food schema rationale and
> licensing are in [architecture/03-food-database.md](03-food-database.md).

## Conventions

- Every user-owned table has `id uuid pk`, `user_id uuid default auth.uid()`, `created_at`,
  `updated_at`. **RLS `auth.uid() = user_id`** on all of them.
- All timestamps `timestamptz`. `updated_at` drives last-write-wins sync.
- Nutrition stored **canonically per 100 g**; per-serving derived at read time.
- Reference tables (`foods`) are shared/global, not user-scoped (read-all, restricted writes).

## Entity map

```
auth.users (Supabase)
   └─ profiles (1:1)              basic profile, goals, activity, conditions
   └─ user_plans (1:N)            adopted plan configs (JSON) + active flag
   └─ diary_days (1:N)            per-day rollup + resolved day-type + targets
   └─ food_logs (1:N)            ── food_id ─▶ foods (reference)
   └─ water_logs (1:N)
   └─ fasting_sessions (1:N)
   └─ weight_logs (1:N)
   └─ workout_logs (1:N)
   └─ step_days (1:N)
   └─ sleep_logs (1:N)
   └─ coach_messages (1:N)        Vita chat history + context snapshots
   └─ user_ai_keys (1:1/opt)      encrypted BYOK reference (never plaintext)
   └─ ai_usage (1:N)              spend/meter mirror from LiteLLM
foods (global reference)          USDA/licensed + AI estimates   (OFF is SEPARATE: off_foods)
food_favorites / custom_meals     user-defined templates
```

## Core tables

### profiles
```
user_id uuid pk fk auth.users
display_name text
dob date · gender text
height_cm numeric · weight_kg numeric          -- current; history in weight_logs
activity_level text   -- sedentary|light|moderate|active|very_active
diet_preference text  -- veg|nonveg|vegan|eggetarian
cuisine_preference text -- north|south|both|other
health_conditions text[]  -- diabetes, thyroid, liver, pcod, ...
primary_goal text     -- lose_weight|detox|build_muscle|manage_condition|maintain
onboarding_complete bool
```

### foods (reference — see 04 for full field list & licensing)
```
id uuid pk
name text · name_local jsonb · type text        -- dish|ingredient|branded_product
barcode text null · cuisine_region text · food_group text
basis text default 'per_100g'
energy_kcal numeric
macros jsonb        -- protein_g, carbohydrate_g, sugars_g, fat_g, saturated_fat_g, fiber_g
micros jsonb        -- iron_mg, calcium_mg, sodium_mg, ... (null where unknown)
serving_units jsonb -- [{unit,label,grams,is_default}]
source text         -- curated_ifct|openfoodfacts|usda_fdc|indb|ai_estimate
source_ref text · license text · confidence numeric · verified_by_human bool
```
> OFF-sourced rows are kept source-tagged (and logically separable) to contain ODbL share-alike.

### user_plans (the plan engine store)
```
id uuid pk · user_id
name text · goal text · source text   -- ai_generated|user_imported|template
config jsonb        -- the full Plan JSON (see architecture/04-plan-engine.md)
duration_days int null · start_date date · is_active bool
```
> `config` is interpreted by the app engine, never hardcoded. One active plan per user (enforced by
> partial unique index on `(user_id) where is_active`).

### diary_days (per-day rollup — the dashboard's backbone)
```
id uuid pk · user_id · date date
resolved_day_type text            -- computed from active plan schedule
targets jsonb                     -- resolved calorie/macro/water targets for the day
totals jsonb                      -- summed calories/macros/micros/water from logs
checklist_state jsonb             -- {item: done_bool}
unique (user_id, date)
```

### food_logs
```
id uuid pk · user_id · date date · meal text   -- breakfast|lunch|dinner|snack
food_id uuid fk foods null        -- null when free-text/AI one-off
name text                         -- denormalized for offline display
serving_qty numeric · serving_unit text · grams numeric
computed jsonb                    -- {energy_kcal, macros{}, micros{}} for this entry
logged_via text                   -- photo|voice|text|barcode|search|template
photo_path text null              -- Supabase Storage path
ai_confidence numeric null        -- when logged_via=photo/AI
```

### Simple log tables
```
water_logs:      user_id, date, amount_ml, logged_at
weight_logs:     user_id, date, weight_kg, note
workout_logs:    user_id, date, type, duration_min, calories_burned, intensity, source
step_days:       user_id, date, steps, distance_m, source (pedometer|healthkit)
sleep_logs:      user_id, date, bedtime, wake_time, duration_min, quality, source (manual|healthkit)
fasting_sessions: user_id, start_at, end_at null, target_hours, status (active|completed|broken)
```

### AI tables
```
coach_messages:  user_id, role (user|assistant|system), content, context_snapshot jsonb,
                 model, tokens_in, tokens_out, created_at
user_ai_keys:    user_id pk, provider text, key_ciphertext bytea,  -- envelope-encrypted (Vault/KMS)
                 key_last4 text, is_active bool           -- NEVER store or return plaintext
ai_usage:        user_id, feature (photosnap|coach|plan), model, tokens_in, tokens_out,
                 cost_usd numeric, virtual_key text, created_at   -- mirror of LiteLLM ledger
```

### Templates
```
custom_meals:    user_id, name, items jsonb (list of {food_id, grams}), computed jsonb
food_favorites:  user_id, food_id, last_used_at
```

## RLS pattern (applied to every user table)
```sql
alter table food_logs enable row level security;
create policy "own rows" on food_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```
`foods` is world-readable (`for select using (true)`), writable only by service role / reviewed
promotion pipeline.

## Sync mapping (PowerSync)
- All user tables replicate into local Drift on a per-`user_id` sync rule.
- `foods` replicates a **filtered subset** (India + user's recently used) to keep the local DB small;
  the rest is fetched on demand and cached. NO OFF snapshot ships (ADR 0014) — OFF rows are cached
  per scanned barcode into the separate off_foods table. The USDA seed ships as app data, refreshed
  periodically.
- Append-mostly logs → few conflicts. `diary_days.totals` is recomputed locally from logs and treated
  as derived (server merge recomputes rather than blind LWW).

## Derived-value rule
`diary_days.totals` and per-entry `food_logs.computed` are **derived** from `foods` × `grams`.
Recompute deterministically on the client; never trust a stale total. The one piece of nutrition
logic in code is default-target computation (Mifflin–St Jeor) per
[architecture/04-plan-engine.md](04-plan-engine.md).
