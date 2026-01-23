"""Tests for betting logic."""
import pytest
from src.game.player import Player
from src.game.betting import BettingRound, Action, ActionType


def make_player(user_id: str, chips: int = 1000) -> Player:
    """Create a test player."""
    return Player(
        user_id=user_id,
        username=f"player_{user_id}",
        seat=int(user_id),
        chips=chips,
    )


class TestBettingRound:
    """Test betting round logic."""
    
    def test_initial_state(self):
        """Test initial betting round state."""
        players = [make_player("1"), make_player("2"), make_player("3")]
        for p in players:
            p.receive_cards([])  # Simulate having cards
            p.hole_cards = ["dummy"]  # Just to make is_active True
        
        round = BettingRound(players, small_blind=1, big_blind=2)
        
        assert round.current_bet == 0
        assert not round.is_complete
    
    def test_check_when_no_bet(self):
        """Test checking when there's no bet to call."""
        players = [make_player("1"), make_player("2")]
        for p in players:
            p.hole_cards = ["dummy"]
        
        round = BettingRound(players, big_blind=2)
        current = round.get_current_player()
        
        valid = round.get_valid_actions(current)
        assert ActionType.CHECK in valid
    
    def test_cannot_check_with_bet(self):
        """Test cannot check when there's a bet to call."""
        players = [make_player("1"), make_player("2")]
        for p in players:
            p.hole_cards = ["dummy"]
        
        round = BettingRound(players, big_blind=2)
        round.current_bet = 10
        current = round.get_current_player()
        
        valid = round.get_valid_actions(current)
        assert ActionType.CHECK not in valid
        assert ActionType.CALL in valid
    
    def test_fold_action(self):
        """Test folding."""
        players = [make_player("1"), make_player("2")]
        for p in players:
            p.hole_cards = ["dummy"]
        
        round = BettingRound(players, big_blind=2)
        current = round.get_current_player()
        
        round.process_action(current, Action(type=ActionType.FOLD))
        
        assert current.is_folded
    
    def test_call_action(self):
        """Test calling."""
        players = [make_player("1", chips=100), make_player("2", chips=100)]
        for p in players:
            p.hole_cards = ["dummy"]
        
        round = BettingRound(players, big_blind=2)
        round.current_bet = 10
        current = round.get_current_player()
        
        round.process_action(current, Action(type=ActionType.CALL))
        
        assert current.current_bet == 10
        assert current.chips == 90
    
    def test_raise_action(self):
        """Test raising."""
        players = [make_player("1", chips=100), make_player("2", chips=100)]
        for p in players:
            p.hole_cards = ["dummy"]
        
        round = BettingRound(players, big_blind=2)
        round.current_bet = 10
        round.min_raise = 10
        current = round.get_current_player()
        
        # Raise to 20 (call 10 + raise 10)
        round.process_action(current, Action(type=ActionType.RAISE, amount=20))
        
        assert round.current_bet == 20
    
    def test_all_in_action(self):
        """Test going all-in."""
        players = [make_player("1", chips=50), make_player("2", chips=100)]
        for p in players:
            p.hole_cards = ["dummy"]
        
        round = BettingRound(players, big_blind=2)
        current = round.get_current_player()
        
        round.process_action(current, Action(type=ActionType.ALL_IN))
        
        assert current.is_all_in
        assert current.chips == 0
        assert current.current_bet == 50
    
    def test_round_completes_after_all_check(self):
        """Test round completes when all check."""
        players = [make_player("1"), make_player("2")]
        for p in players:
            p.hole_cards = ["dummy"]
        
        round = BettingRound(players, big_blind=2)
        
        # Player 1 checks
        round.process_action(round.get_current_player(), Action(type=ActionType.CHECK))
        assert not round.is_complete
        
        # Player 2 checks
        round.process_action(round.get_current_player(), Action(type=ActionType.CHECK))
        assert round.is_complete
    
    def test_round_completes_after_call(self):
        """Test round completes when bet is called."""
        players = [make_player("1"), make_player("2")]
        for p in players:
            p.hole_cards = ["dummy"]
        
        round = BettingRound(players, big_blind=2)
        
        # Player 1 bets
        round.process_action(round.get_current_player(), Action(type=ActionType.BET, amount=10))
        assert not round.is_complete
        
        # Player 2 calls
        round.process_action(round.get_current_player(), Action(type=ActionType.CALL))
        assert round.is_complete


class TestBettingValidation:
    """Test betting validation."""
    
    def test_min_bet_is_big_blind(self):
        """Test minimum bet must be at least big blind."""
        players = [make_player("1", chips=100)]
        players[0].hole_cards = ["dummy"]
        
        round = BettingRound(players, big_blind=10)
        
        with pytest.raises(ValueError):
            round.process_action(
                players[0],
                Action(type=ActionType.BET, amount=5)  # Less than BB
            )
    
    def test_min_raise_amount(self):
        """Test minimum raise must be at least previous raise."""
        players = [make_player("1", chips=100), make_player("2", chips=100)]
        for p in players:
            p.hole_cards = ["dummy"]
        
        round = BettingRound(players, big_blind=2)
        round.current_bet = 10
        round.min_raise = 8  # Previous raise was 8
        
        with pytest.raises(ValueError):
            round.process_action(
                players[0],
                Action(type=ActionType.RAISE, amount=15)  # Only 5 more, need 8+
            )
    
    def test_cannot_bet_when_bet_exists(self):
        """Test cannot use BET when there's already a bet (must RAISE)."""
        players = [make_player("1", chips=100)]
        players[0].hole_cards = ["dummy"]
        
        round = BettingRound(players, big_blind=2)
        round.current_bet = 10  # There's already a bet
        
        with pytest.raises(ValueError):
            round.process_action(
                players[0],
                Action(type=ActionType.BET, amount=20)
            )
