#!/usr/bin/env bash
# Branch protection as CODE, not clicks. (Pattern from ModelBeat.)
# Applies .github/rulesets/main.json to the repo. Re-runnable.
#
#   ./.github/scripts/apply-branch-protection.sh [owner/repo]
#
# Requires: gh, authenticated as an account with admin on the repo.
#
# ⚠️  PLAN LIMIT: repository rulesets require **GitHub Pro** or a **public** repo.
#     On a free PRIVATE repo the API returns 403:
#       "Upgrade to GitHub Pro or make this repository public to enable this feature."
#     Sakama is currently free + private, so this script reports that and exits 0.
#     Until the plan changes, main is guarded by convention plus two real gates:
#       - .claude/hooks/block-push-to-main.py (blocks pushes to main from Claude Code)
#       - the CI checks, which still run on every PR
set -euo pipefail

REPO="${1:-aman1195/Sakama}"
RULESET=".github/rulesets/main.json"
NAME=$(python3 -c "import json;print(json.load(open('$RULESET'))['name'])")

echo "Applying ruleset '$NAME' to $REPO ..."

# Probe first — rulesets are plan-gated on private repos, and the old version of
# this script pasted the 403 error body straight into the next request URL.
if ! PROBE=$(gh api "repos/$REPO/rulesets" 2>&1); then
  if echo "$PROBE" | grep -q "Upgrade to GitHub Pro"; then
    cat <<'MSG'
⚠️  Branch protection NOT applied — GitHub plan limit.

    Repository rulesets require GitHub Pro, or a public repo.
    This repo is free + private, so the API returns 403.

    Options:
      1. Upgrade to GitHub Pro, then re-run this script
      2. Make the repo public (read docs/research/ first — the evals name individuals)
      3. Do nothing. main is still guarded by:
           - .claude/hooks/block-push-to-main.py
           - required CI checks on every PR (licence gate, docs, pr-hygiene)
MSG
    exit 0
  fi
  echo "❌ Unexpected error listing rulesets:" >&2
  echo "$PROBE" >&2
  exit 1
fi

EXISTING=$(echo "$PROBE" | python3 -c "
import json, sys
try:
    rs = json.load(sys.stdin)
except Exception:
    rs = []
print(next((str(r['id']) for r in rs if r.get('name') == '$NAME'), ''))
")

if [ -n "$EXISTING" ]; then
  gh api -X PUT "repos/$REPO/rulesets/$EXISTING" --input "$RULESET" >/dev/null
  echo "✅ updated existing ruleset ($EXISTING)"
else
  gh api -X POST "repos/$REPO/rulesets" --input "$RULESET" >/dev/null
  echo "✅ created ruleset"
fi
echo "main now requires: PR + green checks; no force-push, no deletion."
