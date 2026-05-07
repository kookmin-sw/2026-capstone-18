#!/usr/bin/env bash
# Sprint 6 smoke test. Drives the new deletion jobs against API_BASE.
# Exits 0 on success, non-zero on the first failure.
#
# Required env:
#   API_BASE       e.g. https://api-staging.friendlykr.com (defaults to localhost)
#   DATABASE_URL   asyncpg URL the CLI jobs connect to
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
  local method="$1" path="$2"; shift 2
  local data="" expected="200"
  if [[ "${1:-}" =~ ^\{ ]]; then data="$1"; shift; fi
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then expected="$1"; shift; fi
  local args=(-sS -o /tmp/sprint6.body -w '%{http_code}' -X "$method" "$API_BASE$path")
  if [[ -n "$data" ]]; then args+=(-H 'content-type: application/json' --data "$data"); fi
  while (( $# > 0 )); do args+=(-H "$1"); shift; done
  local code; code=$(curl "${args[@]}")
  local body; body=$(cat /tmp/sprint6.body)
  require_status "$expected" "$code" "$body"
  echo "$body"
}

step "1. anon sign-in"
TOKENS=$(call POST /api/v1/auth/anon)
ACCESS=$(echo "$TOKENS" | python -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
AUTH="authorization: Bearer $ACCESS"

step "2. /me — confirm user is alive"
call GET /api/v1/me 200 "$AUTH" >/dev/null

step "3. soft-delete the account"
call DELETE /api/v1/account 200 "$AUTH" >/dev/null

step "4. /me — must now be 403 (deleted_at set)"
call GET /api/v1/me 403 "$AUTH" >/dev/null

step "5. run purge_accounts CLI with grace=-1 to force hard-delete"
poetry run python -m app.jobs.purge_accounts --grace-window-days -1
echo "OK"

step "6. /me — must now be 403 still (token sub no longer maps to a user)"
call GET /api/v1/me 403 "$AUTH" >/dev/null

step "7. fresh anon sign-in, enable+revoke biosignal consent"
TOKENS=$(call POST /api/v1/auth/anon)
ACCESS=$(echo "$TOKENS" | python -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
AUTH="authorization: Bearer $ACCESS"
call PATCH /api/v1/consent '{"consent_raw_biosignals":true}' 200 "$AUTH" >/dev/null
call POST /api/v1/sync/biosignals \
  '{"signal_type":"hrv","recorded_at":"2026-05-06T12:00:00+00:00","byte_size":1024,"content_hash":"x"}' \
  201 "$AUTH" >/dev/null
call PATCH /api/v1/consent '{"consent_raw_biosignals":false}' 200 "$AUTH" >/dev/null

step "8. run purge_biosignals CLI"
poetry run python -m app.jobs.purge_biosignals
echo "OK"

step "9. confirm new biosignal upload is now blocked (consent revoked)"
call POST /api/v1/sync/biosignals \
  '{"signal_type":"hrv","recorded_at":"2026-05-06T12:01:00+00:00","byte_size":1024,"content_hash":"x"}' \
  403 "$AUTH" >/dev/null

echo
echo "=== Sprint 6 smoke OK ==="
