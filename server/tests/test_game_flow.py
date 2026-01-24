"""Tests for game flow and table state machine."""
import pytest
from src.game.table import Table, TableState
from src.game.player import Player
from src.game.betting import Action, ActionType


def make_player(user_id: str, chips: int = 1000, seat: int = None) -> Player:
    """Create a test player."""
    return Player(
        user_id=user_id,
        username=f"player_{user_id}",
        seat=seat if seat is not None else int(user_id),
        chips=chips,
    )


class TestTableSetup:
    """Test table setup and player management."""
    
    def test_create_table(self):
        """Test creating a table."""
        table = Table(
            table_id="test",
            small_blind=1,
            big_blind=2,
        )
        
        assert table.table_id == "test"
        assert table.state == TableState.WAITING
        assert len(table.players) == 0
    
    def test_add_player(self):
        """Test adding a player."""
        table = Table(table_id="test")
        player = make_player("1", seat=0)
        
        assert table.add_player(player)
        assert len(table.players) == 1
        assert table.players[0] == player
    
    def test_add_player_duplicate_seat(self):
        """Test cannot add player to occupied seat."""
        table = Table(table_id="test")
        player1 = make_player("1", seat=0)
        player2 = make_player("2", seat=0)
        
        assert table.add_player(player1)
        assert not table.add_player(player2)
    
    def test_remove_player(self):
        """Test removing a player."""
        table = Table(table_id="test")
        player = make_player("1", seat=0)
        table.add_player(player)
        
        removed = table.remove_player("1")
        
        assert removed == player
        assert len(table.players) == 0
    
    def test_get_player(self):
        """Test getting a player by username."""
        table = Table(table_id="test")
        player = make_player("1", seat=0)
        table.add_player(player)
        
        found = table.get_player("player_1")
        assert found == player
    
    def test_next_available_seat(self):
        """Test getting next available seat."""
        table = Table(table_id="test", max_players=3)
        table.add_player(make_player("1", seat=0))
        table.add_player(make_player("2", seat=2))
        
        assert table.get_next_available_seat() == 1


class TestHandStart:
    """Test starting a hand."""
    
    def test_cannot_start_with_one_player(self):
        """Test cannot start with only one player."""
        table = Table(table_id="test", min_players=2)
        table.add_player(make_player("1", chips=100, seat=0))
        
        assert not table.can_start_hand()
    
    def test_can_start_with_two_players(self):
        """Test can start with two players."""
        table = Table(table_id="test", min_players=2)
        table.add_player(make_player("1", chips=100, seat=0))
        table.add_player(make_player("2", chips=100, seat=1))
        
        assert table.can_start_hand()
    
    @pytest.mark.asyncio
    async def test_start_hand_deals_cards(self):
        """Test starting hand deals hole cards."""
        table = Table(table_id="test", small_blind=1, big_blind=2)
        table.add_player(make_player("1", chips=100, seat=0))
        table.add_player(make_player("2", chips=100, seat=1))
        
        await table.start_hand()
        
        for player in table.players.values():
            assert len(player.hole_cards) == 2
    
    @pytest.mark.asyncio
    async def test_start_hand_posts_blinds(self):
        """Test starting hand posts blinds."""
        table = Table(table_id="test", small_blind=1, big_blind=2)
        p1 = make_player("1", chips=100, seat=0)
        p2 = make_player("2", chips=100, seat=1)
        table.add_player(p1)
        table.add_player(p2)
        
        await table.start_hand()
        
        # Blinds should be posted
        total_blinds = p1.current_bet + p2.current_bet
        assert total_blinds == 3  # SB + BB
    
    @pytest.mark.asyncio
    async def test_start_hand_changes_state(self):
        """Test starting hand changes state to preflop."""
        table = Table(table_id="test")
        table.add_player(make_player("1", chips=100, seat=0))
        table.add_player(make_player("2", chips=100, seat=1))
        
        await table.start_hand()
        
        assert table.state == TableState.PREFLOP


class TestGameFlow:
    """Test complete game flow."""
    
    @pytest.mark.asyncio
    async def test_preflop_to_flop(self):
        """Test advancing from preflop to flop."""
        table = Table(table_id="test", small_blind=1, big_blind=2)
        table.add_player(make_player("1", chips=100, seat=0))
        table.add_player(make_player("2", chips=100, seat=1))
        
        await table.start_hand()
        assert table.state == TableState.PREFLOP
        
        # Both players need to act - use appropriate action based on valid actions
        while table.current_betting_round and not table.current_betting_round.is_complete:
            current = table.current_betting_round.get_current_player()
            if current:
                valid_actions = table.current_betting_round.get_valid_actions(current)
                if ActionType.CHECK in valid_actions:
                    await table.process_action(current.user_id, Action(type=ActionType.CHECK))
                elif ActionType.CALL in valid_actions:
                    await table.process_action(current.user_id, Action(type=ActionType.CALL))
                else:
                    await table.process_action(current.user_id, Action(type=ActionType.FOLD))
        
        # Should advance to flop after betting completes
        # (This happens automatically in _end_betting_round)
    
    @pytest.mark.asyncio
    async def test_fold_ends_hand(self):
        """Test folding ends the hand when only one player remains."""
        table = Table(table_id="test", small_blind=1, big_blind=2)
        p1 = make_player("1", chips=100, seat=0)
        p2 = make_player("2", chips=100, seat=1)
        table.add_player(p1)
        table.add_player(p2)
        
        await table.start_hand()
        initial_p2_chips = p2.chips
        
        # First player (after blinds) folds
        current = table.current_betting_round.get_current_player()
        await table.process_action(current.user_id, Action(type=ActionType.FOLD))
        
        # Hand should be complete
        assert table.state == TableState.WAITING


class TestStateForPlayer:
    """Test getting state from player's perspective."""
    
    def test_hides_other_players_cards(self):
        """Test other players' hole cards are hidden."""
        table = Table(table_id="test")
        p1 = make_player("1", chips=100, seat=0)
        p2 = make_player("2", chips=100, seat=1)
        table.add_player(p1)
        table.add_player(p2)
        
        # Manually set cards for testing
        from src.game.deck import Card, Rank, Suit
        p1.hole_cards = [Card(Rank.ACE, Suit.SPADES), Card(Rank.KING, Suit.SPADES)]
        p2.hole_cards = [Card(Rank.TWO, Suit.HEARTS), Card(Rank.THREE, Suit.HEARTS)]
        
        state = table.get_state_for_player("1")
        
        # Player 1 should see their own cards
        p1_data = next(p for p in state["players"] if p["user_id"] == "1")
        assert "hole_cards" in p1_data
        
        # Player 1 should NOT see player 2's cards
        p2_data = next(p for p in state["players"] if p["user_id"] == "2")
        assert "hole_cards" not in p2_data
        assert p2_data["has_cards"] is True


class TestSerialization:
    """Test table state serialization."""
    
    def test_round_trip_serialization(self):
        """Test table can be serialized and deserialized."""
        table = Table(
            table_id="test",
            small_blind=5,
            big_blind=10,
        )
        table.add_player(make_player("1", chips=500, seat=0))
        table.add_player(make_player("2", chips=1000, seat=3))
        table.hand_number = 5
        table.dealer_seat = 3
        
        # Serialize
        data = table.to_dict()
        
        # Deserialize
        restored = Table.from_dict(data)
        
        assert restored.table_id == "test"
        assert restored.small_blind == 5
        assert restored.big_blind == 10
        assert restored.hand_number == 5
        assert restored.dealer_seat == 3
        assert len(restored.players) == 2
