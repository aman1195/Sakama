# Sakama Developer Standards

Mandatory standards. Non-compliance blocks the PR.

## Git & branches

Format: `<prefix>/<ticket>-<description>` in kebab-case.

Prefixes: `feature/` `bugfix/` `hotfix/` `release/` `chore/` `docs/` `refactor/`

```
feature/SAK-14-photosnap-confirm-sheet
bugfix/SAK-31-fasting-timer-timezone
chore/SAK-08-bump-flutter
```

- Main branch is **`main`**. **Never push directly** — always a PR. (Enforced by
  `.claude/hooks/block-push-to-main.py`.)

## Commits

Conventional commits: `type(scope): subject` — `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`.

```
feat(photosnap): add portion confirm sheet
fix(sync): resolve duplicate intake on reconnect
```

## Pull requests

- One logical change. Link the issue. Describe **what** and **why**, not just how.
- **Green CI required**: analyze, format, test, and the **licence check**.
- Run the **`licence-guard`** agent if the PR adds a dependency, vendors code, or touches food data.

## Security & secrets

- **No secrets in the repo.** Ever. Use `.env` (gitignored) + compile-time obfuscation.
- **No provider API key in the client.** All LLM calls go through the Edge Function → LiteLLM proxy.
- BYOK keys: envelope-encrypted at rest, **never logged**, never returned to the device.
- **RLS on every user table.** A new user-data table without RLS is a blocking defect.
- No health data (weight, conditions, food logs) in analytics or crash reports.

## Licence hygiene (existential — Sakama is closed-source)

- **Allowed:** MIT, Apache-2.0, BSD, ISC, CC0. **Forbidden:** GPL, AGPL, SSPL, or *no LICENSE file*.
- **Never copy** from OpenNutriTracker, wger, FoodYou, Waistline (copyleft). Read for understanding only.
- **`Best-Flutter-UI-Templates` is not MIT** despite appearances. Never use.
- **LiteLLM:** MIT except `enterprise/` — never vendor that directory.
- Keep OFF (ODbL) data in a **separate, source-tagged table**. Never merge into the proprietary table.

## Flutter standards

- **Feature-first**: `lib/features/<feature>/{data,domain,presentation}`.
- Riverpod for state/DI. `freezed` for models. `go_router` typed routes.
- **Offline-first**: read local Drift, never the network directly.
- Nutrition stored **per 100 g** canonically; per-serving derived at read time.
- **Accessibility identifier on every interactive widget** (stable, kebab-case, locale-independent).
- Plans are **JSON data**, never hardcoded logic.

## Testing

- **TDD the pure logic**: nutrition math, plan-engine resolution, target computation. No excuses.
- Repository tests against an **in-memory Drift** DB.
- Riverpod provider overrides for widget tests.
- **Integration test for the log → sync → pull loop.** This is the highest-risk path in the app.

## Code review checklist

See [CODE_REVIEW.md](CODE_REVIEW.md).
