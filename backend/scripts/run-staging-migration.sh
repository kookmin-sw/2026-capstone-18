#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../infra"

export AWS_PROFILE="${AWS_PROFILE:-little-signals-staging}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"

CLUSTER="$(terraform output -raw ecs_cluster_name)"
SUBNETS="$(terraform output -json private_subnet_ids | jq -r 'join(",")')"
SECURITY_GROUP="$(terraform output -raw ecs_security_group_id)"
TASK_DEFINITION="$(terraform output -raw ecs_task_definition_arn)"

OVERRIDES="$(cat <<'JSON'
{
  "containerOverrides": [
    {
      "name": "backend",
      "command": [
        "sh",
        "-c",
        "export DATABASE_URL=\"postgresql+asyncpg://${DB_USERNAME}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}\" && alembic upgrade head"
      ]
    }
  ]
}
JSON
)"

TASK_ARN="$(aws ecs run-task \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=DISABLED}" \
  --task-definition "$TASK_DEFINITION" \
  --overrides "$OVERRIDES" \
  --query 'tasks[0].taskArn' \
  --output text)"

aws ecs wait tasks-stopped \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --tasks "$TASK_ARN"

EXIT_CODE="$(aws ecs describe-tasks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode' \
  --output text)"

test "$EXIT_CODE" = "0"
