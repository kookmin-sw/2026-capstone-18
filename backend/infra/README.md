# little-signals Infrastructure

Staging runs in AWS Seoul (`ap-northeast-2`) on ECS Fargate with private RDS Postgres.

## One-Time State Bootstrap

Executable now as part of Task 2:

```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend
chmod +x scripts/bootstrap-terraform-state.sh
AWS_PROFILE=little-signals-staging ./scripts/bootstrap-terraform-state.sh
cp infra/backend.hcl.example infra/backend.hcl
```

## Terraform

After Task 3 creates `staging.tfvars`, initialize and apply staging infrastructure:

```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend/infra
AWS_PROFILE=little-signals-staging terraform init -backend-config=backend.hcl
AWS_PROFILE=little-signals-staging terraform plan -var-file=staging.tfvars
AWS_PROFILE=little-signals-staging terraform apply -var-file=staging.tfvars
```

## First Image Push

After Task 6 adds Makefile deploy targets and Terraform creates ECR, run from `backend/`:

```bash
AWS_PROFILE=little-signals-staging make ecr-login
AWS_PROFILE=little-signals-staging make ecr-push IMAGE_TAG=0.2.0
```

## Staging Migration

After Task 8 adds migration scripts, run from `backend/`:

```bash
AWS_PROFILE=little-signals-staging ./scripts/enable-rds-timescaledb.sh
AWS_PROFILE=little-signals-staging ./scripts/run-staging-migration.sh
```

## Smoke Test

After Task 6 adds `smoke-staging` and the ALB is live, run from `backend/`:

```bash
make smoke-staging
```

## Sprint 2 Verification Checklist

- `curl -fsS https://api-staging.friendlykr.com/health` returns `{"status":"ok","version":"0.2.0"}`.
- `curl -fsS https://api-staging.friendlykr.com/ready` returns `{"status":"ok","database":"ok"}`.
- ECS service desired count is `1` and running count is `1`.
- ALB target group shows one healthy target.
- CloudWatch log group `/ecs/little-signals-staging-backend` has recent logs.
- RDS `Publicly accessible` is `No`.
- RDS security group allows inbound `5432` only from the ECS security group.
- Secrets Manager contains the RDS-managed master user secret for `little-signals-staging-postgres`.
- ECR repository has image tags `0.2.0` and `latest`.

## Sprint 3 Verification Checklist

- `little-signals-staging/supabase` secret in AWS Secrets Manager contains keys `url`, `anon_key`, `service_role_key`, `jwt_secret`, `google_oauth_client_id`.
- ECS task definition env contains five new entries sourced from `:json-key::` references on the Supabase secret.
- Alembic migration `expand_users_and_add_user_settings` is applied to staging RDS (`alembic_version` table reflects the new revision).
- `users` table has `supabase_user_id`, `anon_id`, `role`, `consent_raw_biosignals`, `consent_revoked_at`, `deleted_at` columns.
- `user_settings` table exists with all spec §6.3 default values.
- `curl -fsS -X POST https://api-staging.friendlykr.com/api/v1/auth/anon` returns a `TokenResponse` with `is_anonymous: true`.
- That JWT can hit `https://api-staging.friendlykr.com/api/v1/me` and returns the new user.
- Posting a real Google ID token to `/api/v1/auth/google` (via the mobile build or `gcloud auth print-identity-token`) returns a non-anonymous JWT.
- `DELETE /api/v1/account` sets `deleted_at`; subsequent `GET /me` returns 403; `POST /api/v1/account/restore` within 30 days clears the flag.
