#!/usr/bin/env bash
#
# verify-rls.sh — prove row-level security actually holds, against a live project.
#
# WHY THIS EXISTS. RLS is the primary data-isolation boundary for a health app
# (CLAUDE.md rule 2), and until now nothing tested it. The migrations declare
# policies; a declaration is not a proof. On 2026-08-28 a migration shipped four
# RLS policies that could not be verified at all: `supabase db execute` does not
# exist in CLI 2.39.2, and reading a service-role key to check by hand is exactly
# the credential you should not be handling casually.
#
# This talks to PostgREST the way the app does — anon key plus a real user JWT —
# so it tests the boundary as a client experiences it, not as the schema claims
# it. A policy that looks right in SQL and is not enforced fails here.
#
# WHAT IT PROVES
#   1. Anonymous callers are denied on every user table. No JWT, no rows.
#   2. An authenticated user reads only their own rows.
#   3. An authenticated user CANNOT write a row owned by someone else.
#      This is the classic bypass: policies often gate SELECT correctly and
#      leave INSERT's WITH CHECK open, so anyone can forge a row into another
#      person's diary.
#   4. With a second account (optional), neither user can see the other's rows.
#
# USAGE
#   SAKAMA_URL=https://<ref>.supabase.co \
#   SAKAMA_ANON_KEY=<anon key> \
#   SAKAMA_TEST_EMAIL=aman@sakama.test \
#   SAKAMA_TEST_PASSWORD=<password> \
#     bash supabase/verify-rls.sh
#
#   Optionally add SAKAMA_TEST2_EMAIL / SAKAMA_TEST2_PASSWORD to enable the
#   cross-user checks, which are the strongest ones here.
#
#   With no env set it reads app/.env for URL and anon key, so the common case
#   is just the two credential variables.
#
# SAFE TO RUN against the real project. It reads, and its only write is one that
# MUST fail; if that write ever succeeds the script deletes it and fails loudly.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- config -----------------------------------------------------------------

URL="${SAKAMA_URL:-}"
ANON="${SAKAMA_ANON_KEY:-}"

if [ -z "$URL" ] || [ -z "$ANON" ]; then
  ENV_FILE="$ROOT/app/.env"
  if [ -f "$ENV_FILE" ]; then
    [ -z "$URL" ] && URL="$(grep -E '^SUPABASE_URL=' "$ENV_FILE" | cut -d= -f2- | tr -d '"' | tr -d "'")"
    [ -z "$ANON" ] && ANON="$(grep -E '^SUPABASE_ANON_KEY=' "$ENV_FILE" | cut -d= -f2- | tr -d '"' | tr -d "'")"
  fi
fi

EMAIL="${SAKAMA_TEST_EMAIL:-}"
PASSWORD="${SAKAMA_TEST_PASSWORD:-}"

missing=0
for pair in "SAKAMA_URL:$URL" "SAKAMA_ANON_KEY:$ANON" \
            "SAKAMA_TEST_EMAIL:$EMAIL" "SAKAMA_TEST_PASSWORD:$PASSWORD"; do
  name="${pair%%:*}"; value="${pair#*:}"
  if [ -z "$value" ]; then
    echo "missing: $name" >&2
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  echo >&2
  echo "URL and anon key fall back to app/.env; the two credentials do not." >&2
  exit 2
fi

# Every table whose rows belong to one user. Keep in step with the Drift schema:
# a synced table missing from this list is a table nobody proves is private.
TABLES=(food_logs profiles water_logs weight_logs user_plans user_foods workouts)

PASS=0; FAIL=0; SKIP=0

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
# Neither pass nor fail. A check that had nothing to look at proves nothing, and
# counting it as a pass is how a suite reports green on an empty database.
skip() { SKIP=$((SKIP+1)); printf '  \033[33mVOID\033[0m  %s\n' "$1"; }

# --- helpers ----------------------------------------------------------------

# login <email> <password> -> prints "<jwt> <user_id>", or empty on failure.
#
# NOT named UID. `UID` is readonly in bash — it holds the shell's own numeric
# user id — so `read -r JWT UID` fails silently and leaves 501 behind. This
# script compared every row's owner against 501 and reported four tables as
# leaking data. They were not. A security check that cries wolf is worse than
# none, because the next real failure gets waved through.
login() {
  curl -sS -X POST "$URL/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON" -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" 2>/dev/null |
    python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    t=d.get("access_token"); u=(d.get("user") or {}).get("id")
    print(f"{t} {u}" if t and u else "")
except Exception:
    print("")'
}

# status <method> <path> [jwt] [body] -> HTTP status code
status() {
  local method="$1" path="$2" jwt="${3:-}" body="${4:-}"
  local args=(-sS -o /dev/null -w '%{http_code}' -X "$method"
              "$URL/rest/v1/$path" -H "apikey: $ANON")
  [ -n "$jwt" ] && args+=(-H "Authorization: Bearer $jwt")
  if [ -n "$body" ]; then
    args+=(-H "Content-Type: application/json" -H "Prefer: return=representation" -d "$body")
  fi
  curl "${args[@]}" 2>/dev/null
}

# rows <path> <jwt> -> response body
rows() {
  curl -sS "$URL/rest/v1/$1" -H "apikey: $ANON" \
    -H "Authorization: Bearer $2" 2>/dev/null
}

# --- 0. sign in -------------------------------------------------------------

echo
echo "verify-rls — ${URL#https://}"
echo

read -r JWT USER_ID <<<"$(login "$EMAIL" "$PASSWORD")"
if [ -z "${JWT:-}" ]; then
  echo "could not sign in as $EMAIL — check the credentials" >&2
  exit 2
fi
echo "signed in as $EMAIL (${USER_ID:0:8}…)"
echo

JWT2=""; USER_ID2=""
if [ -n "${SAKAMA_TEST2_EMAIL:-}" ] && [ -n "${SAKAMA_TEST2_PASSWORD:-}" ]; then
  read -r JWT2 USER_ID2 <<<"$(login "$SAKAMA_TEST2_EMAIL" "$SAKAMA_TEST2_PASSWORD")"
  if [ -z "${JWT2:-}" ]; then
    echo "second account configured but sign-in failed — cross-user checks skipped" >&2
    JWT2=""
  fi
fi

# --- 1. anonymous is denied everywhere --------------------------------------

echo "1. anonymous callers"
for t in "${TABLES[@]}"; do
  code="$(status GET "$t?select=id&limit=1" "")"
  # 200 with an empty array is still a FAIL in spirit but not in fact: RLS
  # returning zero rows to anon is the correct PostgREST behaviour when a
  # SELECT policy exists and matches nothing. What must never happen is data.
  if [ "$code" = "401" ] || [ "$code" = "403" ]; then
    ok "$t denied to anon ($code)"
  elif [ "$code" = "200" ]; then
    body="$(curl -sS "$URL/rest/v1/$t?select=id&limit=1" -H "apikey: $ANON" 2>/dev/null)"
    if [ "$body" = "[]" ]; then
      ok "$t returns no rows to anon"
    else
      bad "$t LEAKS ROWS TO ANONYMOUS CALLERS: ${body:0:120}"
    fi
  else
    bad "$t unexpected status for anon: $code"
  fi
done
echo

# --- 2. an authenticated user sees only their own rows ----------------------

echo "2. authenticated reads are scoped to the caller"
for t in "${TABLES[@]}"; do
  body="$(rows "$t?select=user_id&limit=200" "$JWT")"
  if [ "${body:0:1}" != "[" ]; then
    bad "$t did not return a list: ${body:0:120}"
    continue
  fi
  read -r total foreign <<<"$(printf '%s' "$body" | python3 -c 'import sys,json
try:
    rows=json.load(sys.stdin)
except Exception:
    print("PARSE PARSE"); raise SystemExit
me=sys.argv[1]
bad=[r for r in rows if r.get("user_id") not in (me, None)]
print(len(rows), len(bad))' "$USER_ID")"
  if [ "$total" = "PARSE" ]; then
    bad "$t response was not JSON"
  elif [ "$total" = "0" ]; then
    # An empty table cannot demonstrate isolation. Reporting this as a pass is
    # how a suite goes green against a database with nothing in it, which is
    # exactly the state a fresh CI project is in.
    skip "$t is empty — nothing to isolate, so nothing proved"
  elif [ "$foreign" = "0" ]; then
    ok "$t: all $total rows belong to the caller"
  else
    bad "$t RETURNED $foreign OF $total ROWS BELONGING TO SOMEONE ELSE"
  fi
done
echo

# --- 3. a user cannot forge a row into someone else's diary -----------------
#
# The strongest single-account check. Policies commonly gate SELECT correctly
# and leave INSERT's WITH CHECK open, which lets anyone write into another
# person's data — worse than reading it, because the victim then sees food they
# never ate and a target computed from it.

echo "3. writing another user's row"
FORGED_ID="rls-probe-$(date +%s)"
FOREIGN_UID="00000000-0000-4000-8000-000000000000"
payload="{\"id\":\"$FORGED_ID\",\"user_id\":\"$FOREIGN_UID\",\"date\":\"2026-01-01\",\"meal\":\"lunch\",\"name\":\"rls probe\",\"energy_kcal\":1,\"created_at\":1,\"updated_at\":1}"
code="$(status POST "food_logs" "$JWT" "$payload")"

if [ "$code" = "401" ] || [ "$code" = "403" ]; then
  ok "food_logs insert with a foreign user_id refused ($code)"
elif [ "$code" = "201" ] || [ "$code" = "200" ]; then
  bad "food_logs ACCEPTED A ROW OWNED BY ANOTHER USER — WITH CHECK is not enforcing"
  # Do not leave the probe behind. It is a real row in a real table.
  del="$(status DELETE "food_logs?id=eq.$FORGED_ID" "$JWT")"
  echo "        (cleanup delete returned $del; verify manually if not 204)"
else
  bad "food_logs foreign insert returned $code — expected a refusal"
fi
echo

# --- 4. cross-user isolation (needs a second account) -----------------------

if [ -n "$JWT2" ]; then
  echo "4. cross-user isolation"
  for t in food_logs weight_logs workouts; do
    body="$(rows "$t?select=user_id&limit=200" "$JWT2")"
    seen="$(printf '%s' "$body" | python3 -c 'import sys,json
try:
    rows=json.load(sys.stdin)
except Exception:
    print("PARSE"); raise SystemExit
other=sys.argv[1]
print(sum(1 for r in rows if r.get("user_id")==other))' "$USER_ID")"
    if [ "$seen" = "0" ]; then
      ok "$t: second user cannot see the first user's rows"
    else
      bad "$t: SECOND USER SEES $seen OF THE FIRST USER'S ROWS"
    fi
  done
  echo
else
  echo "4. cross-user isolation — SKIPPED (set SAKAMA_TEST2_EMAIL/PASSWORD)"
  echo "   This is the strongest check here. One account cannot prove two are isolated."
  echo
fi

# --- result -----------------------------------------------------------------

if [ "$SKIP" -gt 0 ]; then
  echo "$PASS passed, $FAIL failed, $SKIP void (no data to check)"
else
  echo "$PASS passed, $FAIL failed"
fi
[ "$FAIL" -eq 0 ] || {
  echo
  echo "RLS is the primary data-isolation boundary for a health app." >&2
  echo "A failure here means one person's health data is reachable by another." >&2
  exit 1
}
