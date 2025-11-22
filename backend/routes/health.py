from __future__ import annotations

from fastapi import APIRouter
from ..schemas import HealthOut

router = APIRouter(prefix="", tags=["health"])


@router.get("/health", response_model=HealthOut)
def health() -> HealthOut:
	return HealthOut(ok=True, version="0.1.0")


