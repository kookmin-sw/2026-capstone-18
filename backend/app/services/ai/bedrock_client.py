"""Thin async wrapper around AWS Bedrock InvokeModel for Anthropic Claude.

Uses the Anthropic Messages API shape on Bedrock:
  https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-anthropic-claude-messages.html

The call itself is sync (boto3); we run it in an asyncio executor so callers
can `await` it without blocking the event loop.
"""

from __future__ import annotations

import asyncio
import json
from typing import Any, cast

import boto3

from app.config import get_settings


class BedrockError(Exception):
    """Bedrock InvokeModel failed."""


class BedrockClient:
    def __init__(self, raw: Any | None = None, model_id: str | None = None) -> None:
        settings = get_settings()
        self._raw = raw or boto3.client("bedrock-runtime", region_name=settings.aws_bedrock_region)
        self._model_id = model_id or settings.aws_bedrock_model_id

    async def invoke(
        self,
        prompt: str,
        *,
        system: str | None = None,
        max_tokens: int = 1024,
    ) -> str:
        body: dict[str, Any] = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}],
        }
        if system:
            body["system"] = system

        loop = asyncio.get_running_loop()
        try:
            resp = await loop.run_in_executor(
                None,
                lambda: self._raw.invoke_model(
                    modelId=self._model_id,
                    body=json.dumps(body),
                ),
            )
        except Exception as exc:
            raise BedrockError(f"invoke_model failed: {exc}") from exc

        try:
            payload = json.loads(resp["body"].read())
            return cast(str, payload["content"][0]["text"])
        except (KeyError, IndexError, ValueError) as exc:
            raise BedrockError(f"malformed Bedrock response: {exc}") from exc
