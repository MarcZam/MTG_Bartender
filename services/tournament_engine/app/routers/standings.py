"""
POST /standings/compute   — Compute and persist standings after a round.
GET  /standings/{tid}     — Read latest standings from Supabase (passthrough).
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from supabase import Client

from app.core.tiebreakers import rank_players
from app.db.supabase import get_supabase
from app.models.schemas import (
    ComputeStandingsRequest,
    ComputeStandingsResponse,
    PlayerRecord,
    PlayerStanding,
)
from app.routers.pairings import _build_player_records

router = APIRouter(prefix="/standings", tags=["standings"])


@router.post("/compute", response_model=ComputeStandingsResponse)
def compute_standings(
    req: ComputeStandingsRequest,
    db: Client = Depends(get_supabase),
) -> ComputeStandingsResponse:
    tournament_id = str(req.tournament_id)

    # Validate tournament exists
    t_res = db.table("tournaments").select("id, current_round").eq("id", tournament_id).single().execute()
    if not t_res.data:
        raise HTTPException(status_code=404, detail="Tournament not found.")

    if req.after_round > t_res.data["current_round"]:
        raise HTTPException(
            status_code=400,
            detail=f"Round {req.after_round} has not started yet.",
        )

    # Fetch active player IDs
    reg_res = (
        db.table("registrations")
        .select("user_id")
        .eq("tournament_id", tournament_id)
        .not_.in_("status", ["disqualified"])
        .execute()
    )
    active_ids = [UUID(r["user_id"]) for r in reg_res.data]

    if not active_ids:
        raise HTTPException(status_code=400, detail="No active players in tournament.")

    # Build records from all matches up to after_round
    player_records = _build_player_records_up_to_round(
        db, tournament_id, active_ids, req.after_round
    )

    all_players_map: dict[UUID, PlayerRecord] = {p.user_id: p for p in player_records}

    # Rank players using MTG tiebreakers
    ranked = rank_players(player_records, all_players_map)

    standings: list[PlayerStanding] = []
    rows_to_upsert: list[dict] = []

    for rank, (player, omw, pgw, ogw) in enumerate(ranked, start=1):
        standing = PlayerStanding(
            user_id=player.user_id,
            rank=rank,
            points=player.points,
            match_wins=player.match_wins,
            match_losses=player.match_losses,
            match_draws=player.match_draws,
            game_wins=player.game_wins,
            game_losses=player.game_losses,
            game_draws=player.game_draws,
            omw_pct=round(omw, 4),
            ogw_pct=round(ogw, 4),
            pgw_pct=round(pgw, 4),
        )
        standings.append(standing)
        rows_to_upsert.append(
            {
                "tournament_id": tournament_id,
                "user_id": str(player.user_id),
                "after_round": req.after_round,
                "rank": rank,
                "points": player.points,
                "match_wins": player.match_wins,
                "match_losses": player.match_losses,
                "match_draws": player.match_draws,
                "game_wins": player.game_wins,
                "game_losses": player.game_losses,
                "game_draws": player.game_draws,
                "omw_pct": round(omw, 4),
                "ogw_pct": round(ogw, 4),
                "pgw_pct": round(pgw, 4),
            }
        )

    # Upsert standings (idempotent — safe to recompute)
    db.table("standings").upsert(
        rows_to_upsert,
        on_conflict="tournament_id,user_id,after_round",
    ).execute()

    return ComputeStandingsResponse(
        tournament_id=req.tournament_id,
        after_round=req.after_round,
        standings=standings,
    )


@router.get("/{tournament_id}", response_model=ComputeStandingsResponse)
def get_latest_standings(
    tournament_id: UUID,
    db: Client = Depends(get_supabase),
) -> ComputeStandingsResponse:
    """Return the most recently computed standings for a tournament."""
    # Find the latest after_round
    latest_res = (
        db.table("standings")
        .select("after_round")
        .eq("tournament_id", str(tournament_id))
        .order("after_round", desc=True)
        .limit(1)
        .execute()
    )

    if not latest_res.data:
        raise HTTPException(status_code=404, detail="No standings computed yet for this tournament.")

    after_round = latest_res.data[0]["after_round"]

    rows_res = (
        db.table("standings")
        .select("*")
        .eq("tournament_id", str(tournament_id))
        .eq("after_round", after_round)
        .order("rank")
        .execute()
    )

    standings = [
        PlayerStanding(
            user_id=UUID(r["user_id"]),
            rank=r["rank"],
            points=r["points"],
            match_wins=r["match_wins"],
            match_losses=r["match_losses"],
            match_draws=r["match_draws"],
            game_wins=r["game_wins"],
            game_losses=r["game_losses"],
            game_draws=r["game_draws"],
            omw_pct=r["omw_pct"],
            ogw_pct=r["ogw_pct"],
            pgw_pct=r["pgw_pct"],
        )
        for r in rows_res.data
    ]

    return ComputeStandingsResponse(
        tournament_id=tournament_id,
        after_round=after_round,
        standings=standings,
    )


# ── Helpers ───────────────────────────────────────────────────────────────────

def _build_player_records_up_to_round(
    db: Client,
    tournament_id: str,
    active_ids: list[UUID],
    up_to_round: int,
) -> list[PlayerRecord]:
    """Like _build_player_records but only counts matches up to a specific round."""
    records: dict[UUID, PlayerRecord] = {uid: PlayerRecord(user_id=uid) for uid in active_ids}

    match_res = (
        db.table("matches")
        .select("player_a, player_b, result, games_won_a, games_won_b, games_drawn, is_bye, round_number")
        .eq("tournament_id", tournament_id)
        .eq("status", "completed")
        .lte("round_number", up_to_round)
        .execute()
    )

    for m in match_res.data:
        a = UUID(m["player_a"])
        b = UUID(m["player_b"]) if m["player_b"] else None
        result = m["result"]

        if b is None:
            if a in records:
                rec = records[a]
                rec.had_bye = True
                rec.points += 3
                rec.match_wins += 1
                rec.game_wins += 2
            continue

        rec_a = records.get(a)
        rec_b = records.get(b)

        if rec_a and b not in rec_a.opponents:
            rec_a.opponents.append(b)
        if rec_b and a not in rec_b.opponents:
            rec_b.opponents.append(a)

        gwa = m["games_won_a"]
        gwb = m["games_won_b"]
        gwd = m.get("games_drawn", 0)

        if rec_a:
            rec_a.game_wins += gwa
            rec_a.game_losses += gwb
            rec_a.game_draws += gwd
        if rec_b:
            rec_b.game_wins += gwb
            rec_b.game_losses += gwa
            rec_b.game_draws += gwd

        if result == "player_a_wins":
            if rec_a:
                rec_a.points += 3
                rec_a.match_wins += 1
            if rec_b:
                rec_b.match_losses += 1
        elif result == "player_b_wins":
            if rec_b:
                rec_b.points += 3
                rec_b.match_wins += 1
            if rec_a:
                rec_a.match_losses += 1
        elif result == "draw":
            if rec_a:
                rec_a.points += 1
                rec_a.match_draws += 1
            if rec_b:
                rec_b.points += 1
                rec_b.match_draws += 1

    return list(records.values())
