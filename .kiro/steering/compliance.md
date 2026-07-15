# Compliance & Data Protection (MANDATORY)

Sakama handles **health data** — a special category of personal data. Before writing or reviewing ANY code
that touches auth, user data, food logs, health metrics, photos, AI calls, or logging, apply these rules.

> Adapted for Sakama. Helium's SOC 2 / Cognito policies do **not** apply here — different product, different
> stack (Supabase Auth, not Cognito), different risk surface.

## Our actual regulatory surface
- **India DPDP Act 2023** (our primary market) and **GDPR** (any EU user). Health data is sensitive under both.
- **Apple / Google store policies** for health apps — stricter than the law in practice, and they gate shipping.
- **No SOC 2 programme.** Do not cite one.

## Non-negotiables (see [SECURITY.md](../../SECURITY.md))
| Area | Rule |
|---|---|
| Data isolation | **RLS on every user table** (`auth.uid() = user_id`). A new user table without RLS is a blocking defect. |
| API keys | **No provider key in the client, ever** (OWASP Mobile M1). All LLM calls go Edge Function → managed AI gateway → paid provider tier (ADR 0011). |
| BYOK keys | Envelope-encrypted at rest. **Never logged. Never returned to the device.** |
| AI boundary | Meal photos/text may go to an LLM provider. **HealthKit records must never leave the device.** Declare what we send. |
| Analytics | **No health data** (weight, conditions, food logs) in analytics or crash reports. |
| Deletion | Users can export and delete all their data. Build it, do not retrofit it. |
| Selling data | **Never.** It is a core product promise, not just a policy. |

## Licence compliance is a compliance issue here
Sakama is **closed-source and commercial**. Copyleft contamination is existential.
Run the **`licence-guard`** agent before merging anything that adds a dependency, vendors code, or touches
food data. See [ASSET_CREDITS.md](../../ASSET_CREDITS.md) for the ODbL / CC BY obligations we actually carry.
