# little-signals backend dev commands.
# Run from the backend/ directory (or `make -C backend <target>` from repo root).

.PHONY: help install run test test-fast lint format typecheck migrate migrate-test \
        db-up db-down db-logs check clean

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
	poetry run alembic upgrade head

migrate-test:  ## Apply Alembic migrations to the test DB.
	DATABASE_URL=$$TEST_DATABASE_URL poetry run alembic upgrade head

db-up:  ## Start the local Postgres + Adminer stack via docker compose.
	docker compose up -d

db-down:  ## Stop the local Postgres + Adminer stack.
	docker compose down

db-logs:  ## Tail the Postgres container logs.
	docker compose logs -f postgres

clean:  ## Remove caches and build artifacts.
	rm -rf .pytest_cache .mypy_cache .ruff_cache htmlcov .coverage dist build
	find . -type d -name __pycache__ -exec rm -rf {} +
