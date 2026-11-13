"""Liveness endpoint."""

from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel

# A plain APIRoute: probes and monitoring are not clients, so the endpoint
# needs no client headers and no database.
router = APIRouter(tags=["system"])


class Health(BaseModel):
    """Liveness of the API process."""

    status: Literal["ok"] = "ok"


@router.get("/health", summary="Check that the API is alive")
async def get_health() -> Health:
    """Return 200 while the API process is able to serve requests."""
    return Health()
