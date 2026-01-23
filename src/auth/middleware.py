"""WebSocket authentication middleware."""
from typing import Optional
from dataclasses import dataclass

from src.auth.jwt_handler import verify_token, TokenPayload, TokenError
from src.auth.roles import Role
from src.state.redis_client import redis_client
from src.utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class AuthenticatedUser:
    """Authenticated user context."""
    user_id: str
    username: str
    role: Role
    token: str


class AuthMiddleware:
    """WebSocket authentication middleware."""
    
    async def authenticate(self, token: str) -> AuthenticatedUser:
        """Authenticate a WebSocket connection using JWT.
        
        Args:
            token: JWT access token from client.
            
        Returns:
            Authenticated user context.
            
        Raises:
            TokenError: If authentication fails.
        """
        # Verify the token
        payload = verify_token(token, expected_type="access")
        
        # Check if token is revoked
        revoked_key = f"revoked:{token[:32]}"
        if await redis_client.exists(revoked_key):
            raise TokenError("Token has been revoked")
        
        logger.info(f"User {payload.username} authenticated")
        
        return AuthenticatedUser(
            user_id=payload.user_id,
            username=payload.username,
            role=payload.role,
            token=token,
        )
    
    async def revoke_token(self, token: str) -> None:
        """Revoke a token (logout).
        
        Args:
            token: Token to revoke.
        """
        # Store revocation with TTL matching token expiry
        try:
            payload = verify_token(token)
            ttl = int((payload.exp - payload.iat).total_seconds())
            revoked_key = f"revoked:{token[:32]}"
            await redis_client.set(revoked_key, "1", ex=ttl)
            logger.info(f"Token revoked for user {payload.username}")
        except TokenError:
            # Token already expired, no need to revoke
            pass
    
    def check_role(self, user: AuthenticatedUser, required_role: Role) -> bool:
        """Check if user has required role.
        
        Args:
            user: Authenticated user context.
            required_role: Role to check for.
            
        Returns:
            True if user has required role or is admin.
        """
        if user.role == Role.ADMIN:
            return True
        return user.role == required_role


auth_middleware = AuthMiddleware()
