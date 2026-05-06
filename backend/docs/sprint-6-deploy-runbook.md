# Sprint 6 Deploy + Smoke-Test Runbook

This runbook is run by the operator (`AWS_PROFILE=little-signals-staging`) after
the Sprint 6 PR merges to `master`. Sprint 6 adds two in-process deletion jobs
and two CLI entrypoints; no new infrastructure.

## 1. Verify there are no infra changes

```bash
cd backend/infra
terraform plan
```

Expected: `No changes. Your infrastructure matches the configuration.`

If anything is reported, stop and investigate before applying.

## 2. Build and push 0.6.0

```bash
cd backend
make image VERSION=0.6.0
make push  VERSION=0.6.0
```

## 3. Roll ECS

Update the staging task definition to image tag `0.6.0`. Same procedure as
Sprint 5 (see `sprint-5-deploy-runbook.md` §5).

## 4. Run the smoke test

```bash
API_BASE=https://api-staging.friendlykr.com ./scripts/sprint-6-smoke.sh
```

Expected: ends with `=== Sprint 6 smoke OK ===`.

> The smoke runs `poetry run python -m app.jobs.purge_accounts ...` locally
> against staging. That works because the CLI connects via `DATABASE_URL` —
> set that env var to the staging RDS URL before running, or run the smoke
> from inside an ECS exec session.

## 5. Confirm the in-process loop is alive

ECS task logs should include, within `purge_interval_seconds` (default 1h):

```
deletion_purge_expired_accounts count=N cutoff=...
deletion_purge_revoked_biosignals users=N objects=N
```

If you see `purge_accounts_iteration_failed` or `purge_biosignals_iteration_failed`,
capture the stacktrace and roll back.

## 6. On-demand operator runs

Two CLI entrypoints are available for incident response:

```bash
# Hard-delete accounts whose grace window has expired *now*.
poetry run python -m app.jobs.purge_accounts

# Force-purge using a custom window (e.g. delete immediately for a GDPR request).
poetry run python -m app.jobs.purge_accounts --grace-window-days 0

# Wipe biosignals for users whose consent_revoked_at is set.
poetry run python -m app.jobs.purge_biosignals
```

Both connect to the DB via `DATABASE_URL` and S3 via standard AWS creds. Run
them inside an ECS exec session against the staging task so they pick up the
correct IAM role.

## 7. Tag the release

```bash
git tag -a v0.6.0 -m "Sprint 6 — privacy + deletion jobs"
git push origin v0.6.0
```

## Rollback

The deletion jobs do not take destructive locks. To stop them mid-rollout:

1. Roll the ECS task definition back to `0.5.0` (pre-`_purge_loop`).
2. Hard-deletes are non-recoverable — there is no rollback for users already
   purged in step 4 or step 6.
