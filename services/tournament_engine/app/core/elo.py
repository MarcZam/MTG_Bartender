"""
ELO rating system for MTG Bartender.

Standard ELO with K=32 (used by FIDE for active players and common
in competitive card game circuits).

Ratings start at 1200. A win against an equal-rated opponent yields ~+16.
"""

from __future__ import annotations

from uuid import UUID

from app.models.schemas import MatchResult, PlayerRecord

K_FACTOR = 32
STARTING_RATING = 1200


def expected_score(rating_a: int, rating_b: int) -> float:
    """Expected score for player A against player B (0.0 – 1.0)."""
    return 1 / (1 + 10 ** ((rating_b - rating_a) / 400))


def new_ratings(
    rating_a: int,
    rating_b: int,
    result: MatchResult,
) -> tuple[int, int]:
    """
    Compute updated ELO ratings after a match.

    Returns (new_rating_a, new_rating_b).
    """
    score_map = {
        MatchResult.player_a_wins: (1.0, 0.0),
        MatchResult.player_b_wins: (0.0, 1.0),
        MatchResult.draw: (0.5, 0.5),
    }
    score_a, score_b = score_map[result]

    ea = expected_score(rating_a, rating_b)
    eb = expected_score(rating_b, rating_a)

    new_a = round(rating_a + K_FACTOR * (score_a - ea))
    new_b = round(rating_b + K_FACTOR * (score_b - eb))

    return new_a, new_b


def apply_tournament_ratings(
    match_results: list[dict],
    current_ratings: dict[UUID, int],
) -> dict[UUID, int]:
    """
    Apply ELO updates for every completed match in a tournament.

    Args:
        match_results: list of dicts with keys:
                       player_a (UUID), player_b (UUID | None), result (MatchResult)
        current_ratings: {user_id: current_rating}

    Returns:
        Updated ratings dict. Players not in current_ratings start at STARTING_RATING.
    """
    ratings = dict(current_ratings)

    for match in match_results:
        player_a: UUID = match["player_a"]
        player_b: UUID | None = match.get("player_b")
        result: MatchResult = match["result"]

        if player_b is None:
            # Bye — no rating change.
            continue

        ra = ratings.get(player_a, STARTING_RATING)
        rb = ratings.get(player_b, STARTING_RATING)

        new_a, new_b = new_ratings(ra, rb, result)
        ratings[player_a] = new_a
        ratings[player_b] = new_b

    return ratings
