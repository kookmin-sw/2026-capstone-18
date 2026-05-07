#!/usr/bin/env bash
# Bootstrap the CI Postgres service container with the schema layout tests expect.
# Idempotent — safe to call repeatedly.

set -euo pipefail

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-little_signals}"
PGPASSWORD="${PGPASSWORD:-dev_only_password}"
export PGPASSWORD

echo "Waiting for Postgres at ${PGHOST}:${PGPORT}..."
for i in $(seq 1 30); do
  if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

DB_EXISTS=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname='little_signals_test'")
if [[ "$DB_EXISTS" != "1" ]]; then
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres \
    -c "CREATE DATABASE little_signals_test"
fi

for db in little_signals_dev little_signals_test; do
  if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -tAc \
       "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1; then
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db" \
      -c "CREATE EXTENSION IF NOT EXISTS timescaledb"
  fi
done

echo "CI Postgres bootstrap complete."
