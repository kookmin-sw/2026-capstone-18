# little-signals Infrastructure

Staging runs in AWS Seoul (`ap-northeast-2`) on ECS Fargate with private RDS Postgres.

## One-Time State Bootstrap

```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend
chmod +x scripts/bootstrap-terraform-state.sh
AWS_PROFILE=little-signals-staging ./scripts/bootstrap-terraform-state.sh
cp infra/backend.hcl.example infra/backend.hcl
```

## Terraform

```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend/infra
AWS_PROFILE=little-signals-staging terraform init -backend-config=backend.hcl
AWS_PROFILE=little-signals-staging terraform plan -var-file=staging.tfvars
AWS_PROFILE=little-signals-staging terraform apply -var-file=staging.tfvars
```

## First Image Push

After Terraform creates ECR, run from `backend/`:

```bash
AWS_PROFILE=little-signals-staging make ecr-login
AWS_PROFILE=little-signals-staging make ecr-push IMAGE_TAG=0.2.0
```

## Staging Migration

```bash
AWS_PROFILE=little-signals-staging ./scripts/enable-rds-timescaledb.sh
AWS_PROFILE=little-signals-staging ./scripts/run-staging-migration.sh
```

## Smoke Test

```bash
make smoke-staging
```
