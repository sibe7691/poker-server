"""Calculate player standings (+/-)."""
import uuid
from dataclasses import dataclass

from src.db.connection import db
from src.utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class PlayerStanding:
    """A player's standing in the session."""
    user_id: str
    player: str
    buy_ins: int
    cash_outs: int
    adjustments: int
    net: int
    
    def to_dict(self) -> dict:
        """Convert to dictionary."""
        return {
            "user_id": self.user_id,
            "player": self.player,
            "buy_ins": self.buy_ins,
            "cash_outs": self.cash_outs,
            "adjustments": self.adjustments,
            "net": self.net,
        }


async def calculate_standings(session_id: str) -> list[PlayerStanding]:
    """Calculate standings for all players in a session.
    
    Args:
        session_id: The session ID.
        
    Returns:
        List of player standings sorted by net (descending).
    """
    records = await db.fetch(
        """
        SELECT 
            u.id as user_id,
            u.username as player,
            COALESCE(SUM(CASE WHEN t.type = 'buy_in' THEN t.amount ELSE 0 END), 0) as buy_ins,
            COALESCE(SUM(CASE WHEN t.type = 'cash_out' THEN t.amount ELSE 0 END), 0) as cash_outs,
            COALESCE(SUM(CASE WHEN t.type = 'adjustment' THEN t.amount ELSE 0 END), 0) as adjustments
        FROM ledger_transactions t
        JOIN users u ON t.user_id = u.id
        WHERE t.session_id = $1
        GROUP BY u.id, u.username
        ORDER BY (
            COALESCE(SUM(CASE WHEN t.type = 'cash_out' THEN t.amount ELSE 0 END), 0) -
            COALESCE(SUM(CASE WHEN t.type = 'buy_in' THEN t.amount ELSE 0 END), 0) +
            COALESCE(SUM(CASE WHEN t.type = 'adjustment' THEN t.amount ELSE 0 END), 0)
        ) DESC
        """,
        uuid.UUID(session_id)
    )
    
    standings = []
    for r in records:
        buy_ins = r["buy_ins"]
        cash_outs = r["cash_outs"]
        adjustments = r["adjustments"]
        net = cash_outs - buy_ins + adjustments
        
        standings.append(PlayerStanding(
            user_id=str(r["user_id"]),
            player=r["player"],
            buy_ins=buy_ins,
            cash_outs=cash_outs,
            adjustments=adjustments,
            net=net,
        ))
    
    return standings


def format_standings_table(standings: list[PlayerStanding]) -> str:
    """Format standings as a text table.
    
    Args:
        standings: List of player standings.
        
    Returns:
        Formatted table string.
    """
    if not standings:
        return "No transactions recorded."
    
    lines = [
        "| Player     | Buy-ins | Cash-outs | Net (+/-) |",
        "|------------|---------|-----------|-----------|",
    ]
    
    for s in standings:
        net_str = f"+{s.net}" if s.net >= 0 else str(s.net)
        lines.append(
            f"| {s.player:<10} | {s.buy_ins:>7} | {s.cash_outs:>9} | {net_str:>9} |"
        )
    
    return "\n".join(lines)
