# Sakama task runner (convention borrowed from OpenNutriTracker)
# Requires: just (brew install just)

# Install dependencies
install:
    cd app && flutter pub get

# Run code generation (freezed, riverpod, drift)
# `clean` first is LOAD-BEARING, not tidiness. build_runner caches the contents
# of .env, and --delete-conflicting-outputs does NOT clear that cache — so
# editing .env and rebuilding can silently keep the OLD values in env.g.dart.
# That shipped a phone build compiled against https://YOUR-PROJECT.supabase.co
# for days: sync never reached the server and Vita reported a network error,
# looking like three unrelated bugs. See test/core/env_not_placeholder_test.dart.
build:
    cd app && dart run build_runner clean
    cd app && dart run build_runner build --delete-conflicting-outputs

# Format
format:
    cd app && dart format lib test

# Static analysis
analyze:
    cd app && flutter analyze

# Tests
test:
    cd app && flutter test

# Drift schema migration tests — MANDATORY before any release (see docs/MOBILE.md)
test-migrations:
    cd app && flutter test test/migration

# Licence check — Sakama is closed-source; no GPL/AGPL may enter
licences:
    cd app && flutter pub deps --json > /tmp/deps.json && echo "review /tmp/deps.json; run the licence-guard agent"

# Full CI pass
ci: install build format analyze test test-migrations licences

# Prove RLS holds against the LIVE project (CLAUDE.md rule 2).
#
# Reads app/.env for the URL and anon key; the two credentials are yours to
# supply. Safe to run against production: it reads, and its only write is one
# that must fail.
#
#   just verify-rls  (with SAKAMA_TEST_EMAIL / SAKAMA_TEST_PASSWORD exported)
verify-rls:
    bash supabase/verify-rls.sh
