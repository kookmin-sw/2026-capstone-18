#!/usr/bin/env bash
# Sprint 5 smoke test. Drives the new endpoints against API_BASE.
# Exits 0 on success, non-zero on the first failure.
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
  local args=(-sS -o /tmp/sprint5.body -w '%{http_code}' -X "$method" "$API_BASE$path")
  if [[ -n "$data" ]]; then args+=(-H 'content-type: application/json' --data "$data"); fi
  while (( $# > 0 )); do args+=(-H "$1"); shift; done
  local code; code=$(curl "${args[@]}")
  local body; body=$(cat /tmp/sprint5.body)
  require_status "$expected" "$code" "$body"
  echo "$body"
}

step "1. anon sign-in"
TOKENS=$(call POST /api/v1/auth/anon)
ACCESS=$(echo "$TOKENS" | python -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
AUTH="authorization: Bearer $ACCESS"

step "2. register fcm token"
call POST /api/v1/devices/fcm-token '{"token":"smoke-token","platform":"android"}' 201 "$AUTH" >/dev/null

step "3. enable raw biosignal consent"
call PATCH /api/v1/consent '{"consent_raw_biosignals":true}' 200 "$AUTH" >/dev/null

step "4. presigned biosignal upload"
BIO=$(call POST /api/v1/sync/biosignals \
  '{"signal_type":"hrv","recorded_at":"2026-05-06T12:00:00+00:00","byte_size":1024,"content_hash":"x"}' \
  201 "$AUTH")
echo "$BIO" | grep -q "presigned_put_url" || { echo "FAIL: no URL"; exit 1; }

step "5. presigned backup upload"
SYNC=$(call POST /api/v1/sync/upload \
  '{"kind":"backup","byte_size":2048,"content_hash":"x"}' \
  201 "$AUTH")
echo "$SYNC" | grep -q "presigned_put_url" || { echo "FAIL: no URL"; exit 1; }

step "6. backup download"
call GET /api/v1/sync/download?kind=backup 200 "$AUTH" >/dev/null

step "7. wipe sync"
call DELETE /api/v1/sync 204 "$AUTH" >/dev/null

step "8. revoke consent — biosignal upload should now 403"
call PATCH /api/v1/consent '{"consent_raw_biosignals":false}' 200 "$AUTH" >/dev/null
call POST /api/v1/sync/biosignals \
  '{"signal_type":"hrv","recorded_at":"2026-05-06T12:00:00+00:00","byte_size":1024,"content_hash":"x"}' \
  403 "$AUTH" >/dev/null

echo
echo "ALL SMOKE TESTS PASSED."
