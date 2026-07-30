# Store privacy declarations and pre-submission checklist

This maps Sakama's actual data flows (see [privacy-policy.md](privacy-policy.md)) to the answers the
app stores require. It exists so the App Store privacy questionnaire, the Play Data-safety form, and the
DPDP notice are all consistent with the code and with each other. **#43 and #60 gate release on these.**

**Status: DRAFT for the operator's review.** The answers below reflect the app as built. Confirm the
legal-entity and retention details marked _[confirm]_ before submitting.

## Recipients (must appear in every artefact)

Every privacy artefact must name **both** external recipient classes. Missing either is the specific
failure #43 and #60 call out.

1. **AI provider — OpenRouter, forwarding to Google (Gemini).** Receives photos, dish names, or the
   food log plus profile including health conditions, and only when the user has enabled AI. Paid tier,
   no training, no human review.
2. **Open Food Facts.** Receives the scanned barcode and the device IP on a barcode lookup. No user
   identifier attached. This path is **not** covered by the AI-consent gate because it is a different
   recipient for a different purpose; it must still be disclosed.

Backend processors that also receive data when sync is on: **Supabase** (storage/auth) and **PowerSync**
(sync transit). These are processors acting on our instructions, not independent controllers.

## Apple — App Store privacy "Nutrition Labels"

Declare the following data types. For each, Apple asks: collected? linked to identity? used for tracking?
**Sakama uses none of this data for tracking, and runs no third-party ads or analytics SDKs.**

| Apple data type | Collected | Linked to user | Tracking | Notes |
|---|---|---|---|---|
| Health & Fitness (food log, weight, water, health conditions) | Yes | Yes, when signed in and synced | No | Core function. Sensitive; see below. |
| Contact Info — Email address | Yes, only if the user creates an account | Yes | No | Anonymous by default; email is optional. |
| User Content — Photos | Yes | No | No | PhotoSnap photo is sent to the AI provider to analyze; not stored by us. |
| Identifiers — User ID | Yes | Yes | No | Anonymous device identifier or account id. |
| Diagnostics | _[confirm]_ | — | No | Only if crash/diagnostics reporting is added later. Currently none. |

- Under "Third parties," disclose that photos and (for the coach) health data are sent to an **AI service
  provider**, and that barcode scans query **Open Food Facts**.
- Provide the **privacy-policy URL** in App Store Connect.
- If the app declares any Apple **required-reason APIs** (for example `UserDefaults` via
  `shared_preferences`), ensure each has a declared reason in the app's `PrivacyInfo.xcprivacy`.
  **_[confirm the app-level privacy manifest is present and complete for the release build.]_**

## Google — Play Data safety form

| Play data type | Collected | Shared | Purpose | Optional |
|---|---|---|---|---|
| Health and fitness info (incl. health conditions) | Yes | Shared with the AI provider only when AI is enabled | App functionality; personalization | AI sharing is optional (off by default) |
| Personal info — Email | Yes | No | Account | Yes (account optional) |
| Photos | Yes | Shared with the AI provider for PhotoSnap | App functionality | Yes (feature optional) |
| App activity — in-app actions (food log) | Yes | With backend processor for sync | App functionality | — |
| Device or other IDs | Yes | With Open Food Facts (IP on lookups) | Product lookup | — |

- Declare data **encrypted in transit**.
- Declare a way for users to **request deletion**. **_[confirm the deletion path.]_**
- Mark AI-related sharing as tied to an **optional feature** the user turns on.

## India DPDP notice (in-app / at consent)

The AI-consent disclosure already shown in-app (Me → AI & privacy, and the first-use sheet) covers the
AI recipient. For DPDP the fuller notice must also:

- Identify the **data fiduciary** (legal entity) and the **grievance contact**.
- State the **purpose** of processing health data and that it is done on **consent**.
- Describe the **right to withdraw consent** (turning AI off; deleting the account) and **grievance
  redressal**.
- Name **Open Food Facts** as a recipient for barcode lookups.

The public privacy policy is the durable artefact for this; link it from the app.

## Pre-submission checklist (release gate)

- [ ] Legal entity name and registered address confirmed and filled into the policy.
- [ ] Monitored **privacy/grievance mailbox** live (for example `privacy@sakama.app`).
- [ ] `contact@sakama.app` (Open Food Facts User-Agent contact) confirmed **live and monitored** — OFF
      may block clients it cannot reach.
- [ ] Privacy policy **hosted at a public URL** and linked in-app and in both store listings.
- [ ] App Store privacy questionnaire completed per the table above.
- [ ] Play Data-safety form completed per the table above.
- [ ] iOS app-level **`PrivacyInfo.xcprivacy`** present with required-reason API declarations.
- [ ] Account/data **deletion path** implemented or documented, with a stated turnaround.
- [ ] Both external recipients (**AI provider** and **Open Food Facts**) named in **every** artefact:
      policy, App Store, Play, DPDP notice.
- [ ] Minimum-age / children handling confirmed for the target markets.

## Cross-references

- Data flows and recipient detail: [privacy-policy.md](privacy-policy.md)
- AI gateway architecture and the paid-tier / no-training decision: [../adr/0011-serverless-ai-gateway.md](../adr/0011-serverless-ai-gateway.md)
- In-app AI disclosure and consent gate: `app/lib/features/settings/presentation/ai_disclosure.dart`,
  `ai_privacy_page.dart`
- Open Food Facts client and User-Agent contact: `app/lib/features/foods/data/off_client.dart`
