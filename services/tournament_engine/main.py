"""
MTG Bartender — Tournament Engine
FastAPI microservice responsible for:
  - Generating Swiss pairings
  - Computing standings and tiebreakers (OMW%, PGW%, OGW%)
  - Managing round lifecycle
  - Updating ELO player ratings

Authentication: all endpoints require the X-API-Key header matching
the API_SECRET_KEY environment variable. This service should NOT be
exposed directly to the public internet — it is called by Supabase
Edge Functions or your Next.js API routes (server-side only).
"""

from fastapi import Depends, FastAPI, HTTPException, Security, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader

from app.db.supabase import get_settings
from app.models.schemas import HealthResponse
from app.routers import pairings, ratings, rounds, standings

app = FastAPI(
    title="MTG Bartender — Tournament Engine",
    version="2.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# ── CORS ──────────────────────────────────────────────────────────────────────
# Restrict to your own domains in production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten this in production
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── API Key auth ──────────────────────────────────────────────────────────────
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


def verify_api_key(key: str | None = Security(api_key_header)) -> str:
    settings = get_settings()
    if key != settings.api_secret_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API key.",
        )
    return key


# ── Routers ───────────────────────────────────────────────────────────────────
app.include_router(pairings.router, dependencies=[Depends(verify_api_key)])
app.include_router(standings.router, dependencies=[Depends(verify_api_key)])
app.include_router(rounds.router, dependencies=[Depends(verify_api_key)])
app.include_router(ratings.router, dependencies=[Depends(verify_api_key)])


# ── Health check (no auth required) ──────────────────────────────────────────
@app.get("/health", response_model=HealthResponse, tags=["meta"])
def health() -> HealthResponse:
    return HealthResponse()
