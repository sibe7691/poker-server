"""Tests for reconnection logic."""
import pytest
from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch

from src.state.session_store import SessionStore, PlayerSession
from src.config import config


class TestPlayerSession:
    """Test PlayerSession model."""
    
    def test_to_dict(self):
        """Test serialization."""
        session = PlayerSession(
            user_id="user123",
            username="alice",
            table_id="table1",
            seat=3,
            chips=500,
            hole_cards=["Ah", "Ks"],
            is_folded=False,
            current_bet=50,
        )
        
        data = session.to_dict()
        
        assert data["user_id"] == "user123"
        assert data["username"] == "alice"
        assert data["chips"] == 500
        assert data["hole_cards"] == ["Ah", "Ks"]
    
    def test_from_dict(self):
        """Test deserialization."""
        data = {
            "user_id": "user123",
            "username": "alice",
            "table_id": "table1",
            "seat": 3,
            "chips": 500,
            "hole_cards": ["Ah", "Ks"],
            "is_folded": False,
            "current_bet": 50,
            "disconnected_at": None,
        }
        
        session = PlayerSession.from_dict(data)
        
        assert session.user_id == "user123"
        assert session.username == "alice"
        assert session.chips == 500


class TestSessionStore:
    """Test session store operations."""
    
    @pytest.fixture
    def store(self):
        """Create a session store."""
        return SessionStore()
    
    @pytest.mark.asyncio
    async def test_save_and_get_session(self, store):
        """Test saving and retrieving a session."""
        session = PlayerSession(
            user_id="user123",
            username="alice",
            table_id="table1",
            seat=3,
            chips=500,
            hole_cards=["Ah", "Ks"],
            is_folded=False,
            current_bet=50,
        )
        
        # Mock Redis client
        with patch("src.state.session_store.redis_client") as mock_redis:
            mock_redis.set_json = AsyncMock()
            mock_redis.get_json = AsyncMock(return_value=session.to_dict())
            
            await store.save_session(session)
            retrieved = await store.get_session("user123")
            
            assert retrieved is not None
            assert retrieved.user_id == "user123"
            assert retrieved.chips == 500
    
    @pytest.mark.asyncio
    async def test_get_nonexistent_session(self, store):
        """Test getting a non-existent session."""
        with patch("src.state.session_store.redis_client") as mock_redis:
            mock_redis.get_json = AsyncMock(return_value=None)
            
            session = await store.get_session("nonexistent")
            assert session is None
    
    @pytest.mark.asyncio
    async def test_mark_disconnected(self, store):
        """Test marking a player as disconnected."""
        session = PlayerSession(
            user_id="user123",
            username="alice",
            table_id="table1",
            seat=3,
            chips=500,
            hole_cards=[],
            is_folded=False,
            current_bet=0,
        )
        
        with patch("src.state.session_store.redis_client") as mock_redis:
            mock_redis.get_json = AsyncMock(return_value=session.to_dict())
            mock_redis.set_json = AsyncMock()
            mock_redis.hset = AsyncMock()
            
            await store.mark_disconnected("user123", "table1", grace_seconds=60)
            
            # Should have saved session with disconnect time
            mock_redis.set_json.assert_called()
            # Should have added to disconnected hash
            mock_redis.hset.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_mark_reconnected_within_grace(self, store):
        """Test reconnecting within grace period."""
        import json
        import time
        
        with patch("src.state.session_store.redis_client") as mock_redis:
            # Simulate disconnection 30 seconds ago with 60s grace
            disconnect_data = {
                "user_id": "user123",
                "disconnected_at": datetime.now(timezone.utc).isoformat(),
                "grace_expires": time.time() + 30,  # 30s remaining
            }
            mock_redis.hget = AsyncMock(return_value=json.dumps(disconnect_data))
            mock_redis.hdel = AsyncMock()
            mock_redis.get_json = AsyncMock(return_value={
                "user_id": "user123",
                "username": "alice",
                "table_id": "table1",
                "seat": 3,
                "chips": 500,
                "hole_cards": [],
                "is_folded": False,
                "current_bet": 0,
                "disconnected_at": datetime.now(timezone.utc).isoformat(),
            })
            mock_redis.set_json = AsyncMock()
            
            result = await store.mark_reconnected("user123", "table1")
            
            assert result is True
            mock_redis.hdel.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_mark_reconnected_after_grace(self, store):
        """Test reconnecting after grace period expired."""
        import json
        import time
        
        with patch("src.state.session_store.redis_client") as mock_redis:
            # Simulate disconnection with expired grace
            disconnect_data = {
                "user_id": "user123",
                "disconnected_at": datetime.now(timezone.utc).isoformat(),
                "grace_expires": time.time() - 10,  # Expired 10s ago
            }
            mock_redis.hget = AsyncMock(return_value=json.dumps(disconnect_data))
            
            result = await store.mark_reconnected("user123", "table1")
            
            assert result is False
    
    @pytest.mark.asyncio
    async def test_cleanup_expired(self, store):
        """Test cleaning up expired disconnections."""
        import json
        import time
        
        with patch("src.state.session_store.redis_client") as mock_redis:
            # Two disconnections: one expired, one still valid
            disconnect_data = {
                "user1": json.dumps({
                    "user_id": "user1",
                    "disconnected_at": datetime.now(timezone.utc).isoformat(),
                    "grace_expires": time.time() - 10,  # Expired
                }),
                "user2": json.dumps({
                    "user_id": "user2",
                    "disconnected_at": datetime.now(timezone.utc).isoformat(),
                    "grace_expires": time.time() + 30,  # Still valid
                }),
            }
            mock_redis.hgetall = AsyncMock(return_value=disconnect_data)
            mock_redis.hdel = AsyncMock()
            mock_redis.delete = AsyncMock()
            
            expired = await store.cleanup_expired("table1")
            
            assert "user1" in expired
            assert "user2" not in expired
