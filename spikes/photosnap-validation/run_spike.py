#!/usr/bin/env python3
"""PhotoSnap validation spike runner — stdlib only, no pip install.

Sends each meal photo + the Indian-food prompt to one or more vision models and saves the
structured JSON responses. No app, no Flutter. This is Phase 0 (ADR 0013): prove a VLM can
estimate Indian-meal macros usefully BEFORE building anything.

USAGE
  1. Put meal photos in ./images/  (jpg/png). Name them meaningfully, e.g. thali-01.jpg
  2. Get an API key (either works):
       export OPENROUTER_API_KEY=sk-or-...      # one key -> Gemini, Claude, GPT (recommended)
       export GEMINI_API_KEY=...                # direct Google, free tier OK for a spike
  3. python3 run_spike.py                       # runs every image through the default models
     python3 run_spike.py --models google/gemini-2.5-flash,anthropic/claude-sonnet-4.6
  4. Results -> ./results/<model>/<image>.json   then:  python3 score.py

NOTE ON PRIVACY: free provider tiers train on submitted data (ADR 0011). That is FINE here —
these are your own test photos, not user health data. Never point this at real user data on a free tier.
"""
import argparse
import base64
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from prompt import PROMPT  # noqa: E402

HERE = Path(__file__).parent
IMAGES = HERE / "images"
RESULTS = HERE / "results"

# Default model set: cheap-but-capable vision models across three providers, via OpenRouter.
DEFAULT_OPENROUTER_MODELS = [
    "google/gemini-2.5-flash",
    "anthropic/claude-sonnet-4.6",
    "openai/gpt-5-mini",
]


def _image_data_url(path: Path) -> str:
    mime = mimetypes.guess_type(str(path))[0] or "image/jpeg"
    b64 = base64.b64encode(path.read_bytes()).decode()
    return f"data:{mime};base64,{b64}"


def _post(url: str, headers: dict, payload: dict, timeout: int = 120) -> dict:
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(), headers=headers, method="POST"
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def call_openrouter(model: str, image: Path, api_key: str) -> str:
    body = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": PROMPT},
                    {"type": "image_url", "image_url": {"url": _image_data_url(image)}},
                ],
            }
        ],
        "temperature": 0.2,
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://sakama.app",
        "X-Title": "Sakama PhotoSnap spike",
    }
    resp = _post("https://openrouter.ai/api/v1/chat/completions", headers, body)
    return resp["choices"][0]["message"]["content"]


def call_gemini(model: str, image: Path, api_key: str) -> str:
    mime = mimetypes.guess_type(str(image))[0] or "image/jpeg"
    b64 = base64.b64encode(image.read_bytes()).decode()
    body = {
        "contents": [
            {
                "parts": [
                    {"text": PROMPT},
                    {"inline_data": {"mime_type": mime, "data": b64}},
                ]
            }
        ],
        "generationConfig": {"temperature": 0.2},
    }
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
    resp = _post(url, {"Content-Type": "application/json"}, body)
    return resp["candidates"][0]["content"]["parts"][0]["text"]


def extract_json(text: str) -> dict:
    """Models sometimes wrap JSON in ```json fences or add stray prose. Recover the object."""
    t = text.strip()
    if t.startswith("```"):
        t = t.split("```", 2)[1]
        if t.startswith("json"):
            t = t[4:]
    start, end = t.find("{"), t.rfind("}")
    if start != -1 and end != -1:
        t = t[start : end + 1]
    return json.loads(t)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", help="comma-separated model ids (OpenRouter slugs, or gemini-* for direct)")
    ap.add_argument("--provider", choices=["openrouter", "gemini"], help="force a provider")
    args = ap.parse_args()

    or_key = os.environ.get("OPENROUTER_API_KEY")
    gem_key = os.environ.get("GEMINI_API_KEY")
    if not or_key and not gem_key:
        print("ERROR: set OPENROUTER_API_KEY (recommended) or GEMINI_API_KEY. See the docstring.")
        return 1

    provider = args.provider or ("openrouter" if or_key else "gemini")
    if args.models:
        models = [m.strip() for m in args.models.split(",")]
    elif provider == "openrouter":
        models = DEFAULT_OPENROUTER_MODELS
    else:
        models = ["gemini-2.5-flash"]

    images = sorted(p for p in IMAGES.glob("*") if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"})
    if not images:
        print(f"ERROR: no images in {IMAGES}/ — add meal photos (jpg/png) first.")
        return 1

    print(f"provider={provider}  models={models}  images={len(images)}\n")
    for model in models:
        safe = model.replace("/", "_")
        out = RESULTS / safe
        out.mkdir(parents=True, exist_ok=True)
        for img in images:
            dest = out / f"{img.stem}.json"
            if dest.exists():
                print(f"  skip {model}  {img.name} (already done)")
                continue
            try:
                raw = (call_openrouter if provider == "openrouter" else call_gemini)(model, img, or_key or gem_key)
                parsed = extract_json(raw)
                dest.write_text(json.dumps({"model": model, "image": img.name, "result": parsed}, indent=2))
                n = len(parsed.get("items", []))
                print(f"  ok   {model}  {img.name}  ({n} items, meal_conf={parsed.get('meal_confidence')})")
            except urllib.error.HTTPError as e:
                print(f"  HTTP {e.code} {model} {img.name}: {e.read().decode()[:200]}")
            except Exception as e:  # noqa: BLE001
                print(f"  FAIL {model} {img.name}: {type(e).__name__}: {e}")
            time.sleep(1)  # gentle on free-tier rate limits
    print("\nDone. Now: python3 score.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
