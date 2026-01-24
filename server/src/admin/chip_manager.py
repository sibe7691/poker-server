"""Chip management for admins."""
from typing import Optional, TYPE_CHECKING

from src.admin.ledger import Ledger, TransactionType, Transaction, GameSession
from src.admin.standings import calculate_standings, PlayerStanding
from src.utils.logger import get_logger

if TYPE_CHECKING:
    from src.game.table import Table

logger = get_logger(__name__)


class ChipManager:
    """Manages chip distribution and tracking for a game session."""
    
    def __init__(self, session_id: str):
        """Initialize chip manager.
        
        Args:
            session_id: Unique session identifier.
        """
        self.session_id = session_id
        self.ledger = Ledger(session_id)
        self._table: Optional["Table"] = None
    
    def set_table(self, table: "Table") -> None:
        """Associate a table with this chip manager.
        
        Args:
            table: The game table.
        """
        self._table = table
    
    async def give_chips(
        self,
        user_id: str,
        player_name: str,
        amount: int,
        admin_id: str,
        note: Optional[str] = None,
    ) -> Transaction:
        """Give chips to a player (buy-in).
        
        Args:
            user_id: Player's user ID.
            player_name: Player's username.
            amount: Chip amount to give.
            admin_id: Admin performing the action.
            note: Optional note.
            
        Returns:
            The transaction record.
            
        Raises:
            ValueError: If amount is invalid.
        """
        if amount <= 0:
            raise ValueError("Amount must be positive")
        
        # Record transaction
        transaction = await self.ledger.record_transaction(
            user_id=user_id,
            player_name=player_name,
            transaction_type=TransactionType.BUY_IN,
            amount=amount,
            admin_id=admin_id,
            note=note,
        )
        
        # Update player chips at table if seated
        if self._table:
            table_player = self._table.get_player_by_id(user_id)
            if table_player:
                table_player.chips += amount
                logger.info(f"Added {amount} chips to {player_name} at table (new total: {table_player.chips})")
        
        return transaction
    
    async def take_chips(
        self,
        user_id: str,
        player_name: str,
        amount: int,
        admin_id: str,
        note: Optional[str] = None,
    ) -> Transaction:
        """Take chips from a player (cash-out).
        
        Args:
            user_id: Player's user ID.
            player_name: Player's username.
            amount: Chip amount to take.
            admin_id: Admin performing the action.
            note: Optional note.
            
        Returns:
            The transaction record.
            
        Raises:
            ValueError: If amount is invalid or player doesn't have enough chips.
        """
        if amount <= 0:
            raise ValueError("Amount must be positive")
        
        # Check player has enough chips at table
        if self._table:
            table_player = self._table.get_player_by_id(user_id)
            if table_player and table_player.chips < amount:
                raise ValueError(f"Player {player_name} only has {table_player.chips} chips")
        
        # Record transaction
        transaction = await self.ledger.record_transaction(
            user_id=user_id,
            player_name=player_name,
            transaction_type=TransactionType.CASH_OUT,
            amount=amount,
            admin_id=admin_id,
            note=note,
        )
        
        # Update player chips at table if seated
        if self._table:
            table_player = self._table.get_player_by_id(user_id)
            if table_player:
                table_player.chips -= amount
                logger.info(f"Removed {amount} chips from {player_name} at table (new total: {table_player.chips})")
        
        return transaction
    
    async def set_chips(
        self,
        user_id: str,
        player_name: str,
        amount: int,
        admin_id: str,
        note: Optional[str] = None,
    ) -> Transaction:
        """Set exact chip count for a player (correction).
        
        Args:
            user_id: Player's user ID.
            player_name: Player's username.
            amount: Target chip amount.
            admin_id: Admin performing the action.
            note: Optional note.
            
        Returns:
            The adjustment transaction record.
            
        Raises:
            ValueError: If amount is negative.
        """
        if amount < 0:
            raise ValueError("Amount cannot be negative")
        
        # Calculate adjustment needed
        current_chips = 0
        if self._table:
            table_player = self._table.get_player_by_id(user_id)
            if table_player:
                current_chips = table_player.chips
        
        adjustment = amount - current_chips
        
        if adjustment == 0:
            logger.info(f"No adjustment needed for {player_name}, already at {amount} chips")
            # Still record for audit trail
        
        # Record adjustment transaction
        transaction = await self.ledger.record_transaction(
            user_id=user_id,
            player_name=player_name,
            transaction_type=TransactionType.ADJUSTMENT,
            amount=adjustment,
            admin_id=admin_id,
            note=note or f"Set chips to {amount} (was {current_chips})",
        )
        
        # Update player chips at table if seated
        if self._table:
            table_player = self._table.get_player_by_id(user_id)
            if table_player:
                table_player.chips = amount
                logger.info(f"Set {player_name} chips to {amount}")
        
        return transaction
    
    async def get_ledger(self) -> list[Transaction]:
        """Get all transactions for the session.
        
        Returns:
            List of all transactions.
        """
        return await self.ledger.get_all_transactions()
    
    async def get_standings(self) -> list[PlayerStanding]:
        """Get current standings for all players.
        
        Returns:
            List of player standings sorted by net.
        """
        return await calculate_standings(self.session_id)
    
    async def get_player_summary(self, user_id: str) -> dict:
        """Get summary for a specific player.
        
        Args:
            user_id: Player's user ID.
            
        Returns:
            Player's chip summary.
        """
        return await self.ledger.get_player_summary(user_id)
