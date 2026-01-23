"""PostgreSQL database connection pool."""
from typing import Optional, Any
import asyncpg

from src.config import config
from src.utils.logger import get_logger

logger = get_logger(__name__)


class Database:
    """Async PostgreSQL connection pool manager."""
    
    _instance: Optional["Database"] = None
    _pool: Optional[asyncpg.Pool] = None
    
    def __new__(cls) -> "Database":
        """Singleton pattern for database connection."""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    async def connect(self) -> None:
        """Create connection pool."""
        if self._pool is None:
            self._pool = await asyncpg.create_pool(
                config.database_url,
                min_size=2,
                max_size=10,
            )
            logger.info(f"Connected to PostgreSQL")
    
    async def disconnect(self) -> None:
        """Close connection pool."""
        if self._pool:
            await self._pool.close()
            self._pool = None
            logger.info("Disconnected from PostgreSQL")
    
    @property
    def pool(self) -> asyncpg.Pool:
        """Get connection pool, raise if not connected."""
        if self._pool is None:
            raise RuntimeError("Database not connected. Call connect() first.")
        return self._pool
    
    async def execute(self, query: str, *args: Any) -> str:
        """Execute a query without returning results."""
        async with self.pool.acquire() as conn:
            return await conn.execute(query, *args)
    
    async def fetch(self, query: str, *args: Any) -> list[asyncpg.Record]:
        """Execute a query and return all results."""
        async with self.pool.acquire() as conn:
            return await conn.fetch(query, *args)
    
    async def fetchrow(self, query: str, *args: Any) -> Optional[asyncpg.Record]:
        """Execute a query and return first result."""
        async with self.pool.acquire() as conn:
            return await conn.fetchrow(query, *args)
    
    async def fetchval(self, query: str, *args: Any) -> Any:
        """Execute a query and return first column of first result."""
        async with self.pool.acquire() as conn:
            return await conn.fetchval(query, *args)


# Global instance
db = Database()
