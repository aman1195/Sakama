# Plan Engine — Design Note

> The plan engine is what makes Sakama work "for everyone, not just me." Plans are **data, not
> code**. This note defines the JSON contract. The database wiring lives in
> [architecture/01-data-model.md](01-data-model.md); AI generation of these configs lives in
> [architecture/02-ai-layer.md](02-ai-layer.md).

## Why data, not code

A hardcoded "4-week detox" would only serve one user. Instead a plan is a JSON config the app
*interprets*. A diabetic plan, a muscle-gain plan, and a Tuesday-reset detox are all the same
engine reading different JSON. New plans (AI-generated or user-imported) need **zero app changes**.

## Concepts

- **Plan** — the whole config (goal, duration, day-type schedule, rules).
- **Day type** — a named kind of day (`normal`, `reset`, `refeed`, `fasting`, `detox`). Each has
  its own targets, allowed/blocked foods, fasting window, and checklist.
- **Schedule** — maps calendar days to day types (by weekday, by day-index, or explicit dates).
- **Rules** — declarative special behaviors evaluated by the engine (e.g. "electrolytes matter on
  reset days", "no solid food before 12:00").
- **Checklist** — per-day-type to-do items the user ticks (Type 1 enforcement surface).

## JSON contract (v1)

```jsonc
{
  "schema_version": 1,
  "id": "uuid",
  "name": "4-Week Metabolic Reset",
  "goal": "detox",                       // lose_weight | detox | build_muscle | manage_condition | maintain
  "source": "ai_generated",              // ai_generated | user_imported | template
  "duration_days": 28,                    // null = open-ended
  "created_by": "user_uuid | system",
  "targets_default": {                    // fallback when a day type omits a field
    "calories": 1600,
    "macros": { "protein_g": 90, "carb_g": 150, "fat_g": 50, "fiber_g": 30 },
    "water_ml": 3000
  },
  "day_types": {
    "normal": {
      "label": "Normal day",
      "targets": { "calories": 1600, "macros": { "protein_g": 90, "carb_g": 150, "fat_g": 50, "fiber_g": 30 } },
      "fasting_window": { "eat_start": "08:00", "eat_end": "20:00" },  // null = no fast
      "allowed_foods": null,              // null = anything; else list of food ids/tags
      "blocked_foods": ["sugar", "refined_flour"],
      "checklist": ["10k steps", "30 min walk"]
    },
    "reset": {
      "label": "Tuesday reset",
      "targets": { "calories": 1200, "macros": { "protein_g": 80, "carb_g": 80, "fat_g": 40, "fiber_g": 35 } },
      "fasting_window": { "eat_start": "12:00", "eat_end": "20:00" },
      "allowed_foods": ["vegetables", "coconut_water", "clear_soup"],
      "blocked_foods": ["grains", "dairy"],
      "checklist": ["Electrolytes / coconut water", "3L water", "No solid food before 12:00"]
    }
  },
  "schedule": {
    "type": "weekly",                     // weekly | cyclic | explicit
    "map": { "mon": "normal", "tue": "reset", "wed": "normal",
             "thu": "normal", "fri": "normal", "sat": "normal", "sun": "normal" }
    // cyclic:   { "type": "cyclic", "cycle": ["normal","normal","reset"] }
    // explicit: { "type": "explicit", "dates": { "2026-07-15": "detox" } }
  },
  "rules": [
    { "id": "reset_electrolytes", "when": { "day_type": "reset" },
      "effect": { "emphasize": ["electrolytes", "coconut_water"] },
      "message": "It's your reset day — electrolytes from coconut water matter more today." },
    { "id": "no_solids_am", "when": { "day_type": "reset", "before": "12:00" },
      "effect": { "block_logging": ["solid_food"] },
      "message": "No solid food before noon on reset days." }
  ]
}
```

### Engine responsibilities (app side)
1. **Resolve today's day type** from `schedule` + today's date/weekday/day-index.
2. **Compute today's targets** = day-type targets merged over `targets_default`.
3. **Enforce** `fasting_window`, `allowed/blocked_foods`, and `rules` (warn or block on log).
4. **Surface** the day-type `checklist` and tick state.
5. **Feed context** (active plan, resolved day type, targets, checklist state) to Vita.

### Forward-compat rules
- `schema_version` gates the interpreter; unknown fields are ignored, never fatal.
- Unknown `rules[].effect` keys are skipped with a soft log, so AI can propose richer rules than the
  current app understands without breaking older clients.
- Everything optional falls back to `targets_default`, then to a computed maintenance default
  (Mifflin–St Jeor + activity factor) if no plan is active at all (Type 3 users).

## Default target computation (no active plan)

For Type 3 users and as the ultimate fallback:
- BMR via **Mifflin–St Jeor** from profile (age, weight, height, gender).
- TDEE = BMR × activity factor (sedentary 1.2 → very active 1.9).
- Goal adjustment: −15–20% for loss, +10–15% for muscle gain, 0 for maintain.
- Macro split by goal (e.g. higher protein for muscle/loss), fiber target ~30 g.

This computation is the one piece of "nutrition logic" that lives in code; everything protocol-
specific lives in plan JSON.
