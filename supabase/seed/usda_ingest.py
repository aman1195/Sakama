#!/usr/bin/env python3
"""Ingest USDA FoodData Central SR Legacy into Sakama's food seed asset.

USDA FoodData Central is PUBLIC DOMAIN (CC0) — no attribution or share-alike
obligation (unlike OFF ODbL). Every emitted row is tagged
source='usda_fdc', licence='CC0'. Re-runnable as USDA publishes updates.

Usage:
    # 1. Download the bulk dataset (public, no API key):
    #    https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip
    # 2. unzip, then:
    python3 usda_ingest.py <path-to-sr_legacy.json> <out.json>

Output: a compact JSON array with short keys (source/licence/confidence are
constant for USDA and set by the app loader, so they are NOT repeated per row):
    i  id (usda-<fdcId>)   n name        g foodGroup
    e  energy kcal/100g    p protein g   c carb g   f fat g   fb fiber g
    sl default serving label   sg default serving grams   r FDC:<fdcId>
"""
import json
import sys

# USDA nutrient numbers (per 100 g in SR Legacy).
N_ENERGY_KCAL = "208"
N_PROTEIN = "203"
N_CARB = "205"
N_FAT = "204"
N_FIBER = "291"


def nutrient_map(food):
    out = {}
    for fn in food.get("foodNutrients", []):
        num = fn.get("nutrient", {}).get("number")
        amt = fn.get("amount")
        if num is not None and amt is not None and num not in out:
            out[num] = amt
    return out


def default_serving(food):
    portions = food.get("foodPortions") or []
    if not portions:
        return None, None
    p = portions[0]
    grams = p.get("gramWeight")
    if not grams:
        return None, None
    label = (p.get("portionDescription")
             or p.get("modifier")
             or f"{grams:g} g")
    return label, grams


def convert(food):
    n = nutrient_map(food)
    kcal = n.get(N_ENERGY_KCAL)
    if kcal is None or kcal <= 0:
        return None  # no usable energy — skip
    label, grams = default_serving(food)
    row = {
        "i": f"usda-{food['fdcId']}",
        "n": food.get("description", "").strip(),
        "g": (food.get("foodCategory") or {}).get("description"),
        "e": round(kcal, 1),
        "p": round(n.get(N_PROTEIN, 0.0), 2),
        "c": round(n.get(N_CARB, 0.0), 2),
        "f": round(n.get(N_FAT, 0.0), 2),
        "fb": round(n[N_FIBER], 2) if N_FIBER in n else None,
        "sl": label,
        "sg": round(grams, 1) if grams else None,
        "r": f"FDC:{food['fdcId']}",
    }
    return row


def main():
    src, out = sys.argv[1], sys.argv[2]
    data = json.load(open(src))
    foods = data["SRLegacyFoods"]
    rows = [r for r in (convert(f) for f in foods) if r and r["n"]]
    rows.sort(key=lambda r: r["n"].lower())
    json.dump(rows, open(out, "w"), separators=(",", ":"), ensure_ascii=False)
    print(f"in={len(foods)} out={len(rows)} skipped={len(foods)-len(rows)}")


if __name__ == "__main__":
    main()
