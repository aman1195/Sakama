# App Store Listing

> Version-controlled store metadata. Convention from Fud AI. Update in the same PR as the release.

## App Name
Sakama

## Subtitle (30 chars max)
`AI food & health tracker`

## Promotional Text (170 chars max)
_(editable without review)_
> Snap a photo of your thali — Sakama logs the calories, macros and micros. Free forever. No ads.

## Keywords (100 chars max)
`calorie,indian food,macro,nutrition,diet,ai,fasting,water,weight,health,tracker,roti,dal`

## Category
Primary: **Health & Fitness** · Secondary: Food & Drink

## Description
_(Lead with the Indian + AI + free angle. Keep the first 2 lines strong — that is all most users read.)_

## What's New
_(Per release. Mirror `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt`.)_

## URLs
- Privacy Policy: _TBD (required — we handle health data)_
- Terms: _TBD_
- Support: _TBD_
- Marketing: _TBD_

## ⚠️ Reviewer Notes (health apps get extra scrutiny — do not leave blank)
- Sakama is a **nutrition tracker**, not a medical device. It does not diagnose or treat.
- **HealthKit:** we read steps/sleep and write nutrition. Health data is **never** used for advertising and
  **never** shared with third parties.
- **AI:** meal photos and text descriptions are sent to an LLM provider to estimate nutrition. **HealthKit
  records are never sent.** Users may supply their own API key (BYOK).
- No account is required to try core tracking.
- Demo credentials: _TBD_

## Required declarations
- Privacy Manifest (`PrivacyInfo.xcprivacy`) must declare health data collection accurately.
- We collect health data. **We do not sell it.** Say so plainly.
