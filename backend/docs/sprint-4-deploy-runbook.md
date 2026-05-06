# Sprint 4 Deploy + Smoke-Test Runbook

This runbook is run by the operator (`AWS_PROFILE=little-signals-staging`) after the
Sprint 4 PR merges to `master`. It covers tagging, deploying, and smoke-testing the
new core data endpoints.

## 1. Apply the migration to staging RDS

Pull the latest Sprint 4 code into the directory the ECS one-off scripts run from:

```bash
git checkout master && git pull
cd backend
AWS_PROFILE=little-signals-staging ./scripts/run-staging-migration.sh
```

Expected: the ECS one-off task exits `0` and `\d stress_events` / `\d cycles` show
the new tables in the staging database.

Verify the hypertable was created:

```bash
AWS_PROFILE=little-signals-staging aws rds-data execute-statement \
  --resource-arn "$(terraform -chdir=infra output -raw rds_cluster_arn 2>/dev/null || echo)" \
  --database little_signals \
  --secret-arn "$(terraform -chdir=infra output -raw db_secret_arn)" \
  --sql "SELECT hypertable_name FROM timescaledb_information.hypertables WHERE hypertable_name='stress_events'"
```

(If you don't use rds-data, port-forward via the bastion and run the same query in psql.)

## 2. Build and push the 0.4.0 image

```bash
cd backend
make image VERSION=0.4.0
make push  VERSION=0.4.0
```

Expected: ECR has a new `0.4.0` tag for the `little-signals-backend` repository.

## 3. Roll the ECS service

Update the staging task definition's image tag to `0.4.0`. Two options — pick one:

**Option A — `aws ecs register-task-definition` + `update-service`:**

```bash
aws ecs describe-task-definition \
  --task-definition little-signals-backend-staging \
  --query 'taskDefinition' \
  --output json > /tmp/td.json

# Replace the image and re-register:
jq '.containerDefinitions[0].image = (.containerDefinitions[0].image | sub(":[^:]+$"; ":0.4.0"))' \
  /tmp/td.json > /tmp/td-new.json

aws ecs register-task-definition --cli-input-json file:///tmp/td-new.json

aws ecs update-service \
  --cluster little-signals-staging \
  --service little-signals-backend-staging \
  --task-definition little-signals-backend-staging \
  --force-new-deployment
```

**Option B — bump the version in Terraform** (`backend/infra/ecs.tf`,
`var.image_tag` or equivalent) and `terraform apply`.

Wait until `aws ecs describe-services` shows `runningCount == desiredCount` and
the deployment status is `PRIMARY` only.

## 4. Run the smoke tests against staging

The smoke-test script (`backend/scripts/sprint-4-smoke.sh`) walks the full data
flow:

1. `POST /api/v1/auth/anon` → grab access_token + refresh_token
2. `GET /api/v1/me` → confirm `role == "user"`
3. `GET /api/v1/settings` → confirm defaults
4. `POST /api/v1/cycles/period-start` → log a fake period
5. `GET /api/v1/cycles/current` → confirm phase is computed
6. `POST /api/v1/events` → log a fake stress event
7. `GET /api/v1/events` → confirm the event is returned
8. `PATCH /api/v1/consent` → toggle raw biosignal consent
9. `GET /api/v1/consent` → confirm the toggle stuck
10. `DELETE /api/v1/account` → start the grace window
11. `POST /api/v1/account/restore` → cancel the grace window

Run it with:

```bash
API_BASE=https://api-staging.littlesignals.app ./scripts/sprint-4-smoke.sh
```

Expected: every step prints `OK` and the final exit code is `0`.

## 5. Verify CloudWatch logs

```bash
AWS_PROFILE=little-signals-staging aws logs filter-log-events \
  --log-group-name /aws/ecs/little-signals-backend-staging \
  --start-time $(date -v-15M +%s)000 \
  --filter-pattern '{ $.event = "request_validation_failed" }'
```

If the smoke test sent any deliberately bad payloads, they should appear here.
For a clean smoke run, this filter returns no events — that is fine.

```bash
AWS_PROFILE=little-signals-staging aws logs filter-log-events \
  --log-group-name /aws/ecs/little-signals-backend-staging \
  --start-time $(date -v-15M +%s)000 \
  --filter-pattern '{ $.event = "unhandled_exception" }'
```

Expected: zero matches. Any matches mean a 500 happened during the smoke run —
investigate before declaring the deploy successful.

## 6. Tag the deploy

```bash
git tag -a v0.4.0 -m "Sprint 4 — core data endpoints"
git push origin v0.4.0
```
