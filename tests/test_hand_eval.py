"""Tests for hand evaluation."""
import pytest
from src.game.deck import Card, Rank, Suit
from src.game.hand_eval import (
    evaluate_hand,
    compare_hands,
    HandRank,
    _evaluate_5_cards,
)


def make_card(s: str) -> Card:
    """Helper to create card from string like 'Ah', '10s'."""
    return Card.from_string(s)


def make_cards(cards: str) -> list[Card]:
    """Helper to create cards from space-separated string."""
    return [make_card(c) for c in cards.split()]


class TestHandRanking:
    """Test individual hand rankings."""
    
    def test_high_card(self):
        """Test high card detection."""
        cards = make_cards("2h 5d 8c Jh Ks")
        result = _evaluate_5_cards(cards)
        assert result.rank == HandRank.HIGH_CARD
        assert result.values[0] == 13  # King high
    
    def test_pair(self):
        """Test pair detection."""
        cards = make_cards("2h 2d 8c Jh Ks")
        result = _evaluate_5_cards(cards)
        assert result.rank == HandRank.PAIR
        assert result.values[0] == 2  # Pair of 2s
    
    def test_two_pair(self):
        """Test two pair detection."""
        cards = make_cards("2h 2d 8c 8h Ks")
        result = _evaluate_5_cards(cards)
        assert result.rank == HandRank.TWO_PAIR
        assert result.values[0] == 8  # Higher pair
        assert result.values[1] == 2  # Lower pair
    
    def test_three_of_a_kind(self):
        """Test three of a kind detection."""
        cards = make_cards("Jh Jd Jc 8h Ks")
        result = _evaluate_5_cards(cards)
        assert result.rank == HandRank.THREE_OF_A_KIND
        assert result.values[0] == 11  # Jacks
    
    def test_straight(self):
        """Test straight detection."""
        cards = make_cards("5h 6d 7c 8h 9s")
        result = _evaluate_5_cards(cards)
        assert result.rank == HandRank.STRAIGHT
        assert result.values[0] == 9  # 9 high
    
    def test_straight_wheel(self):
        """Test A-2-3-4-5 (wheel) straight."""
        cards = make_cards("Ah 2d 3c 4h 5s")
        result = _evaluate_5_cards(cards)
        assert result.rank == HandRank.STRAIGHT
        assert result.values[0] == 5  # 5 high (wheel)
    
    def test_straight_broadway(self):
        """Test 10-J-Q-K-A (broadway) straight."""
        cards = make_cards("Th Jd Qc Kh As")
        result = _evaluate_5_cards(cards)
        assert result.rank == HandRank.STRAIGHT
        assert result.values[0] == 14  # Ace high
    
    def test_flush(self):
        """Test flush detection."""
        cards = make_cards("2h 5h 8h Jh Kh")
        result = _evaluate_5_cards(cards)
        assert result.rank == HandRank.FLUSH
        assert result.values[0] == 13  # King high flush
    
    def test_full_house(self):
        """Test full house detection."""
        cards = make_cards("Jh Jd Jc 8h 8s")
        result = _evaluate_5_cards(cards)
        assert result.rank == HandRank.FULL_HOUSE
        assert result.values[0] == 11  # Jacks full
        assert result.values[1] == 8   # of 8s
    
    def test_four_of_a_kind(self):
        """Test four of a kind detection."""
        cards = make_cards("Jh Jd Jc Js Ks")
        result = _evaluate_5_cards(cards)
        assert result.rank == HandRank.FOUR_OF_A_KIND
        assert result.values[0] == 11  # Quad Jacks
    
    def test_straight_flush(self):
        """Test straight flush detection."""
        cards = make_cards("5h 6h 7h 8h 9h")
        result = _evaluate_5_cards(cards)
        assert result.rank == HandRank.STRAIGHT_FLUSH
        assert result.values[0] == 9  # 9 high
    
    def test_royal_flush(self):
        """Test royal flush detection."""
        cards = make_cards("Th Jh Qh Kh Ah")
        result = _evaluate_5_cards(cards)
        assert result.rank == HandRank.ROYAL_FLUSH


class TestBestHandSelection:
    """Test selecting best hand from 7 cards."""
    
    def test_best_from_seven(self):
        """Test finding best 5-card hand from 7 cards."""
        hole = make_cards("Ah Kh")
        community = make_cards("Qh Jh Th 2c 3d")
        result = evaluate_hand(hole, community)
        assert result.rank == HandRank.ROYAL_FLUSH
    
    def test_uses_both_hole_cards(self):
        """Test when best hand uses both hole cards."""
        hole = make_cards("Ah As")
        community = make_cards("Ad Ac 2h 3c 4d")
        result = evaluate_hand(hole, community)
        assert result.rank == HandRank.FOUR_OF_A_KIND
    
    def test_uses_one_hole_card(self):
        """Test when best hand uses one hole card."""
        hole = make_cards("Ah 2c")
        community = make_cards("Kh Qh Jh Th 3d")
        result = evaluate_hand(hole, community)
        assert result.rank == HandRank.ROYAL_FLUSH
    
    def test_plays_the_board(self):
        """Test when board is the best hand."""
        hole = make_cards("2c 3d")
        community = make_cards("Ah Kh Qh Jh Th")
        result = evaluate_hand(hole, community)
        assert result.rank == HandRank.ROYAL_FLUSH


class TestHandComparison:
    """Test comparing multiple hands."""
    
    def test_higher_rank_wins(self):
        """Test that higher rank beats lower rank."""
        results = [
            ("player1", _evaluate_5_cards(make_cards("2h 2d 8c Jh Ks"))),  # Pair
            ("player2", _evaluate_5_cards(make_cards("5h 6d 7c 8h 9s"))),  # Straight
        ]
        winners = compare_hands(results)
        assert winners[0] == ["player2"]
    
    def test_same_rank_kicker(self):
        """Test kicker breaks ties."""
        results = [
            ("player1", _evaluate_5_cards(make_cards("Ah Kd 8c Jh 2s"))),  # A high, K kicker
            ("player2", _evaluate_5_cards(make_cards("Ah Qd 8c Jh 2s"))),  # A high, Q kicker
        ]
        winners = compare_hands(results)
        assert winners[0] == ["player1"]
    
    def test_split_pot(self):
        """Test identical hands split."""
        results = [
            ("player1", _evaluate_5_cards(make_cards("Ah Kh Qh Jh Th"))),  # Royal flush
            ("player2", _evaluate_5_cards(make_cards("As Ks Qs Js Ts"))),  # Royal flush
        ]
        winners = compare_hands(results)
        assert set(winners[0]) == {"player1", "player2"}
    
    def test_three_way_comparison(self):
        """Test comparing three hands."""
        results = [
            ("player1", _evaluate_5_cards(make_cards("2h 2d 8c Jh Ks"))),    # Pair of 2s
            ("player2", _evaluate_5_cards(make_cards("Ah Kd 8c Jh 2s"))),    # High card
            ("player3", _evaluate_5_cards(make_cards("5h 5d 5c Jh Ks"))),    # Trips
        ]
        winners = compare_hands(results)
        assert winners[0] == ["player3"]
        assert winners[1] == ["player1"]
        assert winners[2] == ["player2"]


class TestEdgeCases:
    """Test edge cases in hand evaluation."""
    
    def test_ace_low_straight(self):
        """Test A-2-3-4-5 beats K-high."""
        wheel = _evaluate_5_cards(make_cards("Ah 2d 3c 4h 5s"))
        high_card = _evaluate_5_cards(make_cards("Kh Qd Jc 9h 7s"))
        assert wheel > high_card
    
    def test_ace_low_vs_six_high_straight(self):
        """Test 6-high straight beats wheel."""
        wheel = _evaluate_5_cards(make_cards("Ah 2d 3c 4h 5s"))
        six_high = _evaluate_5_cards(make_cards("2h 3d 4c 5h 6s"))
        assert six_high > wheel
