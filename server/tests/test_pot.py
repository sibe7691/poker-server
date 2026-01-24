"""Tests for pot and side pot calculation."""
import pytest
from src.game.pot import Pot, SidePot, calculate_winnings


class TestPot:
    """Test basic pot operations."""
    
    def test_initial_state(self):
        """Test pot starts empty."""
        pot = Pot()
        assert pot.get_total() == 0
        assert pot.side_pots == []
    
    def test_add_bet(self):
        """Test adding bets to pot."""
        pot = Pot()
        pot.add_bet("player1", 50)
        pot.add_bet("player2", 50)
        
        assert pot.get_total() == 100
        assert pot.get_contribution("player1") == 50
        assert pot.get_contribution("player2") == 50
    
    def test_add_multiple_bets_same_player(self):
        """Test multiple bets from same player."""
        pot = Pot()
        pot.add_bet("player1", 50)
        pot.add_bet("player1", 100)  # Raises
        
        assert pot.get_total() == 150
        assert pot.get_contribution("player1") == 150
    
    def test_reset(self):
        """Test resetting pot."""
        pot = Pot()
        pot.add_bet("player1", 100)
        pot.reset()
        
        assert pot.get_total() == 0
        assert pot.get_contribution("player1") == 0
    
    def test_to_dict(self):
        """Test pot serialization."""
        pot = Pot()
        pot.add_bet("player1", 100)
        pot.add_bet("player2", 100)
        
        data = pot.to_dict()
        assert data["total"] == 200


class TestSidePots:
    """Test side pot calculation."""
    
    def test_no_all_ins(self):
        """Test no side pots when no all-ins."""
        pot = Pot()
        pot.add_bet("player1", 100)
        pot.add_bet("player2", 100)
        pot.add_bet("player3", 100)
        
        pot.calculate_side_pots({})
        
        assert len(pot.side_pots) == 1
        assert pot.side_pots[0].amount == 300
        assert set(pot.side_pots[0].eligible_players) == {"player1", "player2", "player3"}
    
    def test_one_all_in(self):
        """Test side pot with one all-in."""
        pot = Pot()
        pot.add_bet("player1", 50)   # All-in for 50
        pot.add_bet("player2", 100)
        pot.add_bet("player3", 100)
        
        pot.calculate_side_pots({"player1": 50})
        
        # Main pot: 50 * 3 = 150 (all eligible)
        # Side pot: 50 * 2 = 100 (player2 and player3)
        assert len(pot.side_pots) == 2
        
        main_pot = pot.side_pots[0]
        assert main_pot.amount == 150
        assert "player1" in main_pot.eligible_players
        
        side_pot = pot.side_pots[1]
        assert side_pot.amount == 100
        assert "player1" not in side_pot.eligible_players
    
    def test_multiple_all_ins(self):
        """Test multiple side pots with different all-in amounts."""
        pot = Pot()
        pot.add_bet("player1", 30)   # All-in for 30
        pot.add_bet("player2", 60)   # All-in for 60
        pot.add_bet("player3", 100)
        
        pot.calculate_side_pots({"player1": 30, "player2": 60})
        
        # Pot 1: 30 * 3 = 90 (all eligible)
        # Pot 2: 30 * 2 = 60 (player2, player3)
        # Pot 3: 40 * 1 = 40 (player3 only)
        assert len(pot.side_pots) == 3


class TestCalculateWinnings:
    """Test winnings calculation."""
    
    def test_single_winner_single_pot(self):
        """Test single winner takes whole pot."""
        side_pots = [SidePot(amount=300, eligible_players=["p1", "p2", "p3"])]
        winners_by_pot = {0: ["p1"]}
        
        winnings = calculate_winnings(side_pots, winners_by_pot)
        
        assert winnings["p1"] == 300
        assert "p2" not in winnings
    
    def test_split_pot(self):
        """Test pot split between winners."""
        side_pots = [SidePot(amount=300, eligible_players=["p1", "p2", "p3"])]
        winners_by_pot = {0: ["p1", "p2"]}
        
        winnings = calculate_winnings(side_pots, winners_by_pot)
        
        assert winnings["p1"] == 150
        assert winnings["p2"] == 150
    
    def test_odd_chip_split(self):
        """Test odd chip goes to first winner."""
        side_pots = [SidePot(amount=301, eligible_players=["p1", "p2"])]
        winners_by_pot = {0: ["p1", "p2"]}
        
        winnings = calculate_winnings(side_pots, winners_by_pot)
        
        # 301 / 2 = 150 remainder 1
        assert winnings["p1"] == 151  # Gets extra chip
        assert winnings["p2"] == 150
    
    def test_multiple_pots_different_winners(self):
        """Test different winners for main and side pot."""
        side_pots = [
            SidePot(amount=150, eligible_players=["p1", "p2", "p3"]),  # Main
            SidePot(amount=100, eligible_players=["p2", "p3"]),  # Side
        ]
        winners_by_pot = {
            0: ["p1"],  # p1 wins main (was all-in)
            1: ["p2"],  # p2 wins side
        }
        
        winnings = calculate_winnings(side_pots, winners_by_pot)
        
        assert winnings["p1"] == 150
        assert winnings["p2"] == 100
    
    def test_three_way_split(self):
        """Test three-way pot split."""
        side_pots = [SidePot(amount=300, eligible_players=["p1", "p2", "p3"])]
        winners_by_pot = {0: ["p1", "p2", "p3"]}
        
        winnings = calculate_winnings(side_pots, winners_by_pot)
        
        assert winnings["p1"] == 100
        assert winnings["p2"] == 100
        assert winnings["p3"] == 100
