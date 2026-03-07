"""
Swiss pairing algorithm.

Rules:
  - Players are grouped by current match points (3=win, 1=draw, 0=loss).
  - Within each group, players are shuffled (randomises who sits at table 1).
  - Greedy pairing: highest-ranked unpaired player is matched with the
    highest-ranked available opponent they have NOT played before.
  - If no rematch-free opponent exists, rematches are allowed (last resort).
  - If an odd player remains after all groups are processed, they receive a bye.
    The bye goes to the player with the fewest points who has not yet had a bye.
  - total_rounds for swiss = ceil(log2(player_count)) — standard MTG formula.
"""

from __future__ import annotations

import math
import random
from uuid import UUID

from app.models.schemas import Pairing, PlayerRecord


# ── Public interface ──────────────────────────────────────────────────────────

def generate_swiss_pairings(
    players: list[PlayerRecord],
    round_number: int,
) -> list[Pairing]:
    """Return a list of Pairing objects for the given round."""
    if len(players) < 2:
        raise ValueError("Need at least 2 active players to generate pairings.")

    active = [p for p in players if not _is_eliminated(p)]

    # Separate the bye candidate early if player count is odd.
    bye_player: PlayerRecord | None = None
    if len(active) % 2 == 1:
        bye_player = _pick_bye_candidate(active)
        active = [p for p in active if p.user_id != bye_player.user_id]

    sorted_players = _sort_by_points(active)
    pairings = _pair_greedy(sorted_players)

    if bye_player:
        pairings.append(
            Pairing(
                player_a=bye_player.user_id,
                player_b=None,
                table_number=len(pairings) + 1,
            )
        )

    # Assign table numbers sequentially (bye always goes last).
    for i, p in enumerate(pairings, start=1):
        p.table_number = i

    return pairings


def calculate_total_rounds(player_count: int) -> int:
    """Standard MTG Swiss round count: ceil(log2(player_count))."""
    if player_count < 2:
        return 1
    return math.ceil(math.log2(player_count))


# ── Internal helpers ──────────────────────────────────────────────────────────

def _is_eliminated(player: PlayerRecord) -> bool:
    """Dropped or disqualified players should not receive pairings."""
    # PlayerRecord doesn't carry status; the router filters these out before calling.
    return False


def _pick_bye_candidate(players: list[PlayerRecord]) -> PlayerRecord:
    """
    Choose the bye recipient: lowest-points player who has not had a bye yet.
    Among equal candidates, pick randomly to avoid bias.
    """
    no_bye = [p for p in players if not p.had_bye]
    pool = no_bye if no_bye else players  # everyone had a bye — just pick lowest
    min_points = min(p.points for p in pool)
    candidates = [p for p in pool if p.points == min_points]
    return random.choice(candidates)


def _sort_by_points(players: list[PlayerRecord]) -> list[PlayerRecord]:
    """
    Sort descending by points. Within the same point total, shuffle randomly
    so table assignments are not deterministic.
    """
    groups: dict[int, list[PlayerRecord]] = {}
    for p in players:
        groups.setdefault(p.points, []).append(p)

    result: list[PlayerRecord] = []
    for pts in sorted(groups.keys(), reverse=True):
        group = groups[pts]
        random.shuffle(group)
        result.extend(group)
    return result


def _pair_greedy(sorted_players: list[PlayerRecord]) -> list[Pairing]:
    """
    Greedy O(n²) pairing. For each unpaired player (highest points first),
    find the best available opponent (no rematch preferred, closest in points).
    Falls back to allowing rematches only when no clean option exists.
    """
    paired: set[UUID] = set()
    pairings: list[Pairing] = []

    for player in sorted_players:
        if player.user_id in paired:
            continue

        opponent = _find_opponent(player, sorted_players, paired, allow_rematch=False)
        if opponent is None:
            # Last resort: allow rematch.
            opponent = _find_opponent(player, sorted_players, paired, allow_rematch=True)

        if opponent is None:
            # Should not happen if bye was handled correctly, but guard anyway.
            raise RuntimeError(
                f"Could not find an opponent for player {player.user_id}. "
                "This is a bug — please report it."
            )

        pairings.append(
            Pairing(
                player_a=player.user_id,
                player_b=opponent.user_id,
                table_number=0,  # assigned after the loop
            )
        )
        paired.add(player.user_id)
        paired.add(opponent.user_id)

    return pairings


def _find_opponent(
    player: PlayerRecord,
    sorted_players: list[PlayerRecord],
    paired: set[UUID],
    allow_rematch: bool,
) -> PlayerRecord | None:
    for candidate in sorted_players:
        if candidate.user_id == player.user_id:
            continue
        if candidate.user_id in paired:
            continue
        if not allow_rematch and candidate.user_id in player.opponents:
            continue
        return candidate
    return None
