# Sprint 7 Deploy + Smoke-Test Runbook

This runbook is run by the operator (`AWS_PROFILE=little-signals-staging`)
after the Sprint 7 PR merges to `master`. Sprint 7 swaps the in-process
deletion loop for EventBridge Scheduler + ECS RunTask, and adds an
`audit_log` row per privacy/deletion action.

## 1. Apply infra

```bash
cd backend/infra
AWS_PROFILE=little-signals-staging terraform plan -var-file=staging.tfvars
AWS_PROFILE=little-signals-staging terraform apply -var-file=staging.tfvars
```

Expected new resources: SQS DLQ, scheduler IAM role, cron ECS task
definition, scheduler group, two schedules, DLQ alarm.

## 2. Apply the audit_log migration

```bash
cd backend
AWS_PROFILE=little-signals-staging ./scripts/run-staging-migration.sh
```

Expected: `Running upgrade 6cd3f7dbdd70 -> 81190b1e74b8, add audit_log table`.

## 3. Build and push 0.7.0

```bash
cd backend
make image VERSION=0.7.0
make push  VERSION=0.7.0
```

## 4. Roll the serving ECS task

Update the staging serving task definition to `0.7.0` (same procedure as
Sprint 5/6). The cron task definition picks up the new image automatically
on the next schedule fire because `var.container_image` is shared.

## 5. Run the smoke test

```bash
DATABASE_URL=<staging-rds-url> \
API_BASE=https://api-staging.friendlykr.com \
AWS_PROFILE=little-signals-staging \
  ./scripts/sprint-7-smoke.sh
```

Expected: ends with `=== Sprint 7 smoke OK ===`.

## 6. Verify a real schedule fire (within 6 hours)

After a `purge_biosignals` schedule fires (every 6h at minute 15), the
ECS console under cluster → tasks should show a completed cron task with
exit code 0. CloudWatch log group `/ecs/little-signals-staging-cron`
must contain a `deletion_purge_revoked_biosignals` log line.

If exit code is non-zero or the task never fires, the SQS DLQ depth
will go above 0 within ~1 hour and the alarm
`little-signals-staging-scheduler-dlq-depth` flips to ALARM.

## 7. Tag the release

```bash
git tag -a v0.7.0 -m "Sprint 7 — EventBridge + audit"
git push origin v0.7.0
```

## Rollback

The schedules are independently disable-able from the console or CLI:

```bash
aws scheduler update-schedule \
  --name little-signals-staging-purge-accounts \
  --group-name little-signals-staging-cron \
  --state DISABLED
  # (re-pass other required params; or use the AWS Console toggle)
```

If the audit_log table itself is the problem, the migration is reversible
via `alembic downgrade -1`. Hard-deletes already executed are not
recoverable.
