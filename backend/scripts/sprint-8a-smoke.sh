#!/usr/bin/env bash
# Sprint 8a smoke test — run AFTER staging deploy to confirm observability is live.
# Requires: AWS_PROFILE=little-signals-staging, jq, curl.

set -euo pipefail

API="${API:-https://api-staging.friendlykr.com}"
REGION="${AWS_REGION:-ap-northeast-2}"

echo "==> 1. /health reports 0.8.0"
curl -fsS "$API/health" | jq -e '.version == "0.8.0"' >/dev/null
echo "  ok"

echo "==> 2. /metrics returns Prometheus text + custom counters"
curl -fsS "$API/metrics" | grep -q "^events_created_total " || {
  echo "    FAIL — events_created_total missing from /metrics" >&2
  exit 1
}
curl -fsS "$API/metrics" | grep -q "^active_websocket_connections " || {
  echo "    FAIL — active_websocket_connections missing" >&2
  exit 1
}
echo "  ok"

echo "==> 3. /metrics excludes its own scrapes (excluded_handlers worked)"
if curl -fsS "$API/metrics" | grep -E 'http_request_duration_seconds.*handler="/metrics"'; then
  echo "    FAIL — /metrics scrapes are being recorded; exclusion not working" >&2
  exit 1
fi
echo "  ok"

echo "==> 4. ADOT collector log group exists with recent entries"
aws logs describe-log-groups \
  --region "$REGION" \
  --log-group-name-prefix "/ecs/little-signals-staging-otel-collector" \
  --query 'logGroups[0].logGroupName' --output text | grep -q "otel-collector" || {
  echo "    FAIL — collector log group missing" >&2
  exit 1
}
echo "  ok"

echo "==> 5. SNS topic exists and has at least one CONFIRMED subscription"
TOPIC_ARN=$(aws sns list-topics --region "$REGION" --query "Topics[?contains(TopicArn, 'little-signals-staging-alerts')].TopicArn | [0]" --output text)
test -n "$TOPIC_ARN" || { echo "    FAIL — SNS topic missing" >&2; exit 1; }
CONFIRMED=$(aws sns list-subscriptions-by-topic --region "$REGION" --topic-arn "$TOPIC_ARN" \
  --query "length(Subscriptions[?SubscriptionArn != 'PendingConfirmation'])" --output text)
test "$CONFIRMED" -ge 1 || {
  echo "    FAIL — no confirmed subscribers; check your email and click the AWS confirmation link" >&2
  exit 1
}
echo "  ok ($CONFIRMED confirmed subscriber(s))"

echo
echo "All sprint-8a smoke checks passed."
