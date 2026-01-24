"""Transaction ledger for chip tracking using PostgreSQL."""
import uuid
from datetime import datetime, timezone
from typing import Optional
from dataclasses import dataclass
from enum import Enum

from src.db.connection import db
from src.utils.logger import get_logger

logger = get_logger(__name__)


class TransactionType(str, Enum):
    """Types of chip transactions."""
    BUY_IN = "buy_in"
    CASH_OUT = "cash_out"
    ADJUSTMENT = "adjustment"


@dataclass
class Transaction:
    """A chip transaction record."""
    id: str
    session_id: str
    user_id: str
    player_name: str  # Denormalized for convenience
    type: TransactionType
    amount: int
    admin_id: Optional[str]
    admin_name: Optional[str]  # Denormalized
    note: Optional[str]
    created_at: datetime
    
    def to_dict(self) -> dict:
        """Convert to dictionary for serialization."""
        return {
            "id": self.id,
            "session_id": self.session_id,
            "user_id": self.user_id,
            "player": self.player_name,
            "type": self.type.value,
            "amount": self.amount,
            "admin": self.admin_name,
            "note": self.note,
            "timestamp": self.created_at.isoformat(),
        }
    
    @classmethod
    def from_record(cls, record, player_name: str = "", admin_name: str = None) -> "Transaction":
        """Create from database record."""
        return cls(
            id=str(record["id"]),
            session_id=str(record["session_id"]),
            user_id=str(record["user_id"]),
            player_name=player_name,
            type=TransactionType(record["type"]),
            amount=record["amount"],
            admin_id=str(record["admin_id"]) if record["admin_id"] else None,
            admin_name=admin_name,
            note=record["note"],
            created_at=record["created_at"],
        )


class GameSession:
    """A poker game session."""
    
    def __init__(self, session_id: str, name: Optional[str] = None):
        self.id = session_id
        self.name = name
    
    @classmethod
    async def create(cls, name: Optional[str] = None) -> "GameSession":
        """Create a new game session."""
        session_id = await db.fetchval(
            """
            INSERT INTO game_sessions (name)
            VALUES ($1)
            RETURNING id
            """,
            name
        )
        logger.info(f"Created new game session: {session_id}")
        return cls(str(session_id), name)
    
    @classmethod
    async def get_active(cls) -> Optional["GameSession"]:
        """Get the currently active session."""
        record = await db.fetchrow(
            "SELECT * FROM game_sessions WHERE is_active = TRUE ORDER BY started_at DESC LIMIT 1"
        )
        if record:
            return cls(str(record["id"]), record["name"])
        return None
    
    @classmethod
    async def get_or_create_active(cls, name: Optional[str] = None) -> "GameSession":
        """Get active session or create a new one."""
        session = await cls.get_active()
        if session:
            return session
        return await cls.create(name)
    
    async def end(self) -> None:
        """End this game session."""
        await db.execute(
            "UPDATE game_sessions SET is_active = FALSE, ended_at = NOW() WHERE id = $1",
            uuid.UUID(self.id)
        )
        logger.info(f"Ended game session: {self.id}")


class Ledger:
    """Transaction ledger for tracking chip movements using PostgreSQL."""
    
    def __init__(self, session_id: str):
        """Initialize ledger for a session.
        
        Args:
            session_id: Unique session identifier.
        """
        self.session_id = session_id
    
    async def record_transaction(
        self,
        user_id: str,
        player_name: str,
        transaction_type: TransactionType,
        amount: int,
        admin_id: Optional[str] = None,
        note: Optional[str] = None,
    ) -> Transaction:
        """Record a chip transaction.
        
        Args:
            user_id: Player's user ID.
            player_name: Player's username.
            transaction_type: Type of transaction.
            amount: Chip amount (positive).
            admin_id: Admin who authorized the transaction.
            note: Optional note about the transaction.
            
        Returns:
            The recorded transaction.
        """
        record = await db.fetchrow(
            """
            INSERT INTO ledger_transactions (session_id, user_id, type, amount, admin_id, note)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING *
            """,
            uuid.UUID(self.session_id),
            uuid.UUID(user_id),
            transaction_type.value,
            amount,
            uuid.UUID(admin_id) if admin_id else None,
            note
        )
        
        transaction = Transaction.from_record(record, player_name)
        
        logger.info(
            f"Recorded {transaction_type.value}: {player_name} "
            f"{'+' if transaction_type != TransactionType.CASH_OUT else '-'}{amount}"
        )
        
        return transaction
    
    async def get_all_transactions(self) -> list[Transaction]:
        """Get all transactions for this session.
        
        Returns:
            List of all transactions.
        """
        records = await db.fetch(
            """
            SELECT t.*, u.username as player_name, a.username as admin_name
            FROM ledger_transactions t
            JOIN users u ON t.user_id = u.id
            LEFT JOIN users a ON t.admin_id = a.id
            WHERE t.session_id = $1
            ORDER BY t.created_at
            """,
            uuid.UUID(self.session_id)
        )
        return [
            Transaction.from_record(r, r["player_name"], r.get("admin_name"))
            for r in records
        ]
    
    async def get_player_transactions(self, user_id: str) -> list[Transaction]:
        """Get all transactions for a specific player.
        
        Args:
            user_id: Player's user ID.
            
        Returns:
            List of player's transactions.
        """
        records = await db.fetch(
            """
            SELECT t.*, u.username as player_name, a.username as admin_name
            FROM ledger_transactions t
            JOIN users u ON t.user_id = u.id
            LEFT JOIN users a ON t.admin_id = a.id
            WHERE t.session_id = $1 AND t.user_id = $2
            ORDER BY t.created_at
            """,
            uuid.UUID(self.session_id),
            uuid.UUID(user_id)
        )
        return [
            Transaction.from_record(r, r["player_name"], r.get("admin_name"))
            for r in records
        ]
    
    async def get_player_summary(self, user_id: str) -> dict:
        """Get summary of player's chip movements.
        
        Args:
            user_id: Player's user ID.
            
        Returns:
            Summary with buy_ins, cash_outs, and net.
        """
        record = await db.fetchrow(
            """
            SELECT 
                u.username as player,
                COALESCE(SUM(CASE WHEN t.type = 'buy_in' THEN t.amount ELSE 0 END), 0) as buy_ins,
                COALESCE(SUM(CASE WHEN t.type = 'cash_out' THEN t.amount ELSE 0 END), 0) as cash_outs,
                COALESCE(SUM(CASE WHEN t.type = 'adjustment' THEN t.amount ELSE 0 END), 0) as adjustments
            FROM users u
            LEFT JOIN ledger_transactions t ON u.id = t.user_id AND t.session_id = $1
            WHERE u.id = $2
            GROUP BY u.id, u.username
            """,
            uuid.UUID(self.session_id),
            uuid.UUID(user_id)
        )
        
        if not record:
            return {"player": "", "buy_ins": 0, "cash_outs": 0, "adjustments": 0, "net": 0}
        
        buy_ins = record["buy_ins"]
        cash_outs = record["cash_outs"]
        adjustments = record["adjustments"]
        
        return {
            "player": record["player"],
            "buy_ins": buy_ins,
            "cash_outs": cash_outs,
            "adjustments": adjustments,
            "net": cash_outs - buy_ins + adjustments,
        }
