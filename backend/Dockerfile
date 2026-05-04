# Stage 1: build dependencies
FROM python:3.12-slim AS builder

ENV POETRY_VERSION=2.3.2 \
    POETRY_HOME=/opt/poetry \
    POETRY_NO_INTERACTION=1 \
    POETRY_VIRTUALENVS_IN_PROJECT=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends curl build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://install.python-poetry.org | python3 -
ENV PATH="$POETRY_HOME/bin:$PATH"

WORKDIR /app
COPY pyproject.toml poetry.lock ./
RUN poetry install --only main --no-root

# Stage 2: runtime
FROM python:3.12-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/app/.venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash app

WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY --chown=app:app app/ ./app/

USER app
EXPOSE 8000

# Sprint 1 will add a real entrypoint; for now this is a placeholder
# that proves the image builds and runs.
CMD ["python", "-c", "print('little-signals backend container — replace CMD in Sprint 1')"]
