"""
MTG tiebreaker calculations.

Standard tiebreaker order (DCI rules):
  1. OMW%  — Opponent Match-Win percentage
  2. PGW%  — Player Game-Win percentage
  3. OGW%  — Opponent Game-Win percentage

All percentages have a minimum floor of 33.33% (0.3333) per WotC rules.
This prevents players who faced many byes from being unfairly penalised.

Reference: https://blogs.magicjudges.org/rules/mtr-appendix-c/
"""

from __future__ import annotations

from uuid import UUID

from app.models.schemas import PlayerRecord

# WotC mandated floor for all tiebreaker percentages.
MIN_PCT = 1 / 3


def compute_omw_pct(player: PlayerRecord, all_players: dict[UUID, PlayerRecord]) -> float:
    """
    Opponent Match-Win percentage.
    Average of each opponent's match-win %, floored at MIN_PCT.
    Bye opponents are excluded from the calculation.
    """
    pcts: list[float] = []
    for opp_id in player.opponents:
        opp = all_players.get(opp_id)
        if opp is None:
            continue  # opponent not found (shouldn't happen)
        total = opp.match_wins + opp.match_losses + opp.match_draws
        raw = opp.match_wins / total if total > 0 else 0.0
        pcts.append(max(raw, MIN_PCT))

    return sum(pcts) / len(pcts) if pcts else MIN_PCT


def compute_pgw_pct(player: PlayerRecord) -> float:
    """
    Player Game-Win percentage.
    Games won / total games played, floored at MIN_PCT.
    """
    total = player.game_wins + player.game_losses + player.game_draws
    if total == 0:
        return MIN_PCT
    return max(player.game_wins / total, MIN_PCT)


def compute_ogw_pct(player: PlayerRecord, all_players: dict[UUID, PlayerRecord]) -> float:
    """
    Opponent Game-Win percentage.
    Average of each opponent's PGW%, floored at MIN_PCT.
    Bye opponents are excluded.
    """
    pcts: list[float] = []
    for opp_id in player.opponents:
        opp = all_players.get(opp_id)
        if opp is None:
            continue
        pcts.append(compute_pgw_pct(opp))

    return sum(pcts) / len(pcts) if pcts else MIN_PCT


def rank_players(
    players: list[PlayerRecord],
    all_players: dict[UUID, PlayerRecord],
) -> list[tuple[PlayerRecord, float, float, float]]:
    """
    Return players sorted by (points DESC, omw DESC, pgw DESC, ogw DESC).
    Each tuple is (player, omw_pct, pgw_pct, ogw_pct).
    """
    scored = [
        (
            p,
            compute_omw_pct(p, all_players),
            compute_pgw_pct(p),
            compute_ogw_pct(p, all_players),
        )
        for p in players
    ]
    scored.sort(
        key=lambda x: (x[0].points, x[1], x[2], x[3]),
        reverse=True,
    )
    return scored
