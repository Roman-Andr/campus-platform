"""Opt-in Android acceptance of an exchange over real API, PostgreSQL and RustFS.

CAMPUS_RUN_EXCHANGE_CLIENT=1 uv run pytest tests/test_exchange_client.py -s
Requires Docker, a running Android emulator and Flutter/adb on PATH.
"""

import asyncio
import json
import os
from pathlib import Path

import pytest
import uvicorn

from campus.core.storage import Storage
from tests.test_identity import DEVICE, Auth
from tests.test_listings import owner, places
from tests.test_photos import rustfs, storage
from tests.test_profile import Account, Places, auth, moscow_profile

__all__ = ["auth", "owner", "places", "rustfs", "storage"]
RUN_CLIENT = os.environ.get("CAMPUS_RUN_EXCHANGE_CLIENT") == "1"
APP = Path(__file__).resolve().parents[2] / "app"
PORT = 18043


async def exchanger(
    auth: Auth, places: Places, email: str, first_name: str, last_name: str
) -> Account:
    account = Account(
        auth,
        await auth.login(
            email=email,
            first_name=first_name,
            last_name=last_name,
        ),
    )
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


@pytest.mark.skipif(not RUN_CLIENT, reason="opt-in Android acceptance")
async def test_three_user_exchange_client(
    auth: Auth,
    owner: Account,
    places: Places,
    storage: Storage,
    tmp_path: Path,
) -> None:
    # A configured empty photo storage keeps the listing gallery at 200.
    assert storage.settings.s3_bucket
    first = await exchanger(auth, places, "dana@university.example", "Dana", "Doe")
    second = await exchanger(auth, places, "egor@university.example", "Egor", "Petrov")
    defines = tmp_path / "client.json"
    defines.write_text(
        json.dumps(
            {
                "CAMPUS_API_URL": f"http://127.0.0.1:{PORT}",
                "CAMPUS_TEST_OWNER_REFRESH": owner.tokens["refresh_token"],
                "CAMPUS_TEST_FIRST_REFRESH": first.tokens["refresh_token"],
                "CAMPUS_TEST_SECOND_REFRESH": second.tokens["refresh_token"],
                "CAMPUS_TEST_DEVICE": DEVICE,
            }
        )
    )
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
        reverse = await asyncio.create_subprocess_exec(
            "adb",
            "reverse",
            f"tcp:{PORT}",
            f"tcp:{PORT}",
        )
        assert await reverse.wait() == 0
        process = await asyncio.create_subprocess_exec(
            "flutter",
            "test",
            "integration_test/exchange_test.dart",
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
