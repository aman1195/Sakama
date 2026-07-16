# PhotoSnap Validation Spike — Findings (Phase 0)

> **Verdict: GO.** `gemini-2.5-flash` estimated Indian meals at **9% median calorie error, 18/22 within
> ±30%** — comfortably past the bar in [ADR 0013](../adr/0013-validate-photosnap-before-build.md). The
> failures are diagnosable and have product answers, not model-swap answers.
> Run 2026-07-16 · harness in [`spikes/photosnap-validation/`](../../spikes/photosnap-validation/).

## Setup

- **22 photos of Indian meals** from Wikimedia Commons (freely licensed; provenance in
  `images_manifest.csv`). Difficulty spread on purpose: clean single dishes, counting tests (3 idli,
  2 bhature, 3 poori), a 12-item restaurant south thali, a **deliberately mislabeled trap**
  (file says `pav-bhaji`, the dish is actually **misal pav**), a nearly-black photo, and an extreme
  close-up with no portion reference.
- **Ground truth:** component-based estimation (count the items, price each against standard Indian
  reference values, sum). See "Honesty caveats" below.
- **Prompt:** [`prompt.py`](../../spikes/photosnap-validation/prompt.py) — ported from Fud AI (MIT),
  re-vocabularised for Indian units (katori / roti / idli / dosa), with count-the-pieces and
  mixed-dish rules.

## Results

| Model | n | kcal median err | kcal mean err | within ±30% | protein med | carb med | fat med |
|---|---|---|---|---|---|---|---|
| **google/gemini-2.5-flash** | 22 | **9%** | 15% | **18/22** | 18% | 11% | 18% |
| google/gemini-2.5-flash-lite | 22 | 30% | 34% | 11/22 | 39% | 21% | 40% |
| openai/gpt-5-mini | 19 | 24% | 27% | 12/19 | 40% | 22% | 50% |
| anthropic/claude-sonnet-5 | 0 | — | — | — | — | — | — |

`claude-sonnet-5` never ran — the test key had ~$0.04 credit, below Sonnet pricing (see "Gaps").
`gpt-5-mini` failed 3 images by burning its token cap on reasoning before emitting JSON.

### What gemini-2.5-flash got right (the encouraging part)

- **The misal-pav trap:** identified **"misal pav"** correctly (flash-lite said "chole bhature",
  gpt-5-mini said "chole with sev topping") — *and* estimated it within 4%. Its Indian-food
  recognition is genuinely stronger, which is exactly what Sakama needs.
- **The 12-item south thali:** 13 items extracted, **16% error** on a 1,350-kcal plate. The hardest
  case in the set passed.
- **The nearly-black samosa photo: 2% error.** Lighting robustness far better than expected.
- Counting: 2 bhature ✓; idli 4-vs-3 and poori 2-vs-3 (both partially occluded stacks) — near misses
  with modest calorie impact.
- Confidence self-reporting is sane: its lowest self-confidence (0.75–0.8) landed on the dark photo
  and the close-up — the images that *are* the hardest.

### The 4 failures, diagnosed

| Image | Err | Diagnosis | Product answer |
|---|---|---|---|
| dosa-masala | −41% | Called it **plain dosa** — the potato filling is hidden inside the roll. Missed ~200 kcal it could not see. | **Occluded fillings are a real failure mode.** The confirm sheet must make "plain vs masala" a one-tap correction; ask-when-ambiguous. |
| aloo-paratha | −32% | Read the **white butter** dollop as **curd** (~180 kcal vs ~30 kcal). | Same class: visually-ambiguous high-fat items. Correction UI + learn from corrections. |
| biryani-veg | +44% | Restaurant bowl, portion ambiguity — and our own ground truth is genuinely uncertain here (a restaurant biryani can be 700+ kcal). | Partly a ground-truth artifact. Portion stepper on the confirm sheet handles it. |
| khichdi | +41% | Extreme close-up filling the frame — **portion is unknowable for anyone**, our reference guess included. | Expected. UI should nudge users toward whole-plate shots; low `meal_confidence` (0.8) already flags it. |

**Pattern:** identification of *visible* dishes is excellent; the errors concentrate in (a) hidden
fillings, (b) ambiguous white dollops, (c) unknowable portions. All three are addressed by the
**confirm-before-log sheet** ([DESIGN.md](../DESIGN.md)) — which is already the core UX — not by a
better model.

## Cost check (validates ADR 0009 freemium math)

gemini-2.5-flash ≈ **$0.002 per photo** (≈1.3K image+prompt tokens in, ~600 out). A free-tier cap of
5 PhotoSnaps/day costs at most ~$0.30/user/month worst-case, typically far less. The freemium
envelope holds.

## Honesty caveats (read before citing these numbers)

1. **Ground truth is reference-based estimation, not lab measurement.** I (the agent) counted
   components in each photo and priced them against standard Indian reference values — the same
   procedure a human nutritionist uses on a photo, and the only kind of "truth" available for photo
   logging anywhere. The numbers measure *agreement with careful component-based estimation*.
2. **Web photos, not user photos.** Wikimedia images skew well-lit and well-plated (we included dark
   and close-up shots deliberately, and they held up). Real kitchen-table photos will be somewhat
   harder. The confirm-sheet UX is the hedge.
3. **The estimator and one candidate share a vendor lineage with the ground-truth author** (Claude).
   Mitigated by: the winning model is Google's, judged against reference values, with a
   vendor-independent runner-up (gpt-5-mini) showing consistent relative ordering.
4. **claude-sonnet-5 unscored** (credit). Worth a later top-up run out of curiosity, but not blocking:
   flash cleared the bar decisively and is ~7× cheaper anyway.

## Decisions this locks

1. **GO — build M0–M3.** The moat premise holds.
2. **v1 PhotoSnap default model: `google/gemini-2.5-flash`** (via the managed gateway, paid tier for
   real users per [ADR 0011](../adr/0011-serverless-ai-gateway.md)).
3. **flash-lite is NOT good enough** to be the free-tier model (30% median). Free tier = same flash
   model, capped count — quality is the product; the cap is the cost control.
4. **Reasoning models (gpt-5-mini) need `max_tokens` headroom** or they burn the cap thinking and
   return nothing — a gateway-config lesson for M3.
5. The confirm sheet must optimize for the three observed failure modes: hidden fillings, ambiguous
   dollops, portion steppers.

## Reproduce

```bash
cd spikes/photosnap-validation
export OPENROUTER_API_KEY=...
python3 fetch_test_images.py   # or supply your own photos
python3 run_spike.py --models "google/gemini-2.5-flash"
python3 score.py
```
