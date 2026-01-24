"""Role definitions and authorization."""
from enum import Enum
from functools import wraps
from typing import Callable, Any


class Role(str, Enum):
    """User roles."""
    PLAYER = "player"
    ADMIN = "admin"


def require_role(required_role: Role) -> Callable:
    """Decorator to require a specific role for an action.
    
    Args:
        required_role: The minimum role required.
        
    Returns:
        Decorator function.
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(self, user_role: str, *args: Any, **kwargs: Any) -> Any:
            # Admin can do anything
            if user_role == Role.ADMIN:
                return await func(self, *args, **kwargs)
            # Check if user has required role
            if user_role != required_role:
                raise PermissionError(f"Requires {required_role.value} role")
            return await func(self, *args, **kwargs)
        return wrapper
    return decorator
