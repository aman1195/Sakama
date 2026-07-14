# Product

## Register

product

## Users

Indian consumers managing their health through food. Three distinct types, all first-class:

- **Plan followers** — already have a protocol (custom meal plan, fasting window, weekly reset day, detox). They need the app to *enforce and track* it faithfully.
- **Goal setters** — say "lose 10 kg", "improve liver health", "build muscle". They need the app to *generate* a plan, then track it.
- **Casual trackers** — just want to log food, see macros, and get gentle nudges. No rigid plan.

Concretely: a diabetic housewife in Chennai, a gym-going 22-year-old in Delhi, a 45-year-old executive managing fatty liver in Bengaluru. Sessions are short and habitual — log a meal in under ten seconds, glance at the day, occasionally ask the coach a question. Most logging happens *while eating*, one-handed, often on a poor connection.

## Product Purpose

Sakama is a free, AI-powered personal health and nutrition OS for India. One place to track calories, macros, micronutrients, water, fasting, weight, workouts, steps, and sleep — logged by photo, voice, text, barcode, or search.

The wedge is the **AI layer**. Modern LLMs are far more capable than the models most health apps run, so a coach that knows your exact plan, today's logs, your streak, and your weekly trend can say something genuinely useful. The difference between "drink more water" and "you have had 1.8 L today and it is 4 PM, you need 1.7 L more before 9 PM, and it is your reset day so electrolytes from coconut water matter more today" is the entire product.

HealthifyMe charges heavily for a human nutritionist. Sakama does it better, instantly, and free.

**Core promise: Free forever. No ads. No data selling. Better AI than HealthifyMe. Built for India.**

Success looks like: a user logs a thali by photo in six seconds, trusts the numbers, and comes back tomorrow without being nagged.

## Brand Personality

Warm. Knowing. Effortless.

Sakama should feel like a friend who happens to be a brilliant nutritionist — not a spreadsheet, not a drill sergeant, and not a chatbot performing enthusiasm. It knows Indian food without being told. It never shames. It reduces work.

## Anti-references

- **Guilt-driven fitness apps** — red "over budget" banners, streak-loss shaming, aggressive push notifications. Health is not a punishment loop.
- **Spreadsheet-with-a-skin trackers** — endless manual entry, gram-level data entry as the primary path, no intelligence.
- **Generic AI-branded UI** — gradient cards, glowing purple accents, animated counters, a sparkle icon on everything. The AI should be felt in the *quality of the answer*, not the chrome.
- **Western-default food apps** — where "1 serving" means a cup, Indian dishes are missing, and a roti has to be logged as "flatbread, generic".
- **Premium walls on basics** — locking calorie tracking or the food database behind a subscription.

## Design Principles

1. **Friction is the enemy.** Logging is the core loop and it must be near-instant. Photo, voice, and barcode exist so nobody types grams. If a flow takes more than three taps, it is a bug.
2. **India is the default, not a locale.** Katori, roti, idli, dosa, phulka are first-class units. Regional cuisines, veg/non-veg/eggetarian/Jain, and conditions like PCOD, thyroid, and fatty liver are built in, not bolted on.
3. **Show the confidence.** AI estimates are estimates. Surface confidence, make correction one tap, and let the user's correction teach the system. Never present a guess as a fact.
4. **The coach earns its place.** Every coach message must reference something real — today's logs, the plan, the streak. Generic advice is worse than silence.
5. **Earn every color.** Green for on-track, amber for attention, red only for genuine problems. Never colour the whole screen by a calorie deficit.
6. **Works on a train with no signal.** Offline is not a degraded mode. Local is the source of truth; sync is invisible.
7. **Free at the core, honestly.** No dark patterns, no artificial limits on basic tracking, no selling data. If we ever monetize, it never touches the core loop.

## Accessibility & Inclusion

WCAG 2.1 AA minimum. Dynamic Type support throughout (users span teens to 60s). Sufficient contrast in light and dark. Reduced-motion alternatives for all transitions. VoiceOver/TalkBack labels on every interactive element, with stable accessibility identifiers for UI test drivers. Localization scaffold from day one, Hindi first, with regional languages to follow — a user should never be blocked from their health data by English.
