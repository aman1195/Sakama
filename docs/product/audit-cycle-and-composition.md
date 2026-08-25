# Field notes → features: the fortnightly audit, and the numbers we do not keep

> Source: a real, self-published beginner framework by an Indian software engineer who lifted for
> 10+ years ("Fit By Default", June 2026, shared 2026-08-25). Read for **problem discovery only**.
> **Nothing is copied.** Its wording, tables and structure belong to its author; what follows is our
> own reading of the *problems* it documents and our own designs for them. If we ever want its
> content in the product, that is a licensing conversation with the author, not an engineering task.

## Why this source is worth anything

It is not a feature request. It is a **log of what a disciplined user does manually when the app
does not do it for them** — which is the most reliable product input there is. The author is
data-literate, motivated, and still ended up running his system out of a notebook and a spreadsheet.
Everything he had to do by hand is something we already hold the data for.

## The problems it names, in order of how badly we currently serve them

### 1. The scale lies, and it lies hardest exactly when you are doing well

His sharpest point, and the one we serve worst. Four states, one number:

| Scale | Skinfold | What actually happened |
|---|---|---|
| ↓ | ↓ | Fat loss. Good. |
| ↓ | same | **Muscle loss.** Looks like success. Is not. |
| same | ↓ | **Recomposition.** Looks like failure. Is the best outcome available. |
| ↑ | ↓ | Recomposition while gaining. Keep going. |

Sakama shows a weight chart. A user in row 3 sees a flat line for six weeks and quits — during their
best progress. A user in row 2 sees a falling line and celebrates while losing muscle.

**We have no way to distinguish these four states.** That is not a missing metric, it is a wrong
answer delivered confidently.

### 2. Inputs drift silently, and memory covers for it

His plateau, audited: calories had crept up **200–300 kcal** of uncounted snacking; steps had fallen
from a target he had stopped hitting; sleep had slid to 5.5–6 hours; lifts had stopped progressing.
His summary is the useful part — *"the data doesn't lie, your memory does."*

**Every one of those is computable from data we already store** (steps and sleep land in M5). We
currently show today. We do not show *"this fortnight versus last, and here is what moved."*

### 3. A plateau reads as personal failure

He frames it correctly: a plateau means the body adapted, not that you did it wrong. Users quit
here. An app that says *"nothing changed for 14 days"* without a next action makes it worse.

### 4. Changing everything at once teaches nothing

His rule — **one variable per cycle** — is the difference between learning your body and thrashing.
An app that suggests "eat less and walk more and sleep better" is the thrash.

### 5. Eating out is where Indian tracking dies

His fix is one question at the point of ordering: *where is my protein?* Not a diet. A default.

### 6. The gym is not the lever; the other 23 hours are

Home steps, a post-dinner walk, stairs, a podcast and the hallway. Zero friction, no commute, no
excuse — the thing that kept the habit alive on his worst days.

## What we already have, and what is genuinely missing

| Need | Status |
|---|---|
| Food, water, weight logs | Shipped |
| Plans as JSON, day types, targets | Shipped (M4) |
| Vita with memory + grounding | Shipped (ADR 0016) |
| Steps, sleep, HealthKit/Health Connect | **Scoped, M5** |
| Body composition (skinfolds / measurements) | **Not anywhere.** Gap. |
| Trend + drift analysis over weeks | **Not anywhere.** Gap. |
| A structured adjust-and-retest loop | **Not anywhere.** Gap. |

## Proposals

### A · The fortnightly audit — the strongest idea here

Every 14 days, Vita reports what actually changed and proposes **exactly one** adjustment.

Why this is ours to win: **we already hold every input.** A tracker shows numbers; a coach tells you
what they mean and what to do next. That is [PRODUCT.md](../../PRODUCT.md) principle 4 — the coach
earning its place — expressed as a recurring, dated event rather than a chat reply.

It is also, unavoidably, a retention mechanic: a specific reason to open the app on a schedule that
is not a streak nag.

Design notes:
- **Deterministic first, AI second.** The comparison (7-day averages, adherence rate, target-hit
  percentage, drift) is arithmetic and belongs in Dart, tested. Vita explains it and proposes the
  change. Sending raw logs to a model and asking "what changed?" is how you get a confident wrong
  answer, and it costs a call we do not need to spend.
- **Propose-confirm, like every other write.** The suggested change alters plan targets, so it
  arrives as a card the user accepts or declines — never applied silently.
- **One variable.** The UI should make it awkward to change two things, not merely advise against it.
- **Honest when there is nothing to say.** "Two weeks, no meaningful change, and your logging was
  patchy — that is the finding" beats inventing an insight.

### B · Body composition tracking

Weekly skinfolds at fixed sites, plus tape measurements for people without callipers, plus
progress photos stored **device-local only** (they are the most sensitive thing the app would ever
hold — same posture as chats and memory, never synced).

The payoff is not the numbers. It is that the four-state table above becomes answerable, so the app
stops telling a recomping user they are failing.

### C · Drift detection, continuous

Not a fortnightly report — a quiet flag when a 7-day average moves against a 28-day baseline:
*"your daily calories are up ~250 on last month; that is usually untracked snacking."* This is the
thing his audit caught by hand, and it is cheap arithmetic on data we have.

### D · The protein question at the point of ordering

When a user logs something restaurant-shaped, or asks Vita about eating out, one line: what would
add protein to this. Not a lecture, not a refusal — the smallest possible intervention at the moment
it is actionable.

### E · Movement without a gym

A step target that is honest about NEAT, and a post-dinner walk as a plan checklist item. The plan
engine already expresses checklists, so this is mostly content and copy, not engineering.

## Recommendation

**Build A, on top of M5's sensor work, and B before or alongside it** — the audit is much weaker
without composition data, because scale weight alone reproduces exactly the wrong answers in §1.

C is a cheap subset of A's arithmetic and could ship first as a standalone signal.
D and E are content and small surfaces, worth doing while the bigger pieces land.

**What this does not change:** the wedge is still the coaching layer. This proposal is that layer
doing something a tracker structurally cannot — noticing, over weeks, what a person cannot notice
about themselves, and saying it plainly.
