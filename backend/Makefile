# little-signals backend dev commands.
# Run from the backend/ directory (or `make -C backend <target>` from repo root).

-include .env

DATABASE_URL ?= postgresql+asyncpg://little_signals:dev_only_password@localhost:5432/little_signals_dev
TEST_DATABASE_URL ?= postgresql+asyncpg://little_signals:dev_only_password@localhost:5432/little_signals_test

.PHONY: help install run test test-fast lint format typecheck migrate migrate-test \
        db-up db-down db-logs check clean \
        docker-build ecr-login ecr-push smoke-staging smoke-sprint-8a _require-ecr-url

help:  ## Show this help.
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install:  ## Install Python dependencies via Poetry.
	poetry install

run:  ## Run the FastAPI app locally with auto-reload on http://localhost:8000.
	poetry run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

test:  ## Run the full pytest suite.
	poetry run pytest

test-fast:  ## Run tests, stop on first failure.
	poetry run pytest -x --ff

lint:  ## Run ruff lint.
	poetry run ruff check .

format:  ## Run ruff format (writes changes).
	poetry run ruff format .

typecheck:  ## Run mypy in strict mode against app/.
	poetry run mypy app/

check: lint typecheck test  ## Run lint + typecheck + tests. Mirrors CI.

migrate:  ## Apply Alembic migrations to the dev DB.
	DATABASE_URL="$(DATABASE_URL)" poetry run alembic upgrade head

migrate-test:  ## Apply Alembic migrations to the test DB.
	DATABASE_URL="$(TEST_DATABASE_URL)" poetry run alembic upgrade head

db-up:  ## Start the local Postgres + Adminer stack via docker compose.
	docker compose up -d

db-down:  ## Stop the local Postgres + Adminer stack.
	docker compose down

db-logs:  ## Tail the Postgres container logs.
	docker compose logs -f postgres

clean:  ## Remove caches and build artifacts.
	rm -rf .pytest_cache .mypy_cache .ruff_cache htmlcov .coverage dist build
	find . -type d -name __pycache__ -exec rm -rf {} +

# Deploy helpers — require AWS_PROFILE creds and a `terraform apply`d backend/infra/.
# Run from backend/ (terraform output is read from ./infra).
AWS_REGION ?= ap-northeast-2
AWS_PROFILE ?= little-signals-staging
IMAGE_TAG ?= 0.2.0
ECR_REPOSITORY_URL ?= $(shell cd infra && AWS_PROFILE=$(AWS_PROFILE) terraform output -raw ecr_repository_url 2>/dev/null)
STAGING_API_URL ?= https://api-staging.friendlykr.com

_require-ecr-url:
	@if [ -z "$(ECR_REPOSITORY_URL)" ]; then \
	  echo "ERROR: ECR_REPOSITORY_URL is empty. Run 'terraform apply' in backend/infra first, or pass ECR_REPOSITORY_URL=... explicitly."; \
	  exit 1; \
	fi

docker-build:  ## Build the backend Docker image (pinned to linux/amd64 for ECS Fargate).
	docker build --platform linux/amd64 -t little-signals-backend:$(IMAGE_TAG) .

ecr-login: _require-ecr-url  ## Authenticate Docker to AWS ECR.
	aws ecr get-login-password --region $(AWS_REGION) --profile $(AWS_PROFILE) | \
	docker login --username AWS --password-stdin $(ECR_REPOSITORY_URL)

ecr-push: docker-build ecr-login  ## Tag and push the backend image to ECR.
	docker tag little-signals-backend:$(IMAGE_TAG) $(ECR_REPOSITORY_URL):$(IMAGE_TAG)
	docker tag little-signals-backend:$(IMAGE_TAG) $(ECR_REPOSITORY_URL):latest
	docker push $(ECR_REPOSITORY_URL):$(IMAGE_TAG)
	docker push $(ECR_REPOSITORY_URL):latest

smoke-staging:  ## Check staging health and DB readiness.
	curl -fsS "$(STAGING_API_URL)/health"
	curl -fsS "$(STAGING_API_URL)/ready"

smoke-sprint-8a:  ## Run sprint-8a observability smoke against staging.
	./scripts/sprint-8a-smoke.sh
