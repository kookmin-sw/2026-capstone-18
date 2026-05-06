#!/usr/bin/env bash
# Sprint 4 smoke test. Drives every Sprint 4 endpoint against API_BASE.
# Exits 0 on success, non-zero on the first failure.
#
# Usage:
#   API_BASE=https://api-staging.littlesignals.app ./scripts/sprint-4-smoke.sh

set -euo pipefail

API_BASE="${API_BASE:-http://localhost:8000}"

step() { echo; echo "=== $1 ==="; }

require_status() {
  local expected="$1" actual="$2" body="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: expected $expected, got $actual"
    echo "Body: $body"
    exit 1
  fi
  echo "OK ($actual)"
}

call() {
  # call METHOD PATH [JSON] [EXPECTED] [HEADER ...]
  local method="$1" path="$2"; shift 2
  local data="" expected="200"
  if [[ "${1:-}" =~ ^\{ ]]; then data="$1"; shift; fi
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then expected="$1"; shift; fi
  local args=(-sS -o /tmp/sprint4.body -w '%{http_code}' -X "$method" "$API_BASE$path")
  if [[ -n "$data" ]]; then args+=(-H 'content-type: application/json' --data "$data"); fi
  while (( $# > 0 )); do args+=(-H "$1"); shift; done
  local code; code=$(curl "${args[@]}")
  local body; body=$(cat /tmp/sprint4.body)
  require_status "$expected" "$code" "$body"
  echo "$body"
}

step "1. anon sign-in"
TOKENS=$(call POST /api/v1/auth/anon)
ACCESS=$(echo "$TOKENS" | python -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
AUTH="authorization: Bearer $ACCESS"

step "2. /me"
call GET /api/v1/me 200 "$AUTH" >/dev/null

step "3. default settings"
SETTINGS=$(call GET /api/v1/settings 200 "$AUTH")
echo "$SETTINGS" | grep -q '"language":"ko"' || { echo "FAIL: default language not ko"; exit 1; }

step "4. log period start"
call POST /api/v1/cycles/period-start \
  '{"period_start_date":"2026-05-01","cycle_length_days":28}' 201 "$AUTH" >/dev/null

step "5. current cycle"
CURRENT=$(call GET /api/v1/cycles/current 200 "$AUTH")
echo "$CURRENT" | grep -q '"phase"' || { echo "FAIL: phase missing"; exit 1; }

step "6. log stress event"
EVENT=$(call POST /api/v1/events \
  '{"detected_at":"2026-05-06T12:00:00+00:00","model_confidence":0.91,"cycle_phase":"luteal","cycle_day":22}' \
  201 "$AUTH")
EID=$(echo "$EVENT" | python -c 'import sys,json;print(json.load(sys.stdin)["id"])')

step "7. list events"
call GET /api/v1/events 200 "$AUTH" >/dev/null

step "8. patch consent on"
call PATCH /api/v1/consent '{"consent_raw_biosignals":true}' 200 "$AUTH" >/dev/null

step "9. consent state reflects toggle"
CONSENT=$(call GET /api/v1/consent 200 "$AUTH")
echo "$CONSENT" | grep -q '"consent_raw_biosignals":true' || { echo "FAIL"; exit 1; }

step "10. delete account"
call DELETE /api/v1/account 200 "$AUTH" >/dev/null

step "11. restore account"
call POST /api/v1/account/restore '{}' 200 "$AUTH" >/dev/null

echo
echo "ALL SMOKE TESTS PASSED."
