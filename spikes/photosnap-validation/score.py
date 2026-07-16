#!/usr/bin/env python3
"""Score the spike: compare each model's estimate against ground_truth.csv.

Reads results/<model>/<image>.json (from run_spike.py) and ground_truth.csv, then reports,
per model: median & mean absolute % error on calories and each macro, and the pass rate
against the ±30% "useful" band (ADR 0013). Calories are the headline metric — that is what a
logging user actually sees.

  python3 score.py                 # table to stdout
  python3 score.py --band 25       # use a stricter ±25% band

Go / no-go (ADR 0013): a model is a GO if it hits the calorie band on a clear majority of
meals with sensible portions. This script gives the numbers; the human makes the call and
writes findings to docs/research/.
"""
import argparse
import csv
import json
import statistics
from pathlib import Path

HERE = Path(__file__).parent
RESULTS = HERE / "results"
GT = HERE / "ground_truth.csv"


def load_truth() -> dict:
    truth = {}
    with open(GT) as f:
        for row in csv.DictReader(f):
            if row["image"].startswith("thali-01") and "example row" in row.get("notes", ""):
                continue  # skip the template example
            truth[row["image"]] = row
    return truth


def est_totals(result: dict) -> dict:
    """Sum a model's per-item estimates into meal totals."""
    t = {"kcal": 0.0, "protein_g": 0.0, "carb_g": 0.0, "fat_g": 0.0}
    for it in result.get("items", []):
        t["kcal"] += float(it.get("energy_kcal") or 0)
        m = it.get("macros") or {}
        t["protein_g"] += float(m.get("protein_g") or 0)
        t["carb_g"] += float(m.get("carb_g") or 0)
        t["fat_g"] += float(m.get("fat_g") or 0)
    return t


def pct_err(est: float, true: float) -> float | None:
    if true <= 0:
        return None
    return abs(est - true) / true * 100.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--band", type=float, default=30.0, help="pass band in %% (default 30)")
    args = ap.parse_args()

    truth = load_truth()
    if not truth:
        print("No real rows in ground_truth.csv yet — replace the example row with your meals.")
        return 1
    if not RESULTS.exists():
        print("No results/ yet — run: python3 run_spike.py")
        return 1

    print(f"Ground-truth meals: {len(truth)}   pass band: ±{args.band:.0f}% on calories\n")
    header = f"{'model':38} {'n':>3} {'kcal med%':>9} {'kcal mean%':>10} {'PASS':>6} {'prot%':>6} {'carb%':>6} {'fat%':>6}"
    print(header)
    print("-" * len(header))

    for model_dir in sorted(RESULTS.iterdir()):
        if not model_dir.is_dir():
            continue
        kcal_errs, prot_errs, carb_errs, fat_errs, passes, n = [], [], [], [], 0, 0
        for jf in model_dir.glob("*.json"):
            img = jf.stem
            match = next((k for k in truth if Path(k).stem == img), None)
            if not match:
                continue
            gt = truth[match]
            est = est_totals(json.loads(jf.read_text()).get("result", {}))
            n += 1
            ke = pct_err(est["kcal"], float(gt["true_kcal"]))
            if ke is not None:
                kcal_errs.append(ke)
                if ke <= args.band:
                    passes += 1
            for key, col, bucket in [
                ("protein_g", "true_protein_g", prot_errs),
                ("carb_g", "true_carb_g", carb_errs),
                ("fat_g", "true_fat_g", fat_errs),
            ]:
                e = pct_err(est[key], float(gt[col]))
                if e is not None:
                    bucket.append(e)

        if n == 0:
            continue
        med = lambda xs: f"{statistics.median(xs):.0f}" if xs else "-"
        mean = lambda xs: f"{statistics.mean(xs):.0f}" if xs else "-"
        rate = f"{passes}/{n}"
        print(
            f"{model_dir.name:38} {n:>3} {med(kcal_errs):>9} {mean(kcal_errs):>10} "
            f"{rate:>6} {med(prot_errs):>6} {med(carb_errs):>6} {med(fat_errs):>6}"
        )

    print(
        "\nRead: 'kcal med%' = median calorie error. 'PASS' = meals within the band.\n"
        f"GO (ADR 0013) ≈ a clear majority PASS with sensible portions. Write findings to docs/research/."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
