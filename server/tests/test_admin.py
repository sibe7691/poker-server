"""Tests for admin module (chip management, ledger, standings)."""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from datetime import datetime, timezone

from src.admin.ledger import Transaction, TransactionType, Ledger
from src.admin.standings import PlayerStanding, format_standings_table
from src.admin.chip_manager import ChipManager


class TestTransaction:
    """Test Transaction model."""
    
    def test_transaction_to_dict(self):
        """Test transaction serialization."""
        transaction = Transaction(
            id="tx123",
            session_id="session456",
            user_id="user789",
            player_name="alice",
            type=TransactionType.BUY_IN,
            amount=500,
            admin_id="admin001",
            admin_name="bob",
            note="Initial buy-in",
            created_at=datetime(2024, 1, 15, 12, 0, 0, tzinfo=timezone.utc),
        )
        
        data = transaction.to_dict()
        
        assert data["id"] == "tx123"
        assert data["player"] == "alice"
        assert data["type"] == "buy_in"
        assert data["amount"] == 500
        assert data["admin"] == "bob"
        assert data["note"] == "Initial buy-in"
    
    def test_transaction_types(self):
        """Test transaction type values."""
        assert TransactionType.BUY_IN.value == "buy_in"
        assert TransactionType.CASH_OUT.value == "cash_out"
        assert TransactionType.ADJUSTMENT.value == "adjustment"


class TestPlayerStanding:
    """Test PlayerStanding model."""
    
    def test_standing_to_dict(self):
        """Test standing serialization."""
        standing = PlayerStanding(
            user_id="user123",
            player="alice",
            buy_ins=500,
            cash_outs=750,
            adjustments=0,
            net=250,
        )
        
        data = standing.to_dict()
        
        assert data["player"] == "alice"
        assert data["buy_ins"] == 500
        assert data["cash_outs"] == 750
        assert data["net"] == 250
    
    def test_format_standings_table_empty(self):
        """Test formatting empty standings."""
        result = format_standings_table([])
        assert result == "No transactions recorded."
    
    def test_format_standings_table(self):
        """Test formatting standings as table."""
        standings = [
            PlayerStanding("1", "alice", 500, 750, 0, 250),
            PlayerStanding("2", "bob", 500, 200, 0, -300),
        ]
        
        result = format_standings_table(standings)
        
        assert "alice" in result
        assert "bob" in result
        assert "+250" in result
        assert "-300" in result


class TestChipManager:
    """Test ChipManager operations."""
    
    @pytest.fixture
    def chip_manager(self):
        """Create a chip manager with mocked ledger."""
        manager = ChipManager("session123")
        return manager
    
    def test_chip_manager_init(self, chip_manager):
        """Test chip manager initialization."""
        assert chip_manager.session_id == "session123"
        assert chip_manager.ledger is not None
    
    @pytest.mark.asyncio
    async def test_give_chips_invalid_amount(self, chip_manager):
        """Test giving zero or negative chips fails."""
        with pytest.raises(ValueError) as exc_info:
            await chip_manager.give_chips(
                user_id="user1",
                player_name="alice",
                amount=0,
                admin_id="admin1",
            )
        assert "Amount must be positive" in str(exc_info.value)
        
        with pytest.raises(ValueError):
            await chip_manager.give_chips(
                user_id="user1",
                player_name="alice",
                amount=-100,
                admin_id="admin1",
            )
    
    @pytest.mark.asyncio
    async def test_take_chips_invalid_amount(self, chip_manager):
        """Test taking zero or negative chips fails."""
        with pytest.raises(ValueError) as exc_info:
            await chip_manager.take_chips(
                user_id="user1",
                player_name="alice",
                amount=0,
                admin_id="admin1",
            )
        assert "Amount must be positive" in str(exc_info.value)
    
    @pytest.mark.asyncio
    async def test_set_chips_negative_fails(self, chip_manager):
        """Test setting negative chips fails."""
        with pytest.raises(ValueError) as exc_info:
            await chip_manager.set_chips(
                user_id="user1",
                player_name="alice",
                amount=-100,
                admin_id="admin1",
            )
        assert "Amount cannot be negative" in str(exc_info.value)


class TestChipManagerWithTable:
    """Test ChipManager with a mocked table."""
    
    @pytest.mark.asyncio
    async def test_give_chips_updates_table_player(self):
        """Test giving chips updates player at table."""
        from src.game.player import Player
        
        # Create manager and mock table
        manager = ChipManager("session123")
        
        # Create a mock table with a player
        mock_table = MagicMock()
        player = Player(user_id="user1", username="alice", seat=0, chips=100)
        mock_table.get_player_by_id.return_value = player
        
        manager.set_table(mock_table)
        
        # Mock the ledger transaction
        with patch.object(manager.ledger, 'record_transaction', new_callable=AsyncMock) as mock_record:
            mock_record.return_value = Transaction(
                id="tx1",
                session_id="session123",
                user_id="user1",
                player_name="alice",
                type=TransactionType.BUY_IN,
                amount=500,
                admin_id="admin1",
                admin_name=None,
                note=None,
                created_at=datetime.now(timezone.utc),
            )
            
            await manager.give_chips(
                user_id="user1",
                player_name="alice",
                amount=500,
                admin_id="admin1",
            )
        
        # Player chips should be updated
        assert player.chips == 600  # 100 + 500
    
    @pytest.mark.asyncio
    async def test_take_chips_checks_player_balance(self):
        """Test taking chips checks player has enough."""
        from src.game.player import Player
        
        manager = ChipManager("session123")
        
        mock_table = MagicMock()
        player = Player(user_id="user1", username="alice", seat=0, chips=100)
        mock_table.get_player_by_id.return_value = player
        
        manager.set_table(mock_table)
        
        # Try to take more chips than player has
        with pytest.raises(ValueError) as exc_info:
            await manager.take_chips(
                user_id="user1",
                player_name="alice",
                amount=500,  # More than 100
                admin_id="admin1",
            )
        
        assert "only has 100 chips" in str(exc_info.value)
