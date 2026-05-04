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

Production deployment lives on AWS Seoul (`ap-northeast-2`) via Terraform + ECS Fargate. Sprint 2 wires this up. Until then there is no deploy.

## Sprint status

Currently in **Sprint 0 — Foundation & Verification**. See [`docs/superpowers/plans/`](docs/superpowers/plans/) for the active plan.
