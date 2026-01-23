"""Session persistence for reconnection support."""
import json
from datetime import datetime, timezone
from typing import Optional
from dataclasses import dataclass

from src.state.redis_client import redis_client
from src.config import config
from src.utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class PlayerSession:
    """Player's active session state for reconnection."""
    user_id: str
    username: str
    table_id: str
    seat: int
    chips: int
    hole_cards: list[str]  # Serialized cards
    is_folded: bool
    current_bet: int
    disconnected_at: Optional[str] = None
    
    def to_dict(self) -> dict:
        """Convert to dictionary for storage."""
        return {
            "user_id": self.user_id,
            "username": self.username,
            "table_id": self.table_id,
            "seat": self.seat,
            "chips": self.chips,
            "hole_cards": self.hole_cards,
            "is_folded": self.is_folded,
            "current_bet": self.current_bet,
            "disconnected_at": self.disconnected_at,
        }
    
    @classmethod
    def from_dict(cls, data: dict) -> "PlayerSession":
        """Create from dictionary."""
        return cls(
            user_id=data["user_id"],
            username=data["username"],
            table_id=data["table_id"],
            seat=data["seat"],
            chips=data["chips"],
            hole_cards=data["hole_cards"],
            is_folded=data["is_folded"],
            current_bet=data["current_bet"],
            disconnected_at=data.get("disconnected_at"),
        )


class SessionStore:
    """Manages player sessions for reconnection support."""
    
    def _session_key(self, user_id: str) -> str:
        """Get Redis key for user's session."""
        return f"session:{user_id}:table"
    
    def _disconnected_key(self, table_id: str) -> str:
        """Get Redis key for disconnected players on a table."""
        return f"table:{table_id}:disconnected"
    
    async def save_session(self, session: PlayerSession) -> None:
        """Save a player's session state.
        
        Args:
            session: Player session to save.
        """
        key = self._session_key(session.user_id)
        await redis_client.set_json(key, session.to_dict())
        logger.debug(f"Saved session for {session.username} at table {session.table_id}")
    
    async def get_session(self, user_id: str) -> Optional[PlayerSession]:
        """Get a player's active session.
        
        Args:
            user_id: User's ID.
            
        Returns:
            Player session if exists, None otherwise.
        """
        key = self._session_key(user_id)
        data = await redis_client.get_json(key)
        if data is None:
            return None
        return PlayerSession.from_dict(data)
    
    async def delete_session(self, user_id: str) -> None:
        """Delete a player's session.
        
        Args:
            user_id: User's ID.
        """
        key = self._session_key(user_id)
        await redis_client.delete(key)
        logger.debug(f"Deleted session for user {user_id}")
    
    async def mark_disconnected(
        self, 
        user_id: str, 
        table_id: str,
        grace_seconds: Optional[int] = None
    ) -> None:
        """Mark a player as disconnected with grace period.
        
        Args:
            user_id: User's ID.
            table_id: Table ID.
            grace_seconds: Grace period in seconds (uses config default if not provided).
        """
        grace = grace_seconds or config.reconnect_grace_seconds
        
        # Update session with disconnect time
        session = await self.get_session(user_id)
        if session:
            session.disconnected_at = datetime.now(timezone.utc).isoformat()
            await self.save_session(session)
        
        # Add to disconnected set with expiry
        key = self._disconnected_key(table_id)
        disconnect_data = {
            "user_id": user_id,
            "disconnected_at": datetime.now(timezone.utc).isoformat(),
            "grace_expires": (
                datetime.now(timezone.utc).timestamp() + grace
            ),
        }
        await redis_client.hset(key, user_id, json.dumps(disconnect_data))
        
        logger.info(f"Marked user {user_id} as disconnected (grace: {grace}s)")
    
    async def mark_reconnected(self, user_id: str, table_id: str) -> bool:
        """Mark a player as reconnected if within grace period.
        
        Args:
            user_id: User's ID.
            table_id: Table ID.
            
        Returns:
            True if reconnected within grace period, False otherwise.
        """
        key = self._disconnected_key(table_id)
        data = await redis_client.hget(key, user_id)
        
        if data is None:
            # Not in disconnected list
            return False
        
        disconnect_info = json.loads(data)
        now = datetime.now(timezone.utc).timestamp()
        
        if now > disconnect_info["grace_expires"]:
            # Grace period expired
            logger.info(f"User {user_id} reconnection failed - grace period expired")
            return False
        
        # Within grace period - remove from disconnected list
        await redis_client.hdel(key, user_id)
        
        # Update session
        session = await self.get_session(user_id)
        if session:
            session.disconnected_at = None
            await self.save_session(session)
        
        logger.info(f"User {user_id} reconnected successfully")
        return True
    
    async def get_disconnected_players(self, table_id: str) -> list[dict]:
        """Get all disconnected players for a table.
        
        Args:
            table_id: Table ID.
            
        Returns:
            List of disconnected player info with remaining grace time.
        """
        key = self._disconnected_key(table_id)
        data = await redis_client.hgetall(key)
        
        now = datetime.now(timezone.utc).timestamp()
        result = []
        
        for user_id, info_str in data.items():
            info = json.loads(info_str)
            remaining = max(0, info["grace_expires"] - now)
            result.append({
                "user_id": user_id,
                "disconnected_at": info["disconnected_at"],
                "grace_remaining": int(remaining),
            })
        
        return result
    
    async def cleanup_expired(self, table_id: str) -> list[str]:
        """Remove players whose grace period has expired.
        
        Args:
            table_id: Table ID.
            
        Returns:
            List of user IDs that were removed.
        """
        key = self._disconnected_key(table_id)
        data = await redis_client.hgetall(key)
        
        now = datetime.now(timezone.utc).timestamp()
        expired = []
        
        for user_id, info_str in data.items():
            info = json.loads(info_str)
            if now > info["grace_expires"]:
                expired.append(user_id)
                await redis_client.hdel(key, user_id)
                await self.delete_session(user_id)
                logger.info(f"Cleaned up expired session for user {user_id}")
        
        return expired


session_store = SessionStore()
