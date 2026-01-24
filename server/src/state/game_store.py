"""Game state persistence."""
import json
from typing import Optional, Any
from datetime import datetime, timezone

from src.state.redis_client import redis_client
from src.utils.logger import get_logger

logger = get_logger(__name__)


class GameStore:
    """Persists game/table state to Redis."""
    
    def _table_key(self, table_id: str) -> str:
        """Get Redis key for table state."""
        return f"table:{table_id}"
    
    def _players_key(self, table_id: str) -> str:
        """Get Redis key for table players set."""
        return f"table:{table_id}:players"
    
    async def save_table_state(self, table_id: str, state: dict) -> None:
        """Save complete table state.
        
        Args:
            table_id: Table identifier.
            state: Serialized table state.
        """
        state["_saved_at"] = datetime.now(timezone.utc).isoformat()
        await redis_client.set_json(self._table_key(table_id), state)
        logger.debug(f"Saved table state for {table_id}")
    
    async def get_table_state(self, table_id: str) -> Optional[dict]:
        """Get table state.
        
        Args:
            table_id: Table identifier.
            
        Returns:
            Table state if exists, None otherwise.
        """
        return await redis_client.get_json(self._table_key(table_id))
    
    async def delete_table(self, table_id: str) -> None:
        """Delete a table and all associated data.
        
        Args:
            table_id: Table identifier.
        """
        await redis_client.delete(self._table_key(table_id))
        await redis_client.delete(self._players_key(table_id))
        await redis_client.delete(f"table:{table_id}:disconnected")
        logger.info(f"Deleted table {table_id}")
    
    async def add_player_to_table(self, table_id: str, user_id: str) -> None:
        """Add a player to a table's player set.
        
        Args:
            table_id: Table identifier.
            user_id: User's ID.
        """
        await redis_client.sadd(self._players_key(table_id), user_id)
    
    async def remove_player_from_table(self, table_id: str, user_id: str) -> None:
        """Remove a player from a table's player set.
        
        Args:
            table_id: Table identifier.
            user_id: User's ID.
        """
        await redis_client.srem(self._players_key(table_id), user_id)
    
    async def get_table_players(self, table_id: str) -> set[str]:
        """Get all player IDs at a table.
        
        Args:
            table_id: Table identifier.
            
        Returns:
            Set of user IDs.
        """
        return await redis_client.smembers(self._players_key(table_id))
    
    async def is_player_at_table(self, table_id: str, user_id: str) -> bool:
        """Check if a player is at a table.
        
        Args:
            table_id: Table identifier.
            user_id: User's ID.
            
        Returns:
            True if player is at table.
        """
        return await redis_client.sismember(self._players_key(table_id), user_id)
    
    async def list_tables(self) -> list[str]:
        """List all active tables.
        
        Returns:
            List of table IDs.
        """
        keys = await redis_client.redis.keys("table:*")
        # Filter out sub-keys like table:x:players
        table_ids = set()
        for key in keys:
            parts = key.split(":")
            if len(parts) == 2:  # table:{id}
                table_ids.add(parts[1])
        return list(table_ids)


game_store = GameStore()
