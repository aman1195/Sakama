# Store privacy forms — fill-in answers

Copy-ready answers for the **App Store privacy questionnaire** and the **Play Data safety** form,
derived from [store-privacy-mapping.md](store-privacy-mapping.md) and the app's actual data flows. Where a
value depends on an operator decision not yet made, it is marked **`⟨CONFIRM⟩`**.

**Global truths for both forms (state these consistently):**

- **No third-party advertising, no analytics/attribution SDKs, no tracking.** Answer "No" to every
  tracking/advertising question.
- **Two external recipients only:** the AI provider (OpenRouter → Google Gemini) and Open Food Facts.
  Supabase and PowerSync are processors (our infrastructure), not independent recipients.
- **AI sharing is optional and off by default** — the user turns it on via in-app consent.
- **Data is encrypted in transit.**

---

## A. Apple — App Store Connect → App Privacy

For each data type Apple asks: *Do you collect it? Is it linked to the user's identity? Is it used for
tracking?* Sakama tracks nothing, so **Tracking = No everywhere.**

### Data collected

| Apple data type | Collect? | Linked to identity? | Tracking? | Purposes to tick |
|---|---|---|---|---|
| **Health & Fitness** (food log, weight, water, health conditions) | Yes | Yes (when signed in + synced) | No | App Functionality |
| **Contact Info → Email Address** | Yes ⟨only if the user creates an account⟩ | Yes | No | App Functionality |
| **User Content → Photos or Videos** | Yes | No | No | App Functionality |
| **Identifiers → User ID** | Yes | Yes | No | App Functionality |
| **Health & Fitness / Other Data** — none beyond the above | — | — | — | — |
| **Usage Data, Diagnostics, Location, Contacts, Browsing, Financial, Purchases** | **No** | — | — | — |

### Notes to enter / keep ready

- **Photos** — "Food photos are sent to our AI service provider to identify the food, and are not stored
  by us." (Used only if the user enables PhotoSnap.)
- **Health & Fitness** — collected to run the diary and, if the user enables the AI coach, sent to our AI
  provider to personalize advice.
- **Data deletion** — Apple requires a way for users to request account+data deletion. ⟨CONFIRM the
  path/turnaround; see checklist.⟩
- **Privacy Policy URL** — ⟨CONFIRM public URL⟩.
- **Account deletion URL / in-app path** — ⟨CONFIRM⟩.

### iOS privacy manifest (`PrivacyInfo.xcprivacy`)

- `NSPrivacyTracking` = **false**; `NSPrivacyTrackingDomains` = empty.
- Required-reason APIs to declare (from the dependency set):
  - **UserDefaults** (`shared_preferences`) → reason **`CA92.1`** (app-owned data on device).
  - ⟨CONFIRM whether `file timestamp` / `system boot time` / `disk space` reasons are pulled in by any
    plugin; add the matching reason string if so.⟩
- `NSPrivacyCollectedDataTypes` should mirror the table above (health, email, photos, user ID), each with
  `Linked = true/false` per the table and `Tracking = false`.

---

## B. Google Play — Data safety

Two sections: **Data collection & sharing**, then **Security practices.**

### Collected / shared

| Play category → type | Collected | Shared | Optional? | Purpose |
|---|---|---|---|---|
| **Health and fitness → Health info** (incl. health conditions) | Yes | Yes — with the AI provider, **only when the user enables AI** | Yes (feature is optional) | App functionality; Personalization |
| **Personal info → Email address** | Yes ⟨if account created⟩ | No | Yes (account optional) | Account management |
| **Photos and videos → Photos** | Yes | Yes — with the AI provider (PhotoSnap) | Yes (feature optional) | App functionality |
| **App activity → Other in-app actions** (food logging) | Yes | No (processor only) | No | App functionality |
| **App info and performance** (crash/diagnostics) | **No** ⟨unless a crash SDK is added⟩ | No | — | — |
| **Device or other IDs** | ⟨CONFIRM taxonomy⟩ | See note | — | Product lookup |

### Notes to enter / keep ready

- **Encryption in transit** = **Yes**.
- **Users can request data deletion** = **Yes** ⟨CONFIRM the mechanism/URL⟩.
- **Committed to Play Families policy?** ⟨CONFIRM target age handling.⟩
- **Device/IP → Open Food Facts:** a barcode lookup sends the barcode and the device IP to Open Food
  Facts, with no account/user identifier attached. IP is a loose fit for the "Device or other IDs"
  category (which targets ad/device identifiers). ⟨CONFIRM during the legal pass whether this belongs
  under "Device or other IDs," elsewhere, or is not a declarable collection since no identifier is
  attached and we do not retain it.⟩
- **AI provider sharing:** mark the health-info and photo rows as **Shared**, tied to an **optional
  feature** the user turns on. Name the recipient class as an "AI service provider" if Play asks.

---

## C. Recipient statements (reuse verbatim)

- **AI provider:** "When you enable an AI feature, the relevant data (a food photo, a dish name, or your
  recent food log and profile including any health conditions) is sent through our server to our AI
  provider, OpenRouter, which forwards it to Google (Gemini), on a paid tier that does not train on your
  data or use it for human review. It is not retained by us after the response."
- **Open Food Facts:** "When you scan a barcode, the barcode and your device's IP address are sent to
  Open Food Facts to look up the product. No account or identifier is attached."

---

## Open confirmations before submit (⟨CONFIRM⟩ roll-up)

1. Email collection wording assumes account is **optional** (anonymous-first) — correct as built.
2. Public **privacy-policy URL** and **account-deletion path/URL**.
3. **Deletion** mechanism + turnaround.
4. **Target age / families** handling for each market (DPDP + Play/Apple).
5. Play **taxonomy** for the OFF device-IP flow.
6. Any **required-reason API** strings beyond UserDefaults pulled in by plugins.
7. Re-confirm **no analytics/ads/crash SDK** has been added since this sheet (would change several rows).

See the release gate in [launch-checklist.md](launch-checklist.md).
