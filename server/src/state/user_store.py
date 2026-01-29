"""User persistence store using PostgreSQL."""
import uuid
import secrets
from typing import Optional
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta

from src.db.connection import db
from src.auth.password import hash_password, verify_password
from src.auth.roles import Role
from src.auth.jwt_handler import create_access_token, create_refresh_token
from src.utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class User:
    """User model."""
    id: str
    username: str
    email: str
    password_hash: str
    role: Role
    created_at: datetime
    
    @classmethod
    def from_record(cls, record) -> "User":
        """Create from database record."""
        return cls(
            id=str(record["id"]),
            username=record["username"],
            email=record["email"],
            password_hash=record["password_hash"],
            role=Role(record["role"]),
            created_at=record["created_at"],
        )


@dataclass
class AuthTokens:
    """Authentication tokens."""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class UserStore:
    """User persistence and authentication using PostgreSQL."""
    
    async def register(
        self, 
        username: str, 
        email: str,
        password: str, 
        role: Role = Role.PLAYER
    ) -> AuthTokens:
        """Register a new user.
        
        Args:
            username: Unique username (displayed in game).
            email: Unique email address (used for login).
            password: Plain text password.
            role: User role (defaults to player).
            
        Returns:
            Authentication tokens.
            
        Raises:
            ValueError: If username or email already exists.
        """
        # Check if username exists
        existing = await db.fetchrow(
            "SELECT id FROM users WHERE LOWER(username) = LOWER($1)",
            username
        )
        if existing:
            raise ValueError(f"Username '{username}' already exists")
        
        # Check if email exists
        existing_email = await db.fetchrow(
            "SELECT id FROM users WHERE LOWER(email) = LOWER($1)",
            email
        )
        if existing_email:
            raise ValueError(f"Email '{email}' is already registered")
        
        # Create user
        user_id = uuid.uuid4()
        pw_hash = hash_password(password)
        
        await db.execute(
            """
            INSERT INTO users (id, username, email, password_hash, role)
            VALUES ($1, $2, $3, $4, $5)
            """,
            user_id, username, email.lower(), pw_hash, role.value
        )
        
        logger.info(f"Registered new user: {username} ({email}, role: {role.value})")
        
        # Return tokens
        return AuthTokens(
            access_token=create_access_token(str(user_id), username, role),
            refresh_token=create_refresh_token(str(user_id), username, role),
        )
    
    async def login(self, email: str, password: str) -> AuthTokens:
        """Authenticate a user and return tokens.
        
        Args:
            email: User's email address.
            password: Plain text password.
            
        Returns:
            Authentication tokens.
            
        Raises:
            ValueError: If credentials are invalid.
        """
        record = await db.fetchrow(
            "SELECT * FROM users WHERE LOWER(email) = LOWER($1)",
            email
        )
        if record is None:
            raise ValueError("Invalid email or password")
        
        user = User.from_record(record)
        
        # Verify password
        if not verify_password(password, user.password_hash):
            raise ValueError("Invalid email or password")
        
        logger.info(f"User logged in: {user.username} ({email})")
        
        # Return tokens
        return AuthTokens(
            access_token=create_access_token(user.id, user.username, user.role),
            refresh_token=create_refresh_token(user.id, user.username, user.role),
        )
    
    async def get_user(self, username: str) -> Optional[User]:
        """Get user by username.
        
        Args:
            username: User's username.
            
        Returns:
            User if found, None otherwise.
        """
        record = await db.fetchrow(
            "SELECT * FROM users WHERE LOWER(username) = LOWER($1)",
            username
        )
        if record is None:
            return None
        return User.from_record(record)
    
    async def get_user_by_id(self, user_id: str) -> Optional[User]:
        """Get user by ID.
        
        Args:
            user_id: User's ID.
            
        Returns:
            User if found, None otherwise.
        """
        try:
            record = await db.fetchrow(
                "SELECT * FROM users WHERE id = $1",
                uuid.UUID(user_id)
            )
            if record is None:
                return None
            return User.from_record(record)
        except ValueError:
            return None
    
    async def update_role(self, username: str, role: Role) -> None:
        """Update a user's role.
        
        Args:
            username: User's username.
            role: New role to assign.
            
        Raises:
            ValueError: If user not found.
        """
        result = await db.execute(
            "UPDATE users SET role = $1 WHERE LOWER(username) = LOWER($2)",
            role.value, username
        )
        
        if result == "UPDATE 0":
            raise ValueError(f"User '{username}' not found")
        
        logger.info(f"Updated role for {username} to {role.value}")
    
    async def list_users(self) -> list[User]:
        """List all users.
        
        Returns:
            List of all users.
        """
        records = await db.fetch("SELECT * FROM users ORDER BY created_at")
        return [User.from_record(r) for r in records]
    
    async def get_user_by_email(self, email: str) -> Optional[User]:
        """Get user by email.
        
        Args:
            email: User's email address.
            
        Returns:
            User if found, None otherwise.
        """
        record = await db.fetchrow(
            "SELECT * FROM users WHERE LOWER(email) = LOWER($1)",
            email
        )
        if record is None:
            return None
        return User.from_record(record)
    
    async def request_password_reset(self, email: str) -> Optional[str]:
        """Generate a password reset token for a user.
        
        Args:
            email: User's email address.
            
        Returns:
            Reset token if user exists, None otherwise.
            
        Note:
            In a production system, this would send an email with the reset link.
            For now, it just returns the token which can be used for testing.
        """
        user = await self.get_user_by_email(email)
        if user is None:
            # Don't reveal whether email exists - return None silently
            logger.info(f"Password reset requested for non-existent email: {email}")
            return None
        
        # Generate secure token
        reset_token = secrets.token_urlsafe(32)
        expires_at = datetime.now(timezone.utc) + timedelta(hours=1)
        
        await db.execute(
            """
            UPDATE users 
            SET password_reset_token = $1, password_reset_expires = $2
            WHERE LOWER(email) = LOWER($3)
            """,
            reset_token, expires_at, email
        )
        
        logger.info(f"Password reset token generated for user: {user.username}")
        
        return reset_token
    
    async def reset_password(self, token: str, new_password: str) -> bool:
        """Reset a user's password using a reset token.
        
        Args:
            token: Password reset token.
            new_password: New plain text password.
            
        Returns:
            True if password was reset, False if token is invalid/expired.
        """
        record = await db.fetchrow(
            """
            SELECT * FROM users 
            WHERE password_reset_token = $1 
            AND password_reset_expires > NOW()
            """,
            token
        )
        
        if record is None:
            logger.warning("Invalid or expired password reset token used")
            return False
        
        user = User.from_record(record)
        pw_hash = hash_password(new_password)
        
        await db.execute(
            """
            UPDATE users 
            SET password_hash = $1, password_reset_token = NULL, password_reset_expires = NULL
            WHERE id = $2
            """,
            pw_hash, uuid.UUID(user.id)
        )
        
        logger.info(f"Password reset successful for user: {user.username}")
        
        return True


user_store = UserStore()
