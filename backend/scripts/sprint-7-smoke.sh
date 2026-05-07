#!/usr/bin/env bash
# Sprint 7 smoke. Validates EventBridge → ECS RunTask → CLI → audit_log.
# Runs against API_BASE + DATABASE_URL pointing at staging.
#
# Required env:
#   API_BASE       e.g. https://api-staging.friendlykr.com
#   DATABASE_URL   asyncpg URL of the staging RDS
#   AWS_PROFILE    e.g. little-signals-staging (for the schedule trigger)
#
# Strategy:
#   1. Drive the same code path locally with the CLI (proves the audit row lands).
#   2. Verify the schedules exist and are ENABLED in AWS.
#   3. Confirm the DLQ exists and is empty (treats >0 as warning, not failure).
set -euo pipefail
API_BASE="${API_BASE:-http://localhost:8000}"
ENV="${ENVIRONMENT:-staging}"
PREFIX="little-signals-${ENV}"

step() { echo; echo "=== $1 ==="; }

require() {
  if [[ -z "${!1:-}" ]]; then echo "FAIL: env $1 must be set"; exit 1; fi
}

require DATABASE_URL
require AWS_PROFILE

step "1. anon sign-in + soft-delete + force purge_accounts"
TOKENS=$(curl -sS -X POST "$API_BASE/api/v1/auth/anon")
ACCESS=$(echo "$TOKENS" | python -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
AUTH="authorization: Bearer $ACCESS"
USER_ID=$(curl -sS -H "$AUTH" "$API_BASE/api/v1/me" | python -c 'import sys,json;print(json.load(sys.stdin)["id"])')
echo "user_id=$USER_ID"

curl -sS -X DELETE -H "$AUTH" "$API_BASE/api/v1/account" >/dev/null
poetry run python -m app.jobs.purge_accounts --grace-window-days -1
echo "OK"

step "2. assert audit_log row landed for that user"
ROW_COUNT=$(poetry run python -c "
import asyncio, os
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from app.models.audit_log import AuditLog
async def main():
    eng = create_async_engine(os.environ['DATABASE_URL'])
    async with AsyncSession(eng) as s:
        rows = (await s.execute(
            select(AuditLog).where(
                AuditLog.action=='hard_delete_user',
                AuditLog.target_user_id=='$USER_ID'
            )
        )).scalars().all()
        print(len(rows))
asyncio.run(main())
")
if [[ "$ROW_COUNT" != "1" ]]; then
  echo "FAIL: expected 1 audit row, got $ROW_COUNT"
  exit 1
fi
echo "OK (1 audit row)"

step "3. confirm both schedules exist and are ENABLED"
for SCHED in "${PREFIX}-purge-accounts" "${PREFIX}-purge-biosignals"; do
  STATE=$(aws scheduler get-schedule \
    --name "$SCHED" \
    --group-name "${PREFIX}-cron" \
    --query 'State' --output text)
  if [[ "$STATE" != "ENABLED" ]]; then
    echo "FAIL: $SCHED state is $STATE, expected ENABLED"
    exit 1
  fi
  echo "OK $SCHED ENABLED"
done

step "4. confirm DLQ exists and is empty"
DLQ_URL=$(aws sqs get-queue-url --queue-name "${PREFIX}-scheduler-dlq" --query 'QueueUrl' --output text)
DEPTH=$(aws sqs get-queue-attributes --queue-url "$DLQ_URL" \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' --output text)
if [[ "$DEPTH" != "0" ]]; then
  echo "WARN: DLQ depth=$DEPTH (not a hard fail; check CloudWatch)"
fi
echo "OK (depth=$DEPTH)"

echo
echo "=== Sprint 7 smoke OK ==="
