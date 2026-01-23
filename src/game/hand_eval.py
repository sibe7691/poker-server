"""Hand evaluation for Texas Hold'em."""
from enum import IntEnum
from typing import Optional
from dataclasses import dataclass
from collections import Counter
from itertools import combinations

from src.game.deck import Card, Rank, Suit


class HandRank(IntEnum):
    """Poker hand rankings (higher is better)."""
    HIGH_CARD = 1
    PAIR = 2
    TWO_PAIR = 3
    THREE_OF_A_KIND = 4
    STRAIGHT = 5
    FLUSH = 6
    FULL_HOUSE = 7
    FOUR_OF_A_KIND = 8
    STRAIGHT_FLUSH = 9
    ROYAL_FLUSH = 10


@dataclass
class HandResult:
    """Result of hand evaluation."""
    rank: HandRank
    values: tuple[int, ...]  # Tiebreaker values (highest to lowest importance)
    cards: list[Card]  # The 5 cards making the hand
    description: str
    
    def __lt__(self, other: "HandResult") -> bool:
        if self.rank != other.rank:
            return self.rank < other.rank
        return self.values < other.values
    
    def __eq__(self, other: object) -> bool:
        if not isinstance(other, HandResult):
            return False
        return self.rank == other.rank and self.values == other.values
    
    def __gt__(self, other: "HandResult") -> bool:
        return other < self
    
    def __le__(self, other: "HandResult") -> bool:
        return self == other or self < other
    
    def __ge__(self, other: "HandResult") -> bool:
        return self == other or self > other


def _get_rank_counts(cards: list[Card]) -> dict[int, int]:
    """Get count of each rank in cards."""
    return Counter(c.rank.value for c in cards)


def _get_suit_counts(cards: list[Card]) -> dict[str, int]:
    """Get count of each suit in cards."""
    return Counter(c.suit.value for c in cards)


def _is_flush(cards: list[Card]) -> bool:
    """Check if 5 cards are all the same suit."""
    return len(set(c.suit for c in cards)) == 1


def _is_straight(ranks: list[int]) -> bool:
    """Check if sorted ranks form a straight."""
    sorted_ranks = sorted(set(ranks))
    if len(sorted_ranks) != 5:
        return False
    
    # Check for A-2-3-4-5 (wheel)
    if sorted_ranks == [2, 3, 4, 5, 14]:
        return True
    
    # Check for consecutive ranks
    return sorted_ranks[-1] - sorted_ranks[0] == 4


def _get_straight_high(ranks: list[int]) -> int:
    """Get the high card of a straight."""
    sorted_ranks = sorted(set(ranks))
    # Special case: wheel (A-2-3-4-5) has 5 as high
    if sorted_ranks == [2, 3, 4, 5, 14]:
        return 5
    return sorted_ranks[-1]


def _evaluate_5_cards(cards: list[Card]) -> HandResult:
    """Evaluate exactly 5 cards.
    
    Args:
        cards: Exactly 5 cards.
        
    Returns:
        HandResult with ranking.
    """
    if len(cards) != 5:
        raise ValueError(f"Expected 5 cards, got {len(cards)}")
    
    ranks = [c.rank.value for c in cards]
    rank_counts = _get_rank_counts(cards)
    is_flush = _is_flush(cards)
    is_straight = _is_straight(ranks)
    
    # Get counts sorted by frequency then rank
    counts = sorted(rank_counts.items(), key=lambda x: (x[1], x[0]), reverse=True)
    
    # Check for straight flush / royal flush
    if is_flush and is_straight:
        high = _get_straight_high(ranks)
        if high == 14:
            return HandResult(
                rank=HandRank.ROYAL_FLUSH,
                values=(14,),
                cards=cards,
                description="Royal Flush"
            )
        return HandResult(
            rank=HandRank.STRAIGHT_FLUSH,
            values=(high,),
            cards=cards,
            description=f"Straight Flush, {Rank(high)} high"
        )
    
    # Four of a kind
    if counts[0][1] == 4:
        quad_rank = counts[0][0]
        kicker = counts[1][0]
        return HandResult(
            rank=HandRank.FOUR_OF_A_KIND,
            values=(quad_rank, kicker),
            cards=cards,
            description=f"Four of a Kind, {Rank(quad_rank)}s"
        )
    
    # Full house
    if counts[0][1] == 3 and counts[1][1] == 2:
        trips_rank = counts[0][0]
        pair_rank = counts[1][0]
        return HandResult(
            rank=HandRank.FULL_HOUSE,
            values=(trips_rank, pair_rank),
            cards=cards,
            description=f"Full House, {Rank(trips_rank)}s full of {Rank(pair_rank)}s"
        )
    
    # Flush
    if is_flush:
        sorted_ranks = tuple(sorted(ranks, reverse=True))
        return HandResult(
            rank=HandRank.FLUSH,
            values=sorted_ranks,
            cards=cards,
            description=f"Flush, {Rank(sorted_ranks[0])} high"
        )
    
    # Straight
    if is_straight:
        high = _get_straight_high(ranks)
        return HandResult(
            rank=HandRank.STRAIGHT,
            values=(high,),
            cards=cards,
            description=f"Straight, {Rank(high)} high"
        )
    
    # Three of a kind
    if counts[0][1] == 3:
        trips_rank = counts[0][0]
        kickers = tuple(sorted([c[0] for c in counts[1:]], reverse=True))
        return HandResult(
            rank=HandRank.THREE_OF_A_KIND,
            values=(trips_rank,) + kickers,
            cards=cards,
            description=f"Three of a Kind, {Rank(trips_rank)}s"
        )
    
    # Two pair
    if counts[0][1] == 2 and counts[1][1] == 2:
        high_pair = max(counts[0][0], counts[1][0])
        low_pair = min(counts[0][0], counts[1][0])
        kicker = counts[2][0]
        return HandResult(
            rank=HandRank.TWO_PAIR,
            values=(high_pair, low_pair, kicker),
            cards=cards,
            description=f"Two Pair, {Rank(high_pair)}s and {Rank(low_pair)}s"
        )
    
    # Pair
    if counts[0][1] == 2:
        pair_rank = counts[0][0]
        kickers = tuple(sorted([c[0] for c in counts[1:]], reverse=True))
        return HandResult(
            rank=HandRank.PAIR,
            values=(pair_rank,) + kickers,
            cards=cards,
            description=f"Pair of {Rank(pair_rank)}s"
        )
    
    # High card
    sorted_ranks = tuple(sorted(ranks, reverse=True))
    return HandResult(
        rank=HandRank.HIGH_CARD,
        values=sorted_ranks,
        cards=cards,
        description=f"High Card, {Rank(sorted_ranks[0])}"
    )


def evaluate_hand(hole_cards: list[Card], community_cards: list[Card]) -> HandResult:
    """Evaluate the best 5-card hand from hole cards and community cards.
    
    Args:
        hole_cards: Player's 2 hole cards.
        community_cards: 3-5 community cards.
        
    Returns:
        Best possible HandResult.
    """
    all_cards = hole_cards + community_cards
    
    if len(all_cards) < 5:
        raise ValueError(f"Need at least 5 cards, got {len(all_cards)}")
    
    # Find the best 5-card combination
    best: Optional[HandResult] = None
    
    for combo in combinations(all_cards, 5):
        result = _evaluate_5_cards(list(combo))
        if best is None or result > best:
            best = result
    
    return best  # type: ignore


def compare_hands(results: list[tuple[str, HandResult]]) -> list[list[str]]:
    """Compare multiple hands and return winners.
    
    Args:
        results: List of (player_id, HandResult) tuples.
        
    Returns:
        List of winner groups (ties are in the same group).
    """
    if not results:
        return []
    
    # Sort by hand strength descending
    sorted_results = sorted(results, key=lambda x: x[1], reverse=True)
    
    # Group by equal hands
    winners: list[list[str]] = []
    current_group: list[str] = [sorted_results[0][0]]
    current_hand = sorted_results[0][1]
    
    for player_id, hand in sorted_results[1:]:
        if hand == current_hand:
            current_group.append(player_id)
        else:
            winners.append(current_group)
            current_group = [player_id]
            current_hand = hand
    
    winners.append(current_group)
    return winners
