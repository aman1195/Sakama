#!/usr/bin/env bash
# Branch protection as CODE, not clicks. (Pattern from ModelBeat.)
# Applies .github/rulesets/main.json to the repo. Re-runnable.
#
#   ./.github/scripts/apply-branch-protection.sh [owner/repo]
#
# Requires: gh, authenticated as an account with admin on the repo.
set -euo pipefail
REPO="${1:-aman1195/Sakama}"
RULESET=".github/rulesets/main.json"
NAME=$(python3 -c "import json;print(json.load(open('$RULESET'))['name'])")

echo "Applying ruleset '$NAME' to $REPO ..."
EXISTING=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name==\"$NAME\") | .id" 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  gh api -X PUT "repos/$REPO/rulesets/$EXISTING" --input "$RULESET" >/dev/null
  echo "✅ updated existing ruleset ($EXISTING)"
else
  gh api -X POST "repos/$REPO/rulesets" --input "$RULESET" >/dev/null
  echo "✅ created ruleset"
fi
echo "main now requires: PR + green licence-gate/docs/pr-hygiene checks; no force-push, no deletion."
