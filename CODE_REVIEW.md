# Code Review Standards

## Reviewer checklist

### Correctness
- [ ] Does it do what the PR says? Are edge cases handled (timezones, day boundaries, unit conversion)?
- [ ] Nutrition math correct? Values stored **per 100 g**, servings derived?
- [ ] **Offline path works?** Does the UI read local Drift rather than the network?

### Data & privacy
- [ ] **RLS present** on any new user table (`auth.uid() = user_id`)?
- [ ] No health PII in logs, analytics, or crash reports?
- [ ] No API key in the client? BYOK keys encrypted and redacted from logs?

### Licence (blocking)
- [ ] Any new dependency permissive (MIT/Apache/BSD/CC0)? **No GPL/AGPL, no unlicensed repo.**
- [ ] No code copied from a copyleft app?
- [ ] Food rows carry `source`, `licence`, `confidence`? OFF data kept in its **separate** table?

### AI
- [ ] Calls routed through the Edge Function → LiteLLM proxy (never direct from client)?
- [ ] Cheap model by default? Long system prompts prompt-cached? Per-user budget enforced?
- [ ] AI output validated server-side before persisting (especially plan JSON)?

### Craft
- [ ] Feature-first structure respected? Logic out of widgets?
- [ ] Pure logic covered by tests?
- [ ] Accessibility identifiers on new interactive widgets?
- [ ] Follows [docs/DESIGN.md](docs/DESIGN.md) — and does not add "AI chrome"?

## Reviewer conduct
Review the change, not the person. Ask questions before asserting. **Blocking** comments must name the
concrete failure. Everything else is a suggestion, marked as such.
