"""Unit tests for BedrockClient wrapper."""

from __future__ import annotations

import json
from typing import Any
from unittest.mock import MagicMock

import pytest

from app.services.ai.bedrock_client import BedrockClient, BedrockError


def _fake_invoke_response(text: str) -> dict[str, Any]:
    body_dict = {"content": [{"type": "text", "text": text}]}
    body = MagicMock()
    body.read.return_value = json.dumps(body_dict).encode("utf-8")
    return {"body": body, "ResponseMetadata": {"HTTPStatusCode": 200}}


@pytest.mark.asyncio
async def test_invoke_returns_text_from_anthropic_response() -> None:
    raw_client = MagicMock()
    raw_client.invoke_model.return_value = _fake_invoke_response("Hello 안녕")
    client = BedrockClient(raw=raw_client, model_id="model-x")

    result = await client.invoke("user prompt", system="sys", max_tokens=100)

    assert result == "Hello 안녕"
    args, kwargs = raw_client.invoke_model.call_args
    assert kwargs["modelId"] == "model-x"
    body = json.loads(kwargs["body"])
    assert body["max_tokens"] == 100
    assert body["system"] == "sys"
    assert body["messages"] == [{"role": "user", "content": "user prompt"}]


@pytest.mark.asyncio
async def test_invoke_raises_on_client_exception() -> None:
    raw_client = MagicMock()
    raw_client.invoke_model.side_effect = RuntimeError("throttled")
    client = BedrockClient(raw=raw_client, model_id="model-x")

    with pytest.raises(BedrockError) as exc:
        await client.invoke("p", max_tokens=10)
    assert "throttled" in str(exc.value)


@pytest.mark.asyncio
async def test_invoke_no_system_omits_field() -> None:
    raw_client = MagicMock()
    raw_client.invoke_model.return_value = _fake_invoke_response("ok")
    client = BedrockClient(raw=raw_client, model_id="m")

    await client.invoke("p", max_tokens=10)
    body = json.loads(raw_client.invoke_model.call_args.kwargs["body"])
    assert "system" not in body
