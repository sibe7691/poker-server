"""Tests for authentication module."""
import pytest
from datetime import datetime, timezone, timedelta

from src.auth.password import hash_password, verify_password
from src.auth.roles import Role
from src.auth.jwt_handler import (
    create_access_token,
    create_refresh_token,
    verify_token,
    refresh_access_token,
    TokenError,
)


class TestPasswordHashing:
    """Test password hashing utilities."""
    
    def test_hash_password(self):
        """Test password hashing produces different hash."""
        password = "secret123"
        hashed = hash_password(password)
        
        assert hashed != password
        assert len(hashed) > 20  # bcrypt hashes are ~60 chars
    
    def test_hash_password_different_each_time(self):
        """Test same password produces different hashes (due to salt)."""
        password = "secret123"
        hash1 = hash_password(password)
        hash2 = hash_password(password)
        
        assert hash1 != hash2
    
    def test_verify_password_correct(self):
        """Test verifying correct password."""
        password = "secret123"
        hashed = hash_password(password)
        
        assert verify_password(password, hashed) is True
    
    def test_verify_password_incorrect(self):
        """Test verifying incorrect password."""
        password = "secret123"
        hashed = hash_password(password)
        
        assert verify_password("wrongpassword", hashed) is False
    
    def test_verify_password_empty(self):
        """Test empty password fails."""
        hashed = hash_password("secret123")
        
        assert verify_password("", hashed) is False


class TestJWTTokens:
    """Test JWT token handling."""
    
    def test_create_access_token(self):
        """Test creating access token."""
        token = create_access_token("user123", "alice", Role.PLAYER)
        
        assert isinstance(token, str)
        assert len(token) > 50  # JWT tokens are long
    
    def test_create_refresh_token(self):
        """Test creating refresh token."""
        token = create_refresh_token("user123", "alice", Role.PLAYER)
        
        assert isinstance(token, str)
        assert len(token) > 50
    
    def test_verify_access_token(self):
        """Test verifying valid access token."""
        token = create_access_token("user123", "alice", Role.PLAYER)
        payload = verify_token(token, expected_type="access")
        
        assert payload.user_id == "user123"
        assert payload.username == "alice"
        assert payload.role == Role.PLAYER
        assert payload.token_type == "access"
    
    def test_verify_refresh_token(self):
        """Test verifying valid refresh token."""
        token = create_refresh_token("user123", "alice", Role.ADMIN)
        payload = verify_token(token, expected_type="refresh")
        
        assert payload.user_id == "user123"
        assert payload.username == "alice"
        assert payload.role == Role.ADMIN
        assert payload.token_type == "refresh"
    
    def test_verify_token_wrong_type(self):
        """Test verifying token with wrong expected type."""
        token = create_access_token("user123", "alice", Role.PLAYER)
        
        with pytest.raises(TokenError) as exc_info:
            verify_token(token, expected_type="refresh")
        
        assert "Expected refresh token" in str(exc_info.value)
    
    def test_verify_invalid_token(self):
        """Test verifying invalid token."""
        with pytest.raises(TokenError):
            verify_token("invalid.token.here")
    
    def test_refresh_access_token(self):
        """Test refreshing access token."""
        refresh = create_refresh_token("user123", "alice", Role.PLAYER)
        new_access = refresh_access_token(refresh)
        
        payload = verify_token(new_access, expected_type="access")
        assert payload.user_id == "user123"
        assert payload.username == "alice"
    
    def test_refresh_with_access_token_fails(self):
        """Test cannot refresh using access token."""
        access = create_access_token("user123", "alice", Role.PLAYER)
        
        with pytest.raises(TokenError) as exc_info:
            refresh_access_token(access)
        
        assert "Expected refresh token" in str(exc_info.value)


class TestRoles:
    """Test role definitions."""
    
    def test_role_values(self):
        """Test role enum values."""
        assert Role.PLAYER.value == "player"
        assert Role.ADMIN.value == "admin"
    
    def test_role_from_string(self):
        """Test creating role from string."""
        assert Role("player") == Role.PLAYER
        assert Role("admin") == Role.ADMIN
    
    def test_role_comparison(self):
        """Test role comparison."""
        assert Role.PLAYER != Role.ADMIN
