"""User persistence store using PostgreSQL."""
import uuid
from typing import Optional
from dataclasses import dataclass
from datetime import datetime, timezone

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
    password_hash: str
    role: Role
    created_at: datetime
    
    @classmethod
    def from_record(cls, record) -> "User":
        """Create from database record."""
        return cls(
            id=str(record["id"]),
            username=record["username"],
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
        password: str, 
        role: Role = Role.PLAYER
    ) -> AuthTokens:
        """Register a new user.
        
        Args:
            username: Unique username.
            password: Plain text password.
            role: User role (defaults to player).
            
        Returns:
            Authentication tokens.
            
        Raises:
            ValueError: If username already exists.
        """
        # Check if user exists
        existing = await db.fetchrow(
            "SELECT id FROM users WHERE LOWER(username) = LOWER($1)",
            username
        )
        if existing:
            raise ValueError(f"Username '{username}' already exists")
        
        # Create user
        user_id = uuid.uuid4()
        pw_hash = hash_password(password)
        
        await db.execute(
            """
            INSERT INTO users (id, username, password_hash, role)
            VALUES ($1, $2, $3, $4)
            """,
            user_id, username, pw_hash, role.value
        )
        
        logger.info(f"Registered new user: {username} (role: {role.value})")
        
        # Return tokens
        return AuthTokens(
            access_token=create_access_token(str(user_id), username, role),
            refresh_token=create_refresh_token(str(user_id), username, role),
        )
    
    async def login(self, username: str, password: str) -> AuthTokens:
        """Authenticate a user and return tokens.
        
        Args:
            username: User's username.
            password: Plain text password.
            
        Returns:
            Authentication tokens.
            
        Raises:
            ValueError: If credentials are invalid.
        """
        record = await db.fetchrow(
            "SELECT * FROM users WHERE LOWER(username) = LOWER($1)",
            username
        )
        if record is None:
            raise ValueError("Invalid username or password")
        
        user = User.from_record(record)
        
        # Verify password
        if not verify_password(password, user.password_hash):
            raise ValueError("Invalid username or password")
        
        logger.info(f"User logged in: {username}")
        
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


user_store = UserStore()
