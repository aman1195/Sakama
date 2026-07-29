# Mobile Realities

> **Read this before applying any convention inherited from ModelBeat or Helium.** Those are **web**
> projects. Sakama is a **mobile app**, and the differences are not cosmetic — they change what "safe to
> ship" means.
>
> Web conventions that transfer: git flow, commits, PRs, ADRs, TDD, code review, security-by-RLS.
> Web conventions that **do not**: deploy-to-fix, server-side data migrations, Core Web Vitals,
> browser-based performance work.

## Where our mobile conventions come from

**The right references for mobile process are [OpenNutriTracker](research/eval-opennutritracker.md) and
[Fud AI](research/eval-fud-ai.md)** — both are shipping health apps on both stores, so they have already
solved the problems the web repos never faced. We take their **process conventions** (ideas and structure,
not code — OpenNutriTracker is GPL and must never be copied):

| Convention | From | Where it lives in Sakama |
|---|---|---|
| Store listing as **version-controlled files** (char limits, keywords, **Reviewer Notes**) | Fud AI | [APPSTORE.md](../APPSTORE.md), [PLAYSTORE.md](../PLAYSTORE.md) |
| `fastlane/metadata/` — per-locale title/descriptions, per-versionCode changelogs | OpenNutriTracker | `fastlane/metadata/android/en-US/` |
| **`ASSET_CREDITS.md`** — attribution for every dataset and asset | Fud AI | [ASSET_CREDITS.md](../ASSET_CREDITS.md) — **a legal obligation for us (ODbL, CC BY)** |
| **Release keystore SHA-256 fingerprint** published so users can verify a build was signed by us | OpenNutriTracker | §3 below |
| `justfile` task runner (`install`, `build`, `format`, `analyze`, `test`, `ci`) | OpenNutriTracker | [justfile](../justfile) |
| Separate **iOS and Android release workflows** | Fud AI | `.github/workflows/` |
| **Accessibility identifiers** on every interactive widget for UI-driver tests | OpenNutriTracker | §4 below |
| SECURITY.md with **Safe Harbor** + supported versions | Fud AI | [SECURITY.md](../SECURITY.md) |

### The most valuable thing we learned from them
**Fud AI does not bundle the Open Food Facts database — it queries the API live, per barcode.** That is a
deliberate **ODbL-avoidance strategy**: if you never distribute a derived database, share-alike never
triggers. Shipping an OFF snapshot is precisely what *would* trigger it — which is why we do NOT ship one ([ADR 0014](adr/0014-off-live-lookup-only.md)). Both options, and the
trade-off against our offline-first promise, are written up in [ASSET_CREDITS.md](../ASSET_CREDITS.md).

---

## 1. The four differences that actually bite

### ⚠️ 1. You cannot hotfix. A bad release is live for days.
On the web you push a fix and it is live in minutes. On mobile, **App Store review takes days**, and even
after approval users must *update*. A bad build is in your users' hands until they choose to upgrade.

**Consequences (mandatory):**
- **Staged rollout** on Play (start ≤10%); phased release on App Store. Watch crash-free rate before
  widening.
- **Server-side kill switches / feature flags** for anything risky. If a feature can be disabled from
  Supabase without a new build, it can be saved. If it cannot, it is a permanent liability.
- **Minimum-version gate.** The app must be able to tell the user "please update" and block a known-broken
  build. Build this in M0-M1, not after the first incident.
- Never ship a risky change and a store submission on the same day as a deadline.

### ⚠️ 2. The user's data lives on their device. A bad migration destroys it irrecoverably.
This is the single biggest difference from web. On the server, a botched migration is restored from a
backup. On device, **there is no backup and no rollback** — a broken Drift migration silently destroys a
user's food logs, and you cannot get them back.

**Rules:**
- **Every Drift schema change requires a written, tested migration.** No exceptions.
- **Migration tests are mandatory**: open a DB at schema `N`, migrate to `N+1`, assert the data survived.
  Drift's schema-version test harness exists for exactly this.
- **Never renumber or reuse a schema version.** Never edit a shipped migration.
- Migrations must be **forward-only and idempotent**. Users skip versions (they update from v3 to v9).
- Because PowerSync mirrors Supabase, a Postgres schema change and a Drift schema change must be
  **released together and be backward-compatible** — an old client will still be talking to the new server
  for weeks.

### ⚠️ 3. Offline is a requirement, not an enhancement.
Indian mobile networks are unreliable. A user logs a meal in a basement restaurant. **The log must
succeed.** This is why local Drift is the source of truth and the UI never reads the network
([ADR 0003](adr/0003-supabase-offline-first-drift-powersync.md)). Any feature that breaks without a
connection is a defect, not a limitation.

### ⚠️ 4. Permissions and privacy declarations gate shipping.
The store will reject you. Plan for it.
- Every permission (camera for PhotoSnap, microphone for voice logging, HealthKit, motion for steps,
  notifications) needs a **purpose string** in `Info.plist` and a justified Android manifest entry.
- **Request permission in context, at the moment of use** — never in a wall at launch.
- **Apple Privacy Manifest** (`PrivacyInfo.xcprivacy`) and **Play Data Safety** form must accurately
  declare what we collect. We collect health data; we must say so, and say we do not sell it.
- **HealthKit has extra App Review scrutiny.** Health data must not be used for advertising, and must not
  be shared with third parties. Our AI calls send *food descriptions*, not HealthKit records — keep that
  boundary explicit and documented.

---

## 2. Performance targets (mobile, not web)

Delete every instinct about TTFB, LCP, CLS, and bundle size. The metrics that matter here:

| Metric | Target | Why |
|---|---|---|
| **Cold start to interactive** | < 2 s | The app is opened for 10-second sessions. Startup *is* the experience. |
| **Log-a-meal (photo → logged)** | < 10 s end-to-end | The core loop. See [DESIGN.md](DESIGN.md). |
| **UI jank** | 0 dropped frames on the diary scroll | Jank reads as "cheap" instantly. |
| **App download size** | as small as practical | Data is expensive for much of our market. Watch the ML Kit / scanner payload — Smooth App splits `ml_kit` and `zxing` engines for exactly this reason. |
| **Battery / thermal** | no measurable drain at idle | Background steps + sync must be cheap. |
| **Crash-free sessions** | > 99.5% | Gate for widening a staged rollout. |
| **Offline correctness** | 100% of log paths work with airplane mode on | Non-negotiable. |

---

## 3. Release process

| Stage | Action |
|---|---|
| **Versioning** | `major.minor.patch+build`. Build number **always increments**, never reuses. |
| **Signing** | iOS: certificates + provisioning profiles (never in the repo — CI secrets). Android: upload keystore, backed up and **not** in git. **Losing the keystore means losing the ability to update the app, permanently.** |
| **Signature transparency** | Publish the release certificate's **SHA-256 fingerprint** so a security-conscious user can verify a downloaded build was signed by us (`keytool -list -v -keystore <ks> -alias <alias>`). The fingerprint is stable for the life of the key. **Rotating the signing key forces every existing user to uninstall before upgrading** — treat key rotation as a last resort. *(Convention from OpenNutriTracker.)* |
| **Automation** | `fastlane` for build, sign, and upload (both stores). |
| **Internal test** | TestFlight (iOS) / Play Internal Testing (Android). Dogfood every release. |
| **Rollout** | Play staged rollout (10% → 50% → 100%) and App Store phased release. Watch crash-free rate at each step. |
| **Rollback** | **There is none.** You can halt a Play rollout, but shipped is shipped. Roll *forward* with a hotfix build, and use the kill switch meanwhile. |
| **Store review** | Budget days, not minutes. Health apps get extra scrutiny. Have the privacy policy and data-safety answers ready. |

---

## 4. Accessibility (mobile, not WCAG-for-browsers)

WCAG 2.1 AA still applies in spirit, but the mechanics are platform-native:
- **VoiceOver (iOS) / TalkBack (Android)** labels on every interactive element.
- **Dynamic Type / font scaling** — our users span teens to 60s. Layouts must not break at large text sizes.
- **Stable accessibility identifiers** (kebab-case, locale-independent) on every interactive widget, so UI
  test drivers can find them. This is a convention, enforced at review.
- **Reduced Motion** honoured for every transition.
- Tap targets ≥ 44×44 pt.

---

## 5. What we keep from the web repos

To be explicit, these inherited conventions **are** correct and stay:
- Git branching, conventional commits, PR discipline ([DEVELOPER_STANDARDS.md](../DEVELOPER_STANDARDS.md))
- ADRs ([adr/](adr/)), the skills library, code review culture
- RLS-first data isolation, secrets hygiene, no keys in the client
- TDD for pure logic

And these do **not** apply and have been removed or rewritten:
- `benchmark` skill (Core Web Vitals / Next.js) — **deleted**
- `web-design-guidelines` skill (Web Interface Guidelines) — **deleted**
- `impeccable` and `emil-design-eng` — kept, but their examples are **web**. Take the *taste*, not the CSS.

## Pre-release routine addendum (learned in device dogfood, 2026-07)

Before every device deploy / release build, run the **production-stack integration test on a
simulator** in addition to the unit/widget suite:

```
flutter test integration_test/ -d <simulator>
```

Widget tests override `databaseProvider` with plain Drift tables; the REAL app runs on PowerSync
**views**. That gap hid two shipped-quality bugs the simulator run catches structurally
(`cannot UPSERT a view`; anything touching view semantics, triggers, or the sync-attached DB path).
The integration suite drives real flows (onboarding → shell) with zero provider overrides.
