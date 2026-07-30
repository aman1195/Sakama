# Sakama Privacy Policy

**Status: DRAFT for the operator's review. This document is drafted from the app's actual
data flows (see the recipient table below), but it is not legal advice. Before publishing,
the data fiduciary (see "Who we are") must confirm the legal entity name and address, appoint
a grievance contact, and obtain a lawyer's review for India's Digital Personal Data Protection
Act, 2023 (DPDP) and, if applicable, the EU/UK GDPR.**

**Last updated: _[fill on publish]_**
**Effective date: _[fill on publish]_**

---

## Who we are

Sakama ("Sakama", "we", "us") is a personal health and nutrition application. The operator and
data fiduciary is **_[confirm the exact registered legal entity name and registered address]_**.

For any privacy question, data-rights request, or grievance, contact:
**_[confirm a monitored mailbox, for example privacy@sakama.app]_**.

> **Action before publish:** DPDP requires a named, reachable grievance contact. Confirm the mailbox
> is live and monitored. Note that `contact@sakama.app` is already used as the Open Food Facts
> User-Agent contact (see the OFF section) and must also be a real, monitored mailbox, because OFF
> may block clients it cannot reach.

## The short version

- Sakama is **offline-first**. Your health data lives on your device as the source of truth and works
  with no network connection.
- We collect the data **you enter** to run the app: your food log, your profile (including any health
  conditions you choose to add), your weight, and your water intake.
- Some **optional AI features** send data off your device to an AI provider so they can work. You are
  told exactly what is sent, and you must turn AI on before anything is sent. You can turn it off at
  any time in **Me → AI & privacy**.
- The **barcode scanner** sends the scanned barcode (and, unavoidably, your device's IP address) to
  Open Food Facts to look up a product. No account or identity is attached to that request.
- We **do not sell your personal data**, and the AI provider we use operates on a **paid tier that does
  not train on your data**.

## What we collect and store

You provide this data by using the app. It is stored on your device and, when sync is enabled and you
are signed in, replicated to our backend so it survives a device change.

| Category | Examples | Where it lives |
|---|---|---|
| Profile | date of birth, sex, height, weight, activity level, goal, diet, cuisine, and **health conditions** you add (for example diabetes, PCOS) | On device; synced to backend |
| Food log | items, meals, amounts, calories and macronutrients, how each item was logged (search, barcode, photo, AI estimate) | On device; synced to backend |
| Body metrics | weight entries over time, water intake | On device; synced to backend |
| Account identity | an anonymous device identifier by default; your email address only if you create an account | Backend authentication |
| Your own AI key (optional) | an OpenRouter API key you choose to add ("BYOK") | **Only** in your device's secure storage (Keychain / Android Keystore). It is never stored on our servers and never written to our logs. |

**Health conditions are sensitive personal data.** We process them only to personalize the app and,
if you turn on the AI coach, to let the coach give advice that fits your situation. See the next section.

We do **not** collect your contacts, precise location, advertising identifiers, or browsing history.

## When data leaves your device, and to whom

Sakama shares data with the following recipients, and only for the purposes stated. These are the
**only** third parties that receive your data.

### 1. Our backend and sync (Supabase and PowerSync)

When you are signed in and sync is enabled, your profile, food log, weight, and water data are
replicated between your device and our backend so you do not lose your history. This uses:

- **Supabase** (Postgres database, authentication, storage, and serverless functions) as our backend
  processor. Access is restricted per user by row-level security.
- **PowerSync** (JourneyApps) as the synchronization service that moves data between your device and
  our backend.

These providers act as our processors under our instructions. They do not use your data for their own
purposes.

### 2. AI features (OpenRouter and Google)

Sakama's AI features are **optional** and **off until you turn them on**. When you enable them, and only
then, the following is sent to our AI provider so the feature can work:

- **PhotoSnap** sends the **food photo** you take.
- **AI estimate** sends the **dish name** you type.
- **Coach (Vita)** sends your **recent food log and your profile, including any health conditions you
  have added**, so its advice fits you.

This data is routed through our own server function to our AI gateway, **OpenRouter**, which forwards it
to the model provider, **Google (Gemini)**. We use a **paid tier that does not train on your data and
does not use it for human review**. The photo and text are used to produce the response and are not
stored by Sakama after the response is returned.

You can turn all AI features off at any time in **Me → AI & privacy**. Turning them off stops all of the
above; the rest of Sakama keeps working offline.

If you add **your own AI key** (BYOK), your requests go to OpenRouter under your own key. Your key stays
on your device and is used only to authorize those requests.

### 3. Product lookups (Open Food Facts)

When you scan a barcode, the app queries **Open Food Facts** (`world.openfoodfacts.org`) to find the
product. That request necessarily reveals **the scanned barcode and your device's IP address** to Open
Food Facts. **No account, name, or user identifier is attached.** Open Food Facts is an independent
open database with its own terms and privacy practices.

We identify our app to Open Food Facts with a contact address in the request, as their terms require.

### Recipient summary

| Recipient | What it receives | Purpose | Sensitive data? |
|---|---|---|---|
| Supabase | Profile, food log, weight, water, account identity | Backend storage and auth | Yes (health conditions), if synced |
| PowerSync | The same data, in transit | Device ↔ backend sync | Yes, in transit |
| OpenRouter → Google (Gemini) | Photo, dish name, or log + profile incl. health conditions | Run the AI feature you enabled | Yes, for the coach |
| Open Food Facts | Scanned barcode + device IP | Look up a scanned product | No |

## Legal basis and consent

- We process the data you enter to **provide the app you asked for**.
- We process your data for **AI features only with your consent**, collected through the in-app
  disclosure the first time you use an AI feature. You may withdraw that consent at any time by turning
  AI off.
- Health conditions are processed to personalize the app and, with your consent, the AI coach.

## Data retention and deletion

- Data on your device remains until you delete it or uninstall the app.
- Synced data remains in our backend while your account exists.
- You may request deletion of your account and associated backend data by contacting us at the address
  above. **_[Confirm the operational deletion path and target turnaround before publish.]_**

## Your rights

Depending on where you live, you have rights to access, correct, and delete your personal data, to
withdraw consent, and to complain to a regulator. Under India's DPDP Act you also have the right to
nominate another person to exercise your rights and the right to grievance redressal through the contact
above. To exercise any right, contact us at the address in "Who we are".

## Children

Sakama is not directed to children. **_[Confirm the minimum age and any parental-consent handling
required by DPDP for the target markets before publish.]_**

## Security

Your data is protected in transit and at rest by our backend provider, and access to synced data is
restricted per user by row-level security. Your optional AI key is held only in your device's secure
storage. No system is perfectly secure, and we cannot guarantee absolute security.

## Changes to this policy

We will update this policy as the app changes and will revise the "Last updated" date. Material changes
will be surfaced in the app.

## Contact

**_[monitored privacy mailbox]_** — for privacy questions, data-rights requests, and grievances.
