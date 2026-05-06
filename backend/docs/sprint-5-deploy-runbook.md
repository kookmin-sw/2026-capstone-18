# Sprint 5 Deploy + Smoke-Test Runbook

This runbook is run by the operator (`AWS_PROFILE=little-signals-staging`) after the
Sprint 5 PR merges to `master`.

## 1. Apply Terraform changes

```bash
cd backend/infra
terraform init -upgrade
terraform plan
terraform apply
```

Expected: two new S3 buckets (`little-signals-sync-staging`, `little-signals-biosignals-staging`)
and one new Secrets Manager secret (`little-signals-staging/firebase`) created.
ECS task role has the new IAM policy attached.

## 2. Populate the Firebase secret

Follow `backend/docs/sprint-5-firebase-runbook.md` to obtain the FCM service-account
JSON, then:

```bash
AWS_PROFILE=little-signals-staging aws secretsmanager put-secret-value \
  --region ap-northeast-2 \
  --secret-id "$(terraform -chdir=backend/infra output -raw firebase_secret_arn)" \
  --secret-string file://path/to/service-account.json
shred -u path/to/service-account.json
```

## 3. Apply the migration

```bash
cd backend
AWS_PROFILE=little-signals-staging ./scripts/run-staging-migration.sh
```

Expected: the one-off ECS task exits 0; staging RDS now has
`websocket_connections`, `fcm_tokens`, `sync_blobs`, and `raw_biosignal_uploads`
(the last is a hypertable).

## 4. Build and push 0.5.0

```bash
cd backend
make image VERSION=0.5.0
make push  VERSION=0.5.0
```

## 5. Roll ECS

Update the staging task definition's image tag to `0.5.0`. Either:

```bash
aws ecs describe-task-definition \
  --task-definition little-signals-backend-staging \
  --query 'taskDefinition' \
  --output json > /tmp/td.json
jq '.containerDefinitions[0].image = (.containerDefinitions[0].image | sub(":[^:]+$"; ":0.5.0"))' \
  /tmp/td.json > /tmp/td-new.json
aws ecs register-task-definition --cli-input-json file:///tmp/td-new.json
aws ecs update-service \
  --cluster little-signals-staging \
  --service little-signals-backend-staging \
  --task-definition little-signals-backend-staging \
  --force-new-deployment
```

…or bump `var.image_tag` in Terraform and `terraform apply`.

## 6. Run smoke tests

```bash
API_BASE=https://api-staging.littlesignals.app ./scripts/sprint-5-smoke.sh
```

Expected: every step prints `OK` and the script exits 0.

## 7. Verify CloudWatch

Check for connect/disconnect events:

```bash
AWS_PROFILE=little-signals-staging aws logs filter-log-events \
  --log-group-name /aws/ecs/little-signals-backend-staging \
  --start-time $(date -v-15M +%s)000 \
  --filter-pattern '{ $.event = "websocket_connected" }'
```

Expected: matches from the smoke run.

Check for unhandled exceptions:

```bash
AWS_PROFILE=little-signals-staging aws logs filter-log-events \
  --log-group-name /aws/ecs/little-signals-backend-staging \
  --start-time $(date -v-15M +%s)000 \
  --filter-pattern '{ $.event = "unhandled_exception" }'
```

Expected: zero matches.

## 8. Tag the deploy

```bash
git tag -a v0.5.0 -m "Sprint 5 — real-time and sync"
git push origin v0.5.0
```
