"""Opt-in Android acceptance of group purchase shares over the real API.

CAMPUS_RUN_PURCHASE_CLIENT=1 uv run pytest tests/test_purchase_client.py -s
Requires Docker, a running Android emulator and Flutter/adb on PATH.
"""

import asyncio
import json
import os
from pathlib import Path
from urllib.parse import urlsplit

import pytest
import uvicorn

from campus.core.storage import Storage
from tests.test_identity import DEVICE, Auth
from tests.test_listings import borrower, owner
from tests.test_photos import rustfs, storage
from tests.test_profile import Account, auth, places

__all__ = ["auth", "borrower", "owner", "places", "rustfs", "storage"]
RUN_CLIENT = os.environ.get("CAMPUS_RUN_PURCHASE_CLIENT") == "1"
APP = Path(__file__).resolve().parents[2] / "app"
PORT = 18043


async def adb_reverse(port: int) -> None:
    process = await asyncio.create_subprocess_exec(
        "adb", "reverse", f"tcp:{port}", f"tcp:{port}"
    )
    assert await process.wait() == 0


@pytest.mark.skipif(not RUN_CLIENT, reason="opt-in Android acceptance")
async def test_two_user_purchase_client(
    auth: Auth,
    owner: Account,
    borrower: Account,
    storage: Storage,
    tmp_path: Path,
) -> None:
    defines = tmp_path / "client.json"
    defines.write_text(
        json.dumps(
            {
                "CAMPUS_API_URL": f"http://127.0.0.1:{PORT}",
                "CAMPUS_TEST_OWNER_REFRESH": owner.tokens["refresh_token"],
                "CAMPUS_TEST_PARTICIPANT_REFRESH": borrower.tokens["refresh_token"],
                "CAMPUS_TEST_DEVICE": DEVICE,
            }
        )
    )
    # Signed storage links keep the host and port, so Android reaches the
    # same RustFS address through adb reverse.
    storage_port = urlsplit(storage.settings.s3_endpoint_url or "").port
    assert storage_port is not None
    # The fixture owns the lifespan; Uvicorn only exposes it to Android.
    server = uvicorn.Server(
        uvicorn.Config(
            auth.app,
            host="127.0.0.1",
            port=PORT,
            lifespan="off",
            log_level="warning",
        )
    )
    serving = asyncio.create_task(server.serve())
    try:
        while not server.started:
            if serving.done():
                await serving
            await asyncio.sleep(0.05)
        await adb_reverse(PORT)
        await adb_reverse(storage_port)
        process = await asyncio.create_subprocess_exec(
            "flutter",
            "test",
            "integration_test/purchase_test.dart",
            "-d",
            "emulator-5554",
            f"--dart-define-from-file={defines}",
            cwd=APP,
            env={
                **os.environ,
                "GRADLE_OPTS": (
                    "-Dorg.gradle.jvmargs=-Xmx1536m -Dorg.gradle.workers.max=2"
                ),
            },
        )
        try:
            assert await asyncio.wait_for(process.wait(), timeout=900) == 0
        finally:
            if process.returncode is None:
                process.terminate()
                await process.wait()
    finally:
        server.should_exit = True
        await serving
