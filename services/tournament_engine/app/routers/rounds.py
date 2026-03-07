"""
POST /rounds/complete          — Mark a round as complete and trigger standings.
POST /rounds/report-result     — Submit a match result (called by frontend relay).
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from supabase import Client

from app.db.supabase import get_supabase
from app.models.schemas import (
    CompleteRoundRequest,
    CompleteRoundResponse,
    ComputeStandingsRequest,
    ReportResultRequest,
    ReportResultResponse,
)

router = APIRouter(prefix="/rounds", tags=["rounds"])


@router.post("/report-result", response_model=ReportResultResponse)
def report_result(
    req: ReportResultRequest,
    db: Client = Depends(get_supabase),
) -> ReportResultResponse:
    """
    Submit a match result.
    In production, the frontend calls Supabase directly (RLS allows players
    to update their own matches). This endpoint exists for judge overrides
    and for testing without a frontend.
    """
    match_id = str(req.match_id)

    m_res = db.table("matches").select("id, status, is_bye").eq("id", match_id).single().execute()
    if not m_res.data:
        raise HTTPException(status_code=404, detail="Match not found.")

    match = m_res.data
    if match["status"] in ("completed", "bye"):
        raise HTTPException(status_code=400, detail="Match is already finalised.")

    db.table("matches").update(
        {
            "games_won_a": req.games_won_a,
            "games_won_b": req.games_won_b,
            "games_drawn": req.games_drawn,
            "result": req.result.value,
            "status": "completed",
        }
    ).eq("id", match_id).execute()

    return ReportResultResponse(match_id=req.match_id, result=req.result)


@router.post("/complete", response_model=CompleteRoundResponse)
def complete_round(
    req: CompleteRoundRequest,
    db: Client = Depends(get_supabase),
) -> CompleteRoundResponse:
    """
    Attempt to close a round.
    - Checks that all matches in the round are completed.
    - If all done: marks round as 'completed', triggers standings computation,
      and checks if the tournament itself should be marked completed.
    - If pending matches remain: returns the count so the caller knows.
    """
    tournament_id = str(req.tournament_id)

    # Check all matches in this round
    match_res = (
        db.table("matches")
        .select("id, status")
        .eq("tournament_id", tournament_id)
        .eq("round_number", req.round_number)
        .execute()
    )

    if not match_res.data:
        raise HTTPException(
            status_code=404,
            detail=f"No matches found for round {req.round_number}.",
        )

    pending = [m for m in match_res.data if m["status"] not in ("completed", "bye")]

    if pending:
        return CompleteRoundResponse(
            tournament_id=req.tournament_id,
            round_number=req.round_number,
            completed=False,
            pending_matches=len(pending),
        )

    # Mark round as completed
    db.table("tournament_rounds").update({"status": "completed"}).eq(
        "tournament_id", tournament_id
    ).eq("round_number", req.round_number).execute()

    # Trigger standings computation (inline — same process)
    from app.routers.standings import compute_standings  # avoid circular import at module level

    compute_standings(
        ComputeStandingsRequest(
            tournament_id=req.tournament_id,
            after_round=req.round_number,
        ),
        db,
    )

    # Check if the tournament is finished
    t_res = (
        db.table("tournaments")
        .select("current_round, total_rounds, top_cut")
        .eq("id", tournament_id)
        .single()
        .execute()
    )
    tournament = t_res.data
    total_rounds = tournament["total_rounds"] or 0

    if req.round_number >= total_rounds and tournament.get("top_cut", 0) == 0:
        # No top cut — tournament is complete after swiss.
        db.table("tournaments").update({"status": "completed"}).eq("id", tournament_id).execute()
    elif req.round_number >= total_rounds:
        # Swiss done, top cut begins.
        db.table("tournaments").update({"status": "top_cut"}).eq("id", tournament_id).execute()

    return CompleteRoundResponse(
        tournament_id=req.tournament_id,
        round_number=req.round_number,
        completed=True,
        pending_matches=0,
    )
