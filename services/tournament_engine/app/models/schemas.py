from __future__ import annotations

from enum import Enum
from uuid import UUID

from pydantic import BaseModel, Field


# ── Enums (mirror the DB enums for type safety) ───────────────────────────────

class MatchResult(str, Enum):
    player_a_wins = "player_a_wins"
    player_b_wins = "player_b_wins"
    draw = "draw"


class RegistrationStatus(str, Enum):
    registered = "registered"
    checked_in = "checked_in"
    dropped = "dropped"
    disqualified = "disqualified"


class TournamentStatus(str, Enum):
    scheduled = "scheduled"
    registration_open = "registration_open"
    registration_closed = "registration_closed"
    in_progress = "in_progress"
    top_cut = "top_cut"
    completed = "completed"
    cancelled = "cancelled"


# ── Internal domain objects (not exposed via API) ─────────────────────────────

class PlayerRecord(BaseModel):
    """Aggregated stats for a player within a tournament, built from match history."""

    user_id: UUID
    points: int = 0           # 3=win, 1=draw, 0=loss
    match_wins: int = 0
    match_losses: int = 0
    match_draws: int = 0
    game_wins: int = 0
    game_losses: int = 0
    game_draws: int = 0
    opponents: list[UUID] = Field(default_factory=list)  # ordered by round
    had_bye: bool = False


# ── Pairing request / response ────────────────────────────────────────────────

class GeneratePairingsRequest(BaseModel):
    tournament_id: UUID
    round_number: int = Field(ge=1)


class Pairing(BaseModel):
    player_a: UUID
    player_b: UUID | None  # None = bye for player_a
    table_number: int


class GeneratePairingsResponse(BaseModel):
    tournament_id: UUID
    round_number: int
    pairings: list[Pairing]
    round_id: UUID  # the newly created tournament_rounds row


# ── Match result reporting ────────────────────────────────────────────────────

class ReportResultRequest(BaseModel):
    match_id: UUID
    games_won_a: int = Field(ge=0)
    games_won_b: int = Field(ge=0)
    games_drawn: int = Field(ge=0, default=0)
    result: MatchResult


class ReportResultResponse(BaseModel):
    match_id: UUID
    result: MatchResult
    updated: bool = True


# ── Round completion ──────────────────────────────────────────────────────────

class CompleteRoundRequest(BaseModel):
    tournament_id: UUID
    round_number: int = Field(ge=1)


class CompleteRoundResponse(BaseModel):
    tournament_id: UUID
    round_number: int
    completed: bool
    pending_matches: int  # 0 = all done, >0 = still waiting on results


# ── Standings ─────────────────────────────────────────────────────────────────

class ComputeStandingsRequest(BaseModel):
    tournament_id: UUID
    after_round: int = Field(ge=1)


class PlayerStanding(BaseModel):
    user_id: UUID
    rank: int
    points: int
    match_wins: int
    match_losses: int
    match_draws: int
    game_wins: int
    game_losses: int
    game_draws: int
    omw_pct: float  # opponent match-win %  (tiebreaker 1)
    ogw_pct: float  # opponent game-win %   (tiebreaker 2)
    pgw_pct: float  # player game-win %     (tiebreaker 3)


class ComputeStandingsResponse(BaseModel):
    tournament_id: UUID
    after_round: int
    standings: list[PlayerStanding]


# ── ELO update ────────────────────────────────────────────────────────────────

class UpdateRatingsRequest(BaseModel):
    tournament_id: UUID


class UpdateRatingsResponse(BaseModel):
    tournament_id: UUID
    players_updated: int


# ── Health ────────────────────────────────────────────────────────────────────

class HealthResponse(BaseModel):
    status: str = "ok"
    version: str = "2.0.0"
