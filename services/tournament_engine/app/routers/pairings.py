"""
POST /pairings/generate

Generates Swiss pairings for the next round of a tournament.

Steps:
  1. Validate tournament exists and is in a runnable state.
  2. Fetch all active (checked_in) registrations.
  3. Fetch all completed matches to reconstruct player records.
  4. Run the Swiss algorithm.
  5. Create a tournament_rounds row (status = 'active').
  6. Insert match rows into the matches table.
  7. Update tournament.current_round.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from supabase import Client

from app.core.swiss import calculate_total_rounds, generate_swiss_pairings
from app.db.supabase import get_supabase
from app.models.schemas import (
    GeneratePairingsRequest,
    GeneratePairingsResponse,
    Pairing,
    PlayerRecord,
)

router = APIRouter(prefix="/pairings", tags=["pairings"])


@router.post("/generate", response_model=GeneratePairingsResponse)
def generate_pairings(
    req: GeneratePairingsRequest,
    db: Client = Depends(get_supabase),
) -> GeneratePairingsResponse:
    tournament_id = str(req.tournament_id)

    # 1. Fetch tournament
    t_res = db.table("tournaments").select("*").eq("id", tournament_id).single().execute()
    if not t_res.data:
        raise HTTPException(status_code=404, detail="Tournament not found.")

    tournament = t_res.data
    allowed_statuses = {"registration_closed", "in_progress"}
    if tournament["status"] not in allowed_statuses:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot generate pairings for a tournament with status '{tournament['status']}'.",
        )

    expected_round = tournament["current_round"] + 1
    if req.round_number != expected_round:
        raise HTTPException(
            status_code=400,
            detail=f"Expected round {expected_round}, got {req.round_number}.",
        )

    # 2. Fetch active registrations
    reg_res = (
        db.table("registrations")
        .select("user_id, status")
        .eq("tournament_id", tournament_id)
        .in_("status", ["checked_in", "registered"])
        .execute()
    )
    active_user_ids: list[UUID] = [UUID(r["user_id"]) for r in reg_res.data]

    if len(active_user_ids) < 2:
        raise HTTPException(status_code=400, detail="Need at least 2 active players.")

    # 3. Reconstruct player records from completed matches
    player_records = _build_player_records(db, tournament_id, active_user_ids)

    # 4. Auto-calculate total_rounds if not set
    if tournament["total_rounds"] is None:
        total = calculate_total_rounds(len(active_user_ids))
        db.table("tournaments").update({"total_rounds": total}).eq("id", tournament_id).execute()

    # 5. Run Swiss algorithm
    pairings = generate_swiss_pairings(player_records, req.round_number)

    # 6. Create tournament_rounds row
    round_res = (
        db.table("tournament_rounds")
        .insert(
            {
                "tournament_id": tournament_id,
                "round_number": req.round_number,
                "status": "active",
            }
        )
        .execute()
    )
    round_id = UUID(round_res.data[0]["id"])

    # 7. Insert match rows
    match_rows = [
        {
            "tournament_id": tournament_id,
            "round_id": str(round_id),
            "round_number": req.round_number,
            "table_number": p.table_number,
            "player_a": str(p.player_a),
            "player_b": str(p.player_b) if p.player_b else None,
            "status": "bye" if p.player_b is None else "pending",
            # Byes are auto-wins — pre-fill result.
            "result": "player_a_wins" if p.player_b is None else None,
            "games_won_a": 2 if p.player_b is None else 0,
            "games_won_b": 0,
        }
        for p in pairings
    ]
    db.table("matches").insert(match_rows).execute()

    # 8. Advance tournament status and round counter
    new_status = "in_progress" if tournament["status"] == "registration_closed" else tournament["status"]
    db.table("tournaments").update(
        {"current_round": req.round_number, "status": new_status}
    ).eq("id", tournament_id).execute()

    return GeneratePairingsResponse(
        tournament_id=req.tournament_id,
        round_number=req.round_number,
        pairings=pairings,
        round_id=round_id,
    )


# ── Helpers ───────────────────────────────────────────────────────────────────

def _build_player_records(
    db: Client,
    tournament_id: str,
    active_user_ids: list[UUID],
) -> list[PlayerRecord]:
    """Build PlayerRecord objects from completed match history."""

    records: dict[UUID, PlayerRecord] = {
        uid: PlayerRecord(user_id=uid) for uid in active_user_ids
    }

    match_res = (
        db.table("matches")
        .select("player_a, player_b, result, games_won_a, games_won_b, games_drawn, is_bye")
        .eq("tournament_id", tournament_id)
        .eq("status", "completed")
        .execute()
    )

    for m in match_res.data:
        a = UUID(m["player_a"])
        b = UUID(m["player_b"]) if m["player_b"] else None
        result = m["result"]

        if b is None:
            # Bye
            if a in records:
                rec = records[a]
                rec.had_bye = True
                rec.points += 3
                rec.match_wins += 1
                rec.game_wins += 2
            continue

        rec_a = records.get(a)
        rec_b = records.get(b)

        # Track opponents (for rematch avoidance and tiebreaker calc)
        if rec_a and b not in rec_a.opponents:
            rec_a.opponents.append(b)
        if rec_b and a not in rec_b.opponents:
            rec_b.opponents.append(a)

        # Accumulate game scores
        gwa, gwb, gwd = m["games_won_a"], m["games_won_b"], m.get("games_drawn", 0)
        if rec_a:
            rec_a.game_wins += gwa
            rec_a.game_losses += gwb
            rec_a.game_draws += gwd
        if rec_b:
            rec_b.game_wins += gwb
            rec_b.game_losses += gwa
            rec_b.game_draws += gwd

        # Accumulate match results
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
