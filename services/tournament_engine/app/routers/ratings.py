"""
POST /ratings/update — Update ELO ratings for all players in a completed tournament.

Called once after a tournament reaches status = 'completed'.
Reads all completed matches, applies ELO deltas, and upserts player_ratings.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from supabase import Client

from app.core.elo import STARTING_RATING, apply_tournament_ratings
from app.db.supabase import get_supabase
from app.models.schemas import MatchResult, UpdateRatingsRequest, UpdateRatingsResponse

router = APIRouter(prefix="/ratings", tags=["ratings"])


@router.post("/update", response_model=UpdateRatingsResponse)
def update_ratings(
    req: UpdateRatingsRequest,
    db: Client = Depends(get_supabase),
) -> UpdateRatingsResponse:
    tournament_id = str(req.tournament_id)

    # Validate tournament is complete
    t_res = (
        db.table("tournaments")
        .select("id, status, format, event_id")
        .eq("id", tournament_id)
        .single()
        .execute()
    )
    if not t_res.data:
        raise HTTPException(status_code=404, detail="Tournament not found.")

    if t_res.data["status"] != "completed":
        raise HTTPException(
            status_code=400,
            detail="Ratings can only be updated for completed tournaments.",
        )

    fmt = t_res.data["format"]

    # Fetch the event to get game_system
    event_res = (
        db.table("events")
        .select("game_system")
        .eq("id", t_res.data["event_id"])
        .single()
        .execute()
    )
    game_system = event_res.data["game_system"] if event_res.data else "mtg"

    # Fetch all completed matches
    match_res = (
        db.table("matches")
        .select("player_a, player_b, result")
        .eq("tournament_id", tournament_id)
        .eq("status", "completed")
        .execute()
    )

    match_results = [
        {
            "player_a": UUID(m["player_a"]),
            "player_b": UUID(m["player_b"]) if m["player_b"] else None,
            "result": MatchResult(m["result"]),
        }
        for m in match_res.data
        if m["result"] is not None
    ]

    if not match_results:
        return UpdateRatingsResponse(tournament_id=req.tournament_id, players_updated=0)

    # Collect all involved player IDs
    player_ids: set[UUID] = set()
    for m in match_results:
        player_ids.add(m["player_a"])
        if m["player_b"]:
            player_ids.add(m["player_b"])

    player_id_strs = [str(pid) for pid in player_ids]

    # Fetch current ratings for these players (format-specific)
    ratings_res = (
        db.table("player_ratings")
        .select("user_id, rating")
        .in_("user_id", player_id_strs)
        .eq("game_system", game_system)
        .eq("format", fmt)
        .execute()
    )

    current_ratings: dict[UUID, int] = {
        UUID(r["user_id"]): r["rating"] for r in ratings_res.data
    }

    # Apply ELO updates
    updated_ratings = apply_tournament_ratings(match_results, current_ratings)

    # Upsert player_ratings rows
    upsert_rows = [
        {
            "user_id": str(uid),
            "game_system": game_system,
            "format": fmt,
            "rating": new_rating,
            "peak_rating": max(new_rating, current_ratings.get(uid, STARTING_RATING)),
        }
        for uid, new_rating in updated_ratings.items()
    ]

    # Increment games_played separately to avoid overwriting it
    db.table("player_ratings").upsert(
        upsert_rows,
        on_conflict="user_id,game_system,format",
    ).execute()

    # Increment games_played for each player
    for pid in player_ids:
        played = sum(
            1
            for m in match_results
            if m["player_b"] is not None  # byes don't count
            and (m["player_a"] == pid or m["player_b"] == pid)
        )
        if played > 0:
            db.rpc(
                "increment_games_played",
                {"p_user_id": str(pid), "p_game_system": game_system, "p_format": fmt, "p_increment": played},
            ).execute()

    return UpdateRatingsResponse(
        tournament_id=req.tournament_id,
        players_updated=len(updated_ratings),
    )
