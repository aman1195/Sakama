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

# DERIVED from the migrations, never hand-maintained.
#
# A hardcoded list is the failure this tool exists to prevent, one level up: a
# new user table that somebody forgets to add is silently never RLS-verified,
# and RLS is the boundary you least want a quiet hole in. The first version of
# this script listed seven tables by hand and was already missing `ai_usage`,
# which holds per-user AI spend.
#
# RLS-ENABLED IS NOT THE SAME AS USER-OWNED, and conflating them produces false
# alarms. `app_config` has RLS on and a deliberate `using (true)` public-read
# policy with no user_id at all — anon reading it is correct. A table counts as
# user-owned only if one of its policies references auth.uid().
#
# Two shapes appear in the migrations: a direct `alter table public.X enable row
# level security`, and a `foreach t in array['a','b']` loop driving
# `format('%I', t)`. Both are read here rather than rewriting the migrations to
# suit a grep.
DERIVED="$(python3 - "$ROOT/supabase/migrations" <<'PYEOF'
import os, re, sys
d = sys.argv[1]
sql = "\n".join(
    open(os.path.join(d, f)).read()
    for f in sorted(os.listdir(d)) if f.endswith(".sql")
)

rls = set(re.findall(
    r"alter\s+table\s+public\.([a-z_]+)\s+enable\s+row\s+level\s+security", sql))
for block in re.findall(r"do \$\$(.*?)end \$\$;", sql, re.S):
    if "enable row level security" not in block:
        continue
    for arr in re.findall(r"array\[([^\]]*)\]", block):
        rls.update(re.findall(r"'([a-z_]+)'", arr))

# A policy naming the table AND auth.uid() means the rows belong to someone.
owned = set()
for m in re.finditer(r"create policy[^;]*?on public\.([a-z_]+)[^;]*?;", sql, re.S):
    if "auth.uid()" in m.group(0):
        owned.add(m.group(1))
# The loop form builds policies with format('%I'), so the table name is not
# beside auth.uid(). Credit every table the block drives.
for block in re.findall(r"do \$\$(.*?)end \$\$;", sql, re.S):
    if "create policy" not in block or "auth.uid()" not in block:
        continue
    for arr in re.findall(r"array\[([^\]]*)\]", block):
        owned.update(re.findall(r"'([a-z_]+)'", arr))

print(" ".join(sorted(rls & owned)))
print(" ".join(sorted(rls - owned)))
PYEOF
)"
read -r -a TABLES <<<"$(printf '%s' "$DERIVED" | sed -n 1p)"
read -r -a PUBLIC_TABLES <<<"$(printf '%s' "$DERIVED" | sed -n 2p)"

if [ "${#TABLES[@]}" -eq 0 ]; then
  echo "derived no user-owned tables from the migrations" >&2
  echo "that is itself a failure — either the parser broke or nothing has RLS" >&2
  exit 2
fi
echo "user-owned tables (${#TABLES[@]}): ${TABLES[*]}"
# Named, not silently dropped. A table that lands here by mistake — a policy
# written `using (true)` when it meant auth.uid() — is a data leak, and the only
# way anyone notices is seeing it on this line.
[ "${#PUBLIC_TABLES[@]}" -gt 0 ] &&
  echo "deliberately public (${#PUBLIC_TABLES[@]}): ${PUBLIC_TABLES[*]} — verify each is meant to be"

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
  code="$(status GET "$t?select=*&limit=1" "")"
  # 200 with an empty array is still a FAIL in spirit but not in fact: RLS
  # returning zero rows to anon is the correct PostgREST behaviour when a
  # SELECT policy exists and matches nothing. What must never happen is data.
  if [ "$code" = "401" ] || [ "$code" = "403" ]; then
    ok "$t denied to anon ($code)"
  elif [ "$code" = "200" ]; then
    body="$(curl -sS "$URL/rest/v1/$t?select=*&limit=1" -H "apikey: $ANON" 2>/dev/null)"
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

# A minimal row per table, satisfying NOT NULL so the only thing that can
# refuse it is the policy. `%U` is substituted with a user id that is not ours.
#
# WHY EVERY TABLE. The first version probed food_logs alone, which left an open
# WITH CHECK on any of the other seven invisible — and this is the check most
# worth having, so covering one eighth of the surface was the wrong place to
# economise.
probe_payload() {
  local t="$1" id="$2" other="$3"
  case "$t" in
    food_logs)   echo "{\"id\":\"$id\",\"user_id\":\"$other\",\"date\":\"2026-01-01\",\"meal\":\"lunch\",\"name\":\"rls probe\",\"energy_kcal\":1,\"created_at\":1,\"updated_at\":1}" ;;
    water_logs)  echo "{\"id\":\"$id\",\"user_id\":\"$other\",\"date\":\"2026-01-01\",\"amount_ml\":1,\"created_at\":1,\"updated_at\":1}" ;;
    weight_logs) echo "{\"id\":\"$id\",\"user_id\":\"$other\",\"date\":\"2026-01-01\",\"weight_kg\":70,\"created_at\":1,\"updated_at\":1}" ;;
    workouts)    echo "{\"id\":\"$id\",\"user_id\":\"$other\",\"date\":\"2026-01-01\",\"name\":\"rls probe\",\"kind\":\"other\",\"created_at\":1,\"updated_at\":1}" ;;
    user_plans)  echo "{\"id\":\"$id\",\"user_id\":\"$other\",\"name\":\"rls probe\",\"config\":\"{}\",\"created_at\":1,\"updated_at\":1}" ;;
    user_foods)  echo "{\"id\":\"$id\",\"user_id\":\"$other\",\"name\":\"rls probe\",\"kind\":\"custom\",\"created_at\":1,\"updated_at\":1}" ;;
    meals)       echo "{\"id\":\"$id\",\"user_id\":\"$other\",\"name\":\"rls probe\",\"items\":\"[]\",\"created_at\":1,\"updated_at\":1}" ;;
    ai_usage)    echo "{\"user_id\":\"$other\",\"day\":\"2026-01-01\",\"feature\":\"rls-probe\",\"count\":0}" ;;
    profiles)    echo "{\"id\":\"$id\",\"user_id\":\"$other\",\"dob\":\"1990-01-01\",\"weight_kg\":70,\"height_cm\":170,\"sex\":\"other\",\"activity\":\"moderate\",\"goal\":\"maintain\",\"created_at\":1,\"updated_at\":1}" ;;
    *) echo "" ;;
  esac
}

FOREIGN_UID="00000000-0000-4000-8000-000000000000"
for t in "${TABLES[@]}"; do
  probe_id="rls-probe-$t-$(date +%s)"
  payload="$(probe_payload "$t" "$probe_id" "$FOREIGN_UID")"
  if [ -z "$payload" ]; then
    skip "$t: no probe payload defined — write boundary UNTESTED"
    continue
  fi

  code="$(status POST "$t" "$JWT" "$payload")"
  case "$code" in
    401|403)
      ok "$t: insert with a foreign user_id refused ($code)" ;;
    200|201)
      bad "$t ACCEPTED A ROW OWNED BY ANOTHER USER — WITH CHECK is not enforcing"
      # Never leave the probe behind. It is a real row in a real table.
      del="$(status DELETE "$t?id=eq.$probe_id" "$JWT")"
      echo "        (cleanup delete returned $del — verify by hand if not 204)" ;;
    400|409|422)
      # The payload was rejected before any policy ran, so this proves nothing
      # about RLS. Calling it a pass would be the same vacuous green as an
      # empty table.
      skip "$t: probe rejected as malformed ($code) — write boundary UNPROVEN" ;;
    *)
      bad "$t: foreign insert returned $code — expected a refusal" ;;
  esac
done
echo

# --- 4. cross-user isolation (needs a second account) -----------------------

if [ -n "$JWT2" ]; then
  echo "4. cross-user isolation"
  for t in "${TABLES[@]}"; do
    # Only meaningful if the FIRST user actually has rows in this table. If
    # they have none, "the second user cannot see them" is true of nothing —
    # the same vacuous green an empty table gives in check 2, and reporting it
    # as a pass would overstate what two accounts proved.
    mine="$(printf '%s' "$(rows "$t?select=user_id&limit=200" "$JWT")" |
      python3 -c 'import sys,json
try:
    print(len(json.load(sys.stdin)))
except Exception:
    print(0)')"
    if [ "$mine" = "0" ]; then
      skip "$t: first user has no rows — nothing for the second to not-see"
      continue
    fi

    body="$(rows "$t?select=user_id&limit=200" "$JWT2")"
    seen="$(printf '%s' "$body" | python3 -c 'import sys,json
try:
    rows=json.load(sys.stdin)
except Exception:
    print("PARSE"); raise SystemExit
other=sys.argv[1]
print(sum(1 for r in rows if r.get("user_id")==other))' "$USER_ID")"
    if [ "$seen" = "PARSE" ]; then
      bad "$t: second user's response was not JSON"
    elif [ "$seen" = "0" ]; then
      ok "$t: second user sees none of the first user's $mine rows"
    else
      bad "$t: SECOND USER SEES $seen OF THE FIRST USER'S $mine ROWS"
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
