"""S3 presigned URL helpers — wraps boto3 sync calls in asyncio.to_thread."""

from __future__ import annotations

import asyncio
from functools import lru_cache
from typing import cast

import boto3

from app.config import get_settings


@lru_cache(maxsize=1)
def _client() -> object:
    settings = get_settings()
    return boto3.client("s3", region_name=settings.aws_region)


async def presign_put(*, bucket: str, key: str, content_length: int, expires_in: int) -> str:
    def _sign() -> str:
        url = _client().generate_presigned_url(  # type: ignore[attr-defined]
            "put_object",
            Params={
                "Bucket": bucket,
                "Key": key,
                "ContentLength": content_length,
                "ServerSideEncryption": "aws:kms",
            },
            ExpiresIn=expires_in,
        )
        return cast(str, url)

    return await asyncio.to_thread(_sign)


async def presign_get(*, bucket: str, key: str, expires_in: int) -> str:
    def _sign() -> str:
        url = _client().generate_presigned_url(  # type: ignore[attr-defined]
            "get_object",
            Params={"Bucket": bucket, "Key": key},
            ExpiresIn=expires_in,
        )
        return cast(str, url)

    return await asyncio.to_thread(_sign)


async def delete_object(*, bucket: str, key: str) -> None:
    def _delete() -> None:
        _client().delete_object(Bucket=bucket, Key=key)  # type: ignore[attr-defined]

    await asyncio.to_thread(_delete)
