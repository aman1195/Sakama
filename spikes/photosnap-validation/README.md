# Phase 0 — PhotoSnap Validation Spike

> **The most important day of the project.** Before writing any app code, prove that a vision model can
> estimate an Indian meal's macros *usefully*. If it can, we build with confidence. If it cannot, we learn
> it now — in a day — and pivot the wedge instead of discovering it after a month.
> Decision: [ADR 0013](../../docs/adr/0013-validate-photosnap-before-build.md).

No app. No Flutter. No installs beyond `python3` (already present) and one API key.

## What "good enough" means

A logging user sees **calories** first. Target: **most meals within ±30%** on calories, with **sensible
portions** (the model counts 2 rotis as 2, a katori of dal as ~150 g, etc.). Macros are secondary signal.

- **GO** → a clear majority of meals pass the calorie band with believable portions. Proceed to M0; the
  spike also picks the v1 model.
- **NO-GO** → estimates are wildly off or portions are nonsense. Pivot: barcode/search-first wedge, or the
  heavier two-stage (segmentation + VLM) pipeline. Better to know now.

## Steps

### 1. Collect photos (the real work)
Put **20–30 photos of real Indian meals** in `images/` (jpg/png). Shoot what you actually eat — thalis,
tiffin (idli/dosa/vada), street food, a mixed biryani, a simple dal-chawal. Variety matters more than
count. Top-down, whole plate in frame, decent light.

### 2. Record ground truth
For each photo, add a row to `ground_truth.csv` with your **best-estimate** true macros. It does not need
to be lab-perfect — it is the reference the estimates are judged against. Use the `image` column = the
file name. Delete the example row.

> Tip for ground truth: estimate each component (1 katori dal ≈ 180 kcal, 1 phulka ≈ 100 kcal, etc.) and
> sum. Consistency matters more than precision — the spike measures *relative* error.

### 3. Get an API key (either works)
```bash
export OPENROUTER_API_KEY=sk-or-...    # RECOMMENDED: one key → Gemini, Claude, GPT (get at openrouter.ai)
# or
export GEMINI_API_KEY=...              # direct Google; free tier is fine for a spike
```
Free tiers are fine here — these are **your own test photos, not user health data** (the training-on-data
concern in [ADR 0011](../../docs/adr/0011-serverless-ai-gateway.md) only applies to real users).

### 4. Run
```bash
cd spikes/photosnap-validation
python3 run_spike.py                    # default: gemini-2.5-flash, claude-sonnet-4.6, gpt-5-mini
python3 score.py                        # per-model error + pass rate
python3 score.py --band 25              # stricter band
```
Re-running skips images already done, so it is cheap to iterate.

### 5. Decide and record
Write a short findings note to `docs/research/photosnap-spike-findings.md`:
- the table from `score.py`, the model chosen, the error band achieved;
- **failure cases** — which dishes it got wrong and how (this shapes the confidence UI and the
  correction flow in M3);
- the **GO / NO-GO** call and why.

## Files
| File | What |
|---|---|
| `prompt.py` | The Indian-food analysis prompt (ported from Fud AI, re-vocabularised for katori/roti/idli) |
| `run_spike.py` | Sends each photo + prompt to each model; saves JSON to `results/<model>/<image>.json` |
| `ground_truth.csv` | Your meals + best-estimate true macros (you fill this in) |
| `score.py` | Compares estimates vs. truth; median/mean % error + pass rate per model |
| `images/` | Your test photos (gitignored — not committed) |
| `results/` | Model outputs (gitignored) |

## What is NOT tested here (on purpose)
Latency, cost-at-scale, the confirm-sheet UX, and multi-turn correction — those are M3. This spike answers
exactly one question: **are the numbers useful enough to build on?**
