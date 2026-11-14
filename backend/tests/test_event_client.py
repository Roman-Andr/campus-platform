"""Opt-in Android acceptance of event signup over the real API.

CAMPUS_RUN_EVENT_CLIENT=1 uv run pytest tests/test_event_client.py -s
Requires a running Android emulator and Flutter/adb on PATH.
"""

import asyncio
import json
import os
from pathlib import Path

import pytest
import uvicorn

from tests.test_identity import DEVICE, Auth
from tests.test_listing_waitlist import queuer
from tests.test_listings import borrower, owner
from tests.test_profile import Account, Places, auth, places

__all__ = ["auth", "borrower", "owner", "places"]
RUN_CLIENT = os.environ.get("CAMPUS_RUN_EVENT_CLIENT") == "1"
APP = Path(__file__).resolve().parents[2] / "app"
PORT = 18042


@pytest.mark.skipif(not RUN_CLIENT, reason="opt-in Android acceptance")
async def test_two_user_event_client(
    auth: Auth, owner: Account, borrower: Account, places: Places, tmp_path: Path
) -> None:
    queued = await queuer(auth, places, 52)
    defines = tmp_path / "client.json"
    defines.write_text(
        json.dumps(
            {
                "CAMPUS_API_URL": f"http://127.0.0.1:{PORT}",
                "CAMPUS_TEST_OWNER_REFRESH": owner.tokens["refresh_token"],
                "CAMPUS_TEST_PARTICIPANT_REFRESH": borrower.tokens["refresh_token"],
                "CAMPUS_TEST_QUEUED_REFRESH": queued.tokens["refresh_token"],
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
            "integration_test/event_test.dart",
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
