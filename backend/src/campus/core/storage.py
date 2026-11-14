"""S3 protocol adapter; buckets must be private and provisioned externally."""

import asyncio
import contextlib
from collections.abc import Callable
from typing import TYPE_CHECKING, Any

import boto3
from botocore.config import Config

if TYPE_CHECKING:
    from mypy_boto3_s3 import S3Client

from campus.core.config import Settings


async def storage_io[T](operation: Callable[..., T], *args: Any) -> T:
    """Finish in-flight S3 operations before releasing transaction locks.

    Cancelling a bare to_thread releases locks while its thread can still
    write objects. A concurrent expiry could then delete the row first.
    """
    task = asyncio.create_task(asyncio.to_thread(operation, *args))
    try:
        return await asyncio.shield(task)
    except asyncio.CancelledError:
        while not task.done():
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await asyncio.shield(task)
        with contextlib.suppress(Exception):
            task.result()
        raise


class Storage:
    def __init__(self, settings: Settings) -> None:
        if (
            not settings.s3_endpoint_url
            or not settings.s3_access_key
            or not settings.s3_secret_key
        ):
            raise RuntimeError("S3 storage is not configured")
        self.settings = settings
        self.client: S3Client = boto3.client(
            "s3",
            endpoint_url=settings.s3_endpoint_url,
            aws_access_key_id=settings.s3_access_key.get_secret_value(),
            aws_secret_access_key=settings.s3_secret_key.get_secret_value(),
            region_name=settings.s3_region,
            config=Config(
                signature_version="s3v4",
                s3={"addressing_style": "path"},
                connect_timeout=5,
                read_timeout=30,
                retries={"max_attempts": 3},
            ),
        )

    def upload(self, key: str) -> dict[str, Any]:
        return self.client.generate_presigned_post(
            self.settings.s3_bucket,
            key,
            Conditions=[["content-length-range", 1, self.settings.photo_max_bytes]],
            ExpiresIn=int(self.settings.photo_upload_ttl.total_seconds()),
        )

    def read(self, key: str) -> bytes:
        response = self.client.get_object(Bucket=self.settings.s3_bucket, Key=key)
        with response["Body"] as stream:
            return stream.read(self.settings.photo_max_bytes + 1)

    def write(self, key: str, data: bytes) -> None:
        self.client.put_object(
            Bucket=self.settings.s3_bucket,
            Key=key,
            Body=data,
            ContentType="image/jpeg",
            CacheControl="private, no-store",
        )

    def delete(self, key: str) -> None:
        self.client.delete_object(Bucket=self.settings.s3_bucket, Key=key)

    def url(self, key: str) -> str:
        return self.client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.settings.s3_bucket, "Key": key},
            ExpiresIn=int(self.settings.photo_read_ttl.total_seconds()),
        )
