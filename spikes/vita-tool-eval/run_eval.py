"""Tool-selection eval (ADR 0016 decision 7): does a model call the right tool
at the right time, and — harder — REFRAIN when the user is asking, not
reporting?

    export MODELBEAT_API_KEY=mb_live_...     # ModelBeat text models
    export OPENROUTER_API_KEY=sk-or-...      # the gemini baseline
    python3 run_eval.py --models deepseek-v3.2,qwen3-32b

The PERSONA is read from supabase/functions/vita/index.ts at run time so the
eval can never drift from the deployed prompt. TOOLS is redeclared here (the
TS array is not valid JSON); if you change the schema there, change it here.

Scoring per fixture: correct tool (or correct silence), plus arg spot-checks.
A model that logs when asked a question fails the fixture even if its answer
text is lovely — that is the #97 regression, and it is the main thing this
harness exists to catch. ModelBeat responses are rejected unless
resolved_model_used matches the pin (silent-fallback guard, API.md 4.3).
"""
import argparse, json, os, sys, time, urllib.request
from pathlib import Path

HERE = Path(__file__).parent
ROOT = HERE.parent.parent
MODELBEAT_URL = "https://api.beta.modelbeat.ai/v1/chat/completions"
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

TOOLS = [
    {"type": "function", "function": {"name": "log_food",
        "description": "Propose logging a food the user says they ate.",
        "parameters": {"type": "object", "properties": {
            "meal": {"type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"]},
            "name": {"type": "string"}, "energy_kcal": {"type": "number"},
            "protein_g": {"type": "number"}, "carb_g": {"type": "number"},
            "fat_g": {"type": "number"}, "grams": {"type": "number"}},
            "required": ["meal", "name", "energy_kcal"]}}},
    {"type": "function", "function": {"name": "log_water",
        "description": "Propose logging water the user says they drank.",
        "parameters": {"type": "object", "properties": {"amount_ml": {"type": "number"}},
            "required": ["amount_ml"]}}},
    {"type": "function", "function": {"name": "log_weight",
        "description": "Propose logging the user's stated body weight.",
        "parameters": {"type": "object", "properties": {"weight_kg": {"type": "number"}},
            "required": ["weight_kg"]}}},
]


def persona() -> str:
    src = (ROOT / "supabase/functions/vita/index.ts").read_text()
    parts = src.split("const PERSONA =\n  `")
    # Fails LOUD if the TS declaration is reformatted — a confusing IndexError
    # two lines later would send the next person hunting in the wrong file.
    assert len(parts) == 2, "PERSONA declaration in vita/index.ts changed shape; update this split"
    return parts[1].split("`;")[0]


def call(model: str, message: str, context: str, key: str, url: str) -> dict:
    body = json.dumps({
        "model": model,
        "max_tokens": 500,
        "messages": [
            {"role": "system", "content": f"{persona()}\n\n--- The user's data right now ---\n{context}"},
            {"role": "user", "content": message},
        ],
        "tools": TOOLS,
    }).encode()
    req = urllib.request.Request(url, data=body, headers={
        "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=120).read())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", required=True)
    args = ap.parse_args()
    fx = json.loads((HERE / "fixtures.json").read_text())
    mb_key, or_key = os.environ.get("MODELBEAT_API_KEY"), os.environ.get("OPENROUTER_API_KEY")

    results = {}
    for model in args.models.split(","):
        model = model.strip()
        use_mb = not model.startswith(("google/", "openai/", "anthropic/"))
        key, url = (mb_key, MODELBEAT_URL) if use_mb else (or_key, OPENROUTER_URL)
        if not key:
            print(f"SKIP {model}: no key for its gateway"); continue
        rows, out = [], HERE / "results" / f"{model.replace('/', '_')}.json"
        out.parent.mkdir(exist_ok=True)
        for f in fx["fixtures"]:
            try:
                d = call(model, f["message"], fx["context"], key, url)
                served = (d.get("extra_fields") or {}).get("resolved_model_used")
                norm = lambda s: "".join(c for c in s.lower() if c.isalnum())
                if use_mb and (not isinstance(served, str) or norm(model) not in norm(served)):
                    rows.append({"id": f["id"], "verdict": "GATEWAY_SWAP", "served": served}); continue
                msg = d["choices"][0]["message"]
                calls = msg.get("tool_calls") or []
                tool = calls[0]["function"]["name"] if calls else None
                targs = json.loads(calls[0]["function"].get("arguments") or "{}") if calls else {}
                ok = tool == f["expected_tool"]
                why = ""
                if ok and f.get("args_check"):
                    for k, v in f["args_check"].items():
                        if targs.get(k) != v:
                            ok, why = False, f"arg {k}={targs.get(k)!r} wanted {v!r}"; break
                if not ok and not why:
                    why = f"called {tool}, expected {f['expected_tool']}"
                rows.append({"id": f["id"], "verdict": "PASS" if ok else "FAIL",
                             "why": why, "tool": tool, "args": targs,
                             "reply": (msg.get("content") or "")[:160]})
            except Exception as e:  # noqa: BLE001
                rows.append({"id": f["id"], "verdict": "ERROR", "why": f"{type(e).__name__}: {e}"})
            time.sleep(0.5)
        out.write_text(json.dumps({
            # Point-in-time evidence must say WHEN: these age silently against
            # the live PERSONA otherwise (review of #114).
            "run_date": time.strftime("%Y-%m-%d"),
            "persona_source": "supabase/functions/vita/index.ts (read at run time)",
            "rows": rows,
        }, indent=2))
        results[model] = rows

    print(f"\n{'model':28} {'pass':>5} {'fail':>5} {'err':>4}   failures")
    for m, rows in results.items():
        p = sum(r["verdict"] == "PASS" for r in rows)
        fl = [r["id"] for r in rows if r["verdict"] == "FAIL"]
        e = sum(r["verdict"] in ("ERROR", "GATEWAY_SWAP") for r in rows)
        print(f"{m:28} {p:>5} {len(fl):>5} {e:>4}   {', '.join(fl[:4])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
