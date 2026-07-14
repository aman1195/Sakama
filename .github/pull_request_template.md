## What & why
<!-- What changed, and why. Link the issue. -->

Closes #

## Checklist

### Correctness
- [ ] Edge cases handled (timezones, day boundaries, unit conversion)
- [ ] Nutrition stored **per 100 g**; servings derived at read time
- [ ] **Works offline** — UI reads local Drift, not the network

### Data & privacy
- [ ] **RLS** on any new user table (`auth.uid() = user_id`)
- [ ] No health PII in logs / analytics / crash reports
- [ ] No provider API key reachable from the client; BYOK keys encrypted + redacted

### Licence (blocking — Sakama is closed-source)
- [ ] New deps are permissive (MIT / Apache-2.0 / BSD / CC0). **No GPL/AGPL, no unlicensed repo**
- [ ] No code copied from a copyleft app (OpenNutriTracker, wger, FoodYou, Waistline)
- [ ] Food rows carry `source`, `licence`, `confidence`; OFF data kept in its **separate** table
- [ ] Ran the **`licence-guard`** agent if deps or food data changed

### Mobile (see docs/MOBILE.md)
- [ ] **Drift schema change? → migration written AND migration test passing.** A bad migration destroys user data irrecoverably
- [ ] Risky change is behind a server-side kill switch (we cannot hotfix — store review takes days)
- [ ] Accessibility identifier on every new interactive widget

### Quality
- [ ] Pure logic (nutrition math, plan engine) covered by tests
- [ ] Follows `docs/DESIGN.md` — no "AI chrome"
