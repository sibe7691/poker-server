"""Tests for HTTP API endpoints."""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from httpx import AsyncClient, ASGITransport

# We'll test the API schemas and validation
from src.protocol.messages import (
    parse_client_message,
    AuthMessage,
    RegisterMessage,
    LoginMessage,
    JoinTableMessage,
    ActionMessage,
    CreateTableMessage,
    GiveChipsMessage,
)


class TestMessageParsing:
    """Test client message parsing."""
    
    def test_parse_auth_message(self):
        """Test parsing auth message."""
        data = {"type": "auth", "token": "jwt123"}
        msg = parse_client_message(data)
        
        assert isinstance(msg, AuthMessage)
        assert msg.token == "jwt123"
    
    def test_parse_register_message(self):
        """Test parsing register message."""
        data = {"type": "register", "username": "alice", "password": "secret"}
        msg = parse_client_message(data)
        
        assert isinstance(msg, RegisterMessage)
        assert msg.username == "alice"
        assert msg.password == "secret"
    
    def test_parse_login_message(self):
        """Test parsing login message."""
        data = {"type": "login", "username": "alice", "password": "secret"}
        msg = parse_client_message(data)
        
        assert isinstance(msg, LoginMessage)
        assert msg.username == "alice"
    
    def test_parse_join_table_message(self):
        """Test parsing join table message."""
        data = {"type": "join_table", "table_id": "main", "seat": 3}
        msg = parse_client_message(data)
        
        assert isinstance(msg, JoinTableMessage)
        assert msg.table_id == "main"
        assert msg.seat == 3
    
    def test_parse_join_table_no_seat(self):
        """Test parsing join table without seat."""
        data = {"type": "join_table", "table_id": "main"}
        msg = parse_client_message(data)
        
        assert isinstance(msg, JoinTableMessage)
        assert msg.seat is None
    
    def test_parse_action_message(self):
        """Test parsing action message."""
        data = {"type": "action", "action": "raise", "amount": 100}
        msg = parse_client_message(data)
        
        assert isinstance(msg, ActionMessage)
        assert msg.action == "raise"
        assert msg.amount == 100
    
    def test_parse_action_fold(self):
        """Test parsing fold action."""
        data = {"type": "action", "action": "fold"}
        msg = parse_client_message(data)
        
        assert isinstance(msg, ActionMessage)
        assert msg.action == "fold"
        assert msg.amount == 0
    
    def test_parse_create_table_message(self):
        """Test parsing create table message."""
        data = {
            "type": "create_table",
            "table_id": "high-stakes",
            "small_blind": 5,
            "big_blind": 10,
            "max_players": 6,
        }
        msg = parse_client_message(data)
        
        assert isinstance(msg, CreateTableMessage)
        assert msg.table_id == "high-stakes"
        assert msg.small_blind == 5
        assert msg.big_blind == 10
        assert msg.max_players == 6
    
    def test_parse_create_table_defaults(self):
        """Test create table message with defaults."""
        data = {"type": "create_table", "table_id": "main"}
        msg = parse_client_message(data)
        
        assert msg.small_blind == 1
        assert msg.big_blind == 2
        assert msg.min_players == 2
        assert msg.max_players == 10
    
    def test_parse_give_chips_message(self):
        """Test parsing give chips message."""
        data = {"type": "give_chips", "player": "alice", "amount": 500}
        msg = parse_client_message(data)
        
        assert isinstance(msg, GiveChipsMessage)
        assert msg.player == "alice"
        assert msg.amount == 500
    
    def test_parse_unknown_type(self):
        """Test parsing unknown message type."""
        data = {"type": "unknown_action"}
        
        with pytest.raises(ValueError) as exc_info:
            parse_client_message(data)
        
        assert "Unknown message type" in str(exc_info.value)
    
    def test_parse_missing_type(self):
        """Test parsing message without type."""
        data = {"username": "alice"}
        
        with pytest.raises(ValueError) as exc_info:
            parse_client_message(data)
        
        assert "Unknown message type" in str(exc_info.value)


class TestServerMessages:
    """Test server message models."""
    
    def test_error_message(self):
        """Test error message model."""
        from src.protocol.messages import ErrorMessage
        
        msg = ErrorMessage(message="Something went wrong", code="ERROR_123")
        data = msg.model_dump()
        
        assert data["type"] == "error"
        assert data["message"] == "Something went wrong"
        assert data["code"] == "ERROR_123"
    
    def test_game_state_message(self):
        """Test game state message model."""
        from src.protocol.messages import GameStateMessage
        
        msg = GameStateMessage(
            table_id="main",
            state="preflop",
            hand_number=5,
            dealer_seat=2,
            small_blind=1,
            big_blind=2,
            pot=150,
            community_cards=["Ah", "Kd", "Qs"],
            players=[],
            current_player="user123",
            valid_actions=["fold", "call", "raise"],
            call_amount=50,
            min_raise=100,
        )
        data = msg.model_dump()
        
        assert data["type"] == "game_state"
        assert data["table_id"] == "main"
        assert data["pot"] == 150
        assert len(data["community_cards"]) == 3
    
    def test_table_created_message(self):
        """Test table created message model."""
        from src.protocol.messages import TableCreatedMessage
        
        msg = TableCreatedMessage(
            table_id="high-stakes",
            small_blind=5,
            big_blind=10,
            min_players=2,
            max_players=6,
        )
        data = msg.model_dump()
        
        assert data["type"] == "table_created"
        assert data["table_id"] == "high-stakes"
        assert data["big_blind"] == 10
