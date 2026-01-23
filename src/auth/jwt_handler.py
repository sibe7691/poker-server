"""JWT token handling."""
import jwt
from datetime import datetime, timedelta, timezone
from typing import Optional
from dataclasses import dataclass

from src.config import config
from src.auth.roles import Role


@dataclass
class TokenPayload:
    """Decoded token payload."""
    user_id: str
    username: str
    role: Role
    token_type: str  # "access" or "refresh"
    exp: datetime
    iat: datetime


class TokenError(Exception):
    """Token validation error."""
    pass


def create_access_token(user_id: str, username: str, role: Role) -> str:
    """Create a short-lived access token.
    
    Args:
        user_id: Unique user identifier.
        username: User's display name.
        role: User's role (player/admin).
        
    Returns:
        Encoded JWT access token.
    """
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "username": username,
        "role": role.value,
        "type": "access",
        "iat": now,
        "exp": now + timedelta(minutes=config.jwt_access_expiry_minutes),
    }
    return jwt.encode(payload, config.jwt_secret, algorithm=config.jwt_algorithm)


def create_refresh_token(user_id: str, username: str, role: Role) -> str:
    """Create a long-lived refresh token.
    
    Args:
        user_id: Unique user identifier.
        username: User's display name.
        role: User's role (player/admin).
        
    Returns:
        Encoded JWT refresh token.
    """
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "username": username,
        "role": role.value,
        "type": "refresh",
        "iat": now,
        "exp": now + timedelta(days=config.jwt_refresh_expiry_days),
    }
    return jwt.encode(payload, config.jwt_secret, algorithm=config.jwt_algorithm)


def verify_token(token: str, expected_type: Optional[str] = None) -> TokenPayload:
    """Verify and decode a JWT token.
    
    Args:
        token: The JWT token to verify.
        expected_type: If provided, verify token is of this type ("access" or "refresh").
        
    Returns:
        Decoded token payload.
        
    Raises:
        TokenError: If token is invalid, expired, or wrong type.
    """
    try:
        payload = jwt.decode(
            token, 
            config.jwt_secret, 
            algorithms=[config.jwt_algorithm]
        )
    except jwt.ExpiredSignatureError:
        raise TokenError("Token has expired")
    except jwt.InvalidTokenError as e:
        raise TokenError(f"Invalid token: {e}")
    
    token_type = payload.get("type")
    if expected_type and token_type != expected_type:
        raise TokenError(f"Expected {expected_type} token, got {token_type}")
    
    return TokenPayload(
        user_id=payload["sub"],
        username=payload["username"],
        role=Role(payload["role"]),
        token_type=token_type,
        exp=datetime.fromtimestamp(payload["exp"], tz=timezone.utc),
        iat=datetime.fromtimestamp(payload["iat"], tz=timezone.utc),
    )


def refresh_access_token(refresh_token: str) -> str:
    """Create a new access token using a refresh token.
    
    Args:
        refresh_token: Valid refresh token.
        
    Returns:
        New access token.
        
    Raises:
        TokenError: If refresh token is invalid.
    """
    payload = verify_token(refresh_token, expected_type="refresh")
    return create_access_token(payload.user_id, payload.username, payload.role)
