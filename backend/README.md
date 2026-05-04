# little-signals — Backend

FastAPI service for Project Phase. Runs on AWS Seoul (ECS Fargate + RDS Postgres + TimescaleDB) in production. Locally: Docker (Colima or Docker Desktop) for Postgres, Poetry for the Python app.

See [`docs/backend-architecture-spec.md`](docs/backend-architecture-spec.md) for the architecture and [`docs/backend-sprint-plan.md`](docs/backend-sprint-plan.md) for the build plan.

## Setup

Prereqs (one-time):
- Python 3.12 via pyenv
- Poetry 2.x
- Docker (Colima or Docker Desktop) with Compose v2 plugin
- Postgres 15 client (`psql`)

Install Python deps:
```bash
cd backend
poetry install
```

## Run locally

Bring up Postgres (with TimescaleDB) + Adminer:
```bash
docker compose up -d
```

Postgres: `localhost:5432`, user `little_signals`, password `dev_only_password`, db `little_signals_dev`. Adminer: http://localhost:8080.

Tear down:
```bash
docker compose down
```

> **Port 5432 conflict?** If you have Homebrew Postgres running locally (`brew services list` shows `postgresql@15` started) or another container bound to 5432, stop them before `docker compose up`:
> ```bash
> brew services stop postgresql@15
> ```
> Restart afterward with `brew services start postgresql@15`.

## Endpoints (Sprint 1)

- `GET /health` — liveness probe, returns `{"status": "ok", "version": "0.1.0"}`
- `GET /` — redirects to `/docs`
- `GET /docs` — Swagger UI
- `GET /redoc` — ReDoc UI
- `GET /openapi.json` — OpenAPI spec

Real CRUD endpoints (events, cycles, settings, etc.) come in Sprint 4.

## Database

Local Postgres runs via `docker compose up -d`. Apply migrations:

```bash
make migrate
```

Tests use a separate `little_signals_test` DB. Apply migrations there with:

```bash
make migrate-test
```

## Run tests

```bash
poetry run pytest
```

(No tests yet — Sprint 1.)

## Lint and type-check

```bash
poetry run ruff check .
poetry run ruff format --check .
poetry run mypy app/
```

## Deploy

Sprint 2 deploys staging only.

```bash
cd backend
AWS_PROFILE=little-signals-staging ./scripts/bootstrap-terraform-state.sh
cd infra
cp backend.hcl.example backend.hcl
AWS_PROFILE=little-signals-staging terraform init -backend-config=backend.hcl
AWS_PROFILE=little-signals-staging terraform apply -var-file=staging.tfvars
cd ..
AWS_PROFILE=little-signals-staging make ecr-login
AWS_PROFILE=little-signals-staging make ecr-push IMAGE_TAG=0.2.0
cd infra
ECR_URL="$(AWS_PROFILE=little-signals-staging terraform output -raw ecr_repository_url)"
AWS_PROFILE=little-signals-staging terraform apply -var-file=staging.tfvars -var "container_image=$ECR_URL:0.2.0"
cd ..
AWS_PROFILE=little-signals-staging ./scripts/enable-rds-timescaledb.sh
AWS_PROFILE=little-signals-staging ./scripts/run-staging-migration.sh
make smoke-staging
```

The first `terraform apply` provisions networking, ECR, RDS, and the ALB/ECS service against the placeholder image in `staging.tfvars`. After `make ecr-push` lands a real image, the second apply re-points the ECS task definition at that image via `-var container_image=...` so the service actually rolls out the backend.

Expected staging URL: `https://api-staging.littlesignals.app`.

## Sprint status

Currently in **Sprint 2 — First AWS Deploy**. See [`docs/superpowers/plans/`](docs/superpowers/plans/) for the active plan.
