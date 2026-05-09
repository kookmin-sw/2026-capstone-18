"""FastAPI factory for the ML demo service."""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI

from AI.serve.router import router
from AI.serve.settings import Settings


@asynccontextmanager
async def _lifespan(app: FastAPI):
    settings = Settings()
    if not settings.onnx_path.exists():
        raise RuntimeError(f"ONNX model not found at {settings.onnx_path}")
    yield


def build_app() -> FastAPI:
    app = FastAPI(
        title="Little Signals ML Demo",
        version="0.1.0",
        lifespan=_lifespan,
    )
    app.include_router(router)
    return app


app = build_app()
