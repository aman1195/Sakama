# v1 pre-store launch checklist

The gate between "M3 complete" and "submit to the App Store / Play Store." Grouped by owner:
**[code]** is done in-repo, **[operator]** needs a human/account/legal action only you can take.
Store review takes days and there is no hotfix ([MOBILE.md](../MOBILE.md)), so every box here is a real
gate, not a nicety.

## Privacy & legal (see [privacy-policy.md](privacy-policy.md), [store-privacy-mapping.md](store-privacy-mapping.md))

- [x] **[code]** In-app AI disclosure + first-use consent + AI on/off switch (#60).
- [x] **[code]** Privacy-policy and store-declaration drafts, naming **both** recipients — AI provider and
      Open Food Facts (#43).
- [ ] **[operator]** Fill the policy: legal entity name + registered address, monitored grievance mailbox.
- [ ] **[operator]** Confirm `contact@sakama.app` (Open Food Facts User-Agent contact) is **live and
      monitored** — OFF may block clients it cannot reach.
- [ ] **[operator]** Verify the AI-provider "no training / no human review" claim against OpenRouter's and
      Google's current paid-tier terms; ideally a signed DPA. Do not publish the wording unverified.
- [ ] **[operator]** Host the privacy policy at a public URL; link it in-app and in both store listings.
- [ ] **[operator]** Complete the App Store privacy questionnaire and the Play Data-safety form per the
      mapping doc; re-verify no analytics/ads/crash SDK was added since the draft.
- [ ] **[operator]** Confirm minimum-age / children handling for the target markets; DPDP/GDPR legal review.
- [ ] **[operator]** Implement or document the account/data **deletion** path with a stated turnaround.

## Store-readiness gates ([MOBILE.md](../MOBILE.md))

- [x] **[code]** Min-version gate live end to end: `app_config.min_supported_build` (server) →
      `RemoteConfigService` (fail-open, offline-cached) → `UpdateRequiredScreen`. Verified inert at
      floor 1; raise the floor only to force-retire a broken build ([ADR references](../adr/README.md)).
- [x] **[code]** Server-side feature kill-switches (`flag.*` in `app_config`) so AI features can be
      disabled without a new build.
- [ ] **[operator]** iOS **`PrivacyInfo.xcprivacy`** present at app level with required-reason API
      declarations (e.g. `UserDefaults` via `shared_preferences`).
- [ ] **[operator]** Staged rollout configured on both stores (never 100% day one).
- [ ] **[operator]** Store listing assets: screenshots, description, support URL, category, age rating.

## Abuse & cost (see [ADR 0015](../adr/0015-anon-abuse-posture-v1.md))

- [x] **[code]** Per-user daily AI caps enforced atomically (estimate 10, PhotoSnap 8, Vita 30).
- [x] **[code]** Operator monitoring view `admin_ai_usage_daily` (migration `20260731000006`).
- [ ] **[operator]** Apply the monitoring migration to the live project (`supabase db push`).
- [ ] **[operator]** Confirm Supabase's **anonymous sign-in per-IP rate limit** is enabled in the dashboard.
- [ ] **[operator]** Confirm a hard billing cap / budget alert on the AI provider account (rule 9 backstop).
- [ ] **[operator]** Watch `admin_ai_usage_daily` after launch; add attestation if the farm signal appears
      (the deferred-attestation issue holds the trigger).

## Data safety ([MOBILE.md](../MOBILE.md))

- [x] **[code]** RLS forced on every user table; AI usage/config tables server-write-only.
- [x] **[code]** Forward-only, tested Drift migrations (migration tests are CI-gated).
- [ ] **[operator]** Final device dogfood of the exact release build on iOS **and** Android before submit.

## Cross-references

- Privacy artefacts: [privacy-policy.md](privacy-policy.md), [store-privacy-mapping.md](store-privacy-mapping.md)
- Anon-abuse decision: [ADR 0015](../adr/0015-anon-abuse-posture-v1.md)
- Mobile release realities: [MOBILE.md](../MOBILE.md)
