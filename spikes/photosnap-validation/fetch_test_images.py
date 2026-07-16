#!/usr/bin/env python3
"""Fetch test photos of Indian meals from Wikimedia Commons. Stdlib only.

Why Commons and not Google/Pinterest scrapes: direct file URLs, freely-licensed images
(CC BY / CC BY-SA / PD), and a recordable provenance trail. Images land in images/
(gitignored — never committed); provenance goes to images_manifest.csv (committed).

Usage:  python3 fetch_test_images.py
"""
import csv
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).parent
IMAGES = HERE / "images"
MANIFEST = HERE / "images_manifest.csv"

# One query per meal type — variety over volume (thali + tiffin + street + rice dishes).
QUERIES = [
    ("thali-north", "north indian thali food"),
    ("thali-south", "south indian thali meal"),
    ("dosa-masala", "masala dosa sambar"),
    ("dosa-plain", "plain dosa chutney"),
    ("idli", "idli sambar plate"),
    ("medu-vada", "medu vada sambar"),
    ("uttapam", "uttapam food"),
    ("chole-bhature", "chole bhature"),
    ("biryani-chicken", "chicken biryani plate"),
    ("biryani-veg", "vegetable biryani served"),
    ("dal-chawal", "dal rice indian meal"),
    ("rajma-chawal", "rajma chawal"),
    ("aloo-paratha", "aloo paratha butter"),
    ("vada-pav", "vada pav"),
    ("samosa", "samosa plate food"),
    ("poha", "poha dish"),
    ("upma", "upma food"),
    ("pav-bhaji", "pav bhaji plate"),
    ("paneer-naan", "paneer butter masala naan"),
    ("puri-sabzi", "puri bhaji food"),
    ("khichdi", "khichdi food"),
    ("dhokla", "dhokla plate"),
]

API = "https://commons.wikimedia.org/w/api.php"
UA = {"User-Agent": "Sakama-spike/0.1 (validation research; contact: dev@sakama.app)"}


def search_one(query: str) -> dict | None:
    """First decent bitmap hit for a query: url, title, license."""
    params = {
        "action": "query",
        "generator": "search",
        "gsrsearch": f"filetype:bitmap {query}",
        "gsrnamespace": "6",
        "gsrlimit": "5",
        "prop": "imageinfo",
        "iiprop": "url|extmetadata|size",
        "iiurlwidth": "900",
        "format": "json",
    }
    url = f"{API}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read().decode())
    pages = (data.get("query") or {}).get("pages") or {}
    # prefer landscape-ish, reasonably sized JPEGs
    best = None
    for p in sorted(pages.values(), key=lambda x: x.get("index", 99)):
        ii = (p.get("imageinfo") or [{}])[0]
        u = ii.get("thumburl") or ii.get("url", "")
        if not u.lower().split("?")[0].endswith((".jpg", ".jpeg", ".png")):
            continue
        meta = ii.get("extmetadata") or {}
        lic = (meta.get("LicenseShortName") or {}).get("value", "unknown")
        best = {"title": p.get("title", ""), "url": u, "page": ii.get("descriptionurl", ""), "license": lic}
        break
    return best


def main() -> int:
    IMAGES.mkdir(exist_ok=True)
    rows = []
    for slug, query in QUERIES:
        # extension resolved AFTER the search so PNG sources keep .png (a PNG saved as
        # .jpg makes run_spike declare the wrong mime type for the bytes)
        dest = IMAGES / f"{slug}.jpg"
        if dest.exists() or (IMAGES / f"{slug}.png").exists():
            print(f"  skip {slug} (exists)")
            continue
        try:
            hit = search_one(query)
            if not hit:
                print(f"  none {slug}  ({query})")
                continue
            ext = ".png" if hit["url"].lower().split("?")[0].endswith(".png") else ".jpg"
            dest = IMAGES / f"{slug}{ext}"
            req = urllib.request.Request(hit["url"], headers=UA)
            with urllib.request.urlopen(req, timeout=60) as r:
                dest.write_bytes(r.read())
            kb = dest.stat().st_size // 1024
            rows.append({"image": dest.name, "commons_title": hit["title"], "license": hit["license"],
                         "source_page": hit["page"], "query": query})
            print(f"  ok   {slug}.jpg  {kb} KB  [{hit['license']}]  {hit['title']}")
        except Exception as e:  # noqa: BLE001
            print(f"  FAIL {slug}: {type(e).__name__}: {e}")
        time.sleep(0.5)

    if rows:
        exists = MANIFEST.exists()
        with open(MANIFEST, "a", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["image", "commons_title", "license", "source_page", "query"])
            if not exists:
                w.writeheader()
            w.writerows(rows)
        print(f"\nmanifest: {MANIFEST.name} (+{len(rows)} rows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
