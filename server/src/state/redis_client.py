"""Async Redis client wrapper."""
from __future__ import annotations
import json
from typing import Any, Optional
from redis.asyncio import Redis, from_url

from src.config import config
from src.utils.logger import get_logger

logger = get_logger(__name__)


class RedisClient:
    """Async Redis client wrapper with JSON serialization."""
    
    _instance: Optional["RedisClient"] = None
    _redis: Optional[Redis] = None
    
    def __new__(cls) -> "RedisClient":
        """Singleton pattern for Redis client."""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    async def connect(self) -> None:
        """Connect to Redis."""
        if self._redis is None:
            self._redis = await from_url(
                config.redis_url,
                encoding="utf-8",
                decode_responses=True
            )
            logger.info(f"Connected to Redis at {config.redis_url}")
    
    async def disconnect(self) -> None:
        """Disconnect from Redis."""
        if self._redis:
            await self._redis.close()
            self._redis = None
            logger.info("Disconnected from Redis")
    
    @property
    def redis(self) -> Redis:
        """Get Redis connection, raise if not connected."""
        if self._redis is None:
            raise RuntimeError("Redis not connected. Call connect() first.")
        return self._redis
    
    # Basic operations
    async def get(self, key: str) -> Optional[str]:
        """Get a string value."""
        return await self.redis.get(key)
    
    async def set(self, key: str, value: str, ex: Optional[int] = None) -> None:
        """Set a string value with optional expiry in seconds."""
        await self.redis.set(key, value, ex=ex)
    
    async def delete(self, key: str) -> None:
        """Delete a key."""
        await self.redis.delete(key)
    
    async def exists(self, key: str) -> bool:
        """Check if a key exists."""
        return await self.redis.exists(key) > 0
    
    # JSON operations
    async def get_json(self, key: str) -> Optional[Any]:
        """Get and deserialize JSON value."""
        value = await self.get(key)
        if value is None:
            return None
        return json.loads(value)
    
    async def set_json(self, key: str, value: Any, ex: Optional[int] = None) -> None:
        """Serialize and set JSON value."""
        await self.set(key, json.dumps(value), ex=ex)
    
    # Hash operations
    async def hget(self, key: str, field: str) -> Optional[str]:
        """Get a hash field value."""
        return await self.redis.hget(key, field)
    
    async def hset(self, key: str, field: str, value: str) -> None:
        """Set a hash field value."""
        await self.redis.hset(key, field, value)
    
    async def hgetall(self, key: str) -> dict[str, str]:
        """Get all hash fields."""
        return await self.redis.hgetall(key)
    
    async def hdel(self, key: str, field: str) -> None:
        """Delete a hash field."""
        await self.redis.hdel(key, field)
    
    # Set operations
    async def sadd(self, key: str, *members: str) -> None:
        """Add members to a set."""
        await self.redis.sadd(key, *members)
    
    async def srem(self, key: str, *members: str) -> None:
        """Remove members from a set."""
        await self.redis.srem(key, *members)
    
    async def smembers(self, key: str) -> set[str]:
        """Get all members of a set."""
        return await self.redis.smembers(key)
    
    async def sismember(self, key: str, member: str) -> bool:
        """Check if member is in set."""
        return await self.redis.sismember(key, member)
    
    # List operations
    async def lpush(self, key: str, *values: str) -> None:
        """Push values to the left of a list."""
        await self.redis.lpush(key, *values)
    
    async def rpush(self, key: str, *values: str) -> None:
        """Push values to the right of a list."""
        await self.redis.rpush(key, *values)
    
    async def lrange(self, key: str, start: int, stop: int) -> list[str]:
        """Get a range of list elements."""
        return await self.redis.lrange(key, start, stop)
    
    # Expiry
    async def expire(self, key: str, seconds: int) -> None:
        """Set expiry on a key."""
        await self.redis.expire(key, seconds)
    
    async def ttl(self, key: str) -> int:
        """Get time to live for a key."""
        return await self.redis.ttl(key)


# Global instance
redis_client = RedisClient()
