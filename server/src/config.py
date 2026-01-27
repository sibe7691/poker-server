"""Application configuration."""
import os
from dataclasses import dataclass
from dotenv import load_dotenv

load_dotenv()


@dataclass
class Config:
    """Application configuration loaded from environment variables."""
    
    # Redis (for real-time state, sessions)
    redis_url: str = os.getenv("REDIS_URL", "redis://localhost:6379")
    
    # PostgreSQL (for users, ledger, persistent data)
    database_url: str = os.getenv("DATABASE_URL", "postgresql://poker:poker@localhost:5432/poker")
    
    # JWT
    jwt_secret: str = os.getenv("JWT_SECRET", "dev-secret-change-in-production")
    jwt_algorithm: str = "HS256"
    jwt_access_expiry_minutes: int = int(os.getenv("JWT_EXPIRY_MINUTES", "15"))
    jwt_refresh_expiry_days: int = int(os.getenv("JWT_REFRESH_EXPIRY_DAYS", "7"))
    
    # Game settings
    reconnect_grace_seconds: int = int(os.getenv("RECONNECT_GRACE_SECONDS", "60"))
    min_players: int = int(os.getenv("MIN_PLAYERS", "2"))
    max_players: int = int(os.getenv("MAX_PLAYERS", "10"))
    
    # Turn timer defaults (can be overridden per-table)
    default_turn_time_seconds: int = int(os.getenv("DEFAULT_TURN_TIME", "30"))
    default_time_bank_seconds: int = int(os.getenv("DEFAULT_TIME_BANK", "60"))
    time_bank_replenish_per_hand: int = int(os.getenv("TIME_BANK_REPLENISH", "10"))
    
    # Server
    host: str = os.getenv("HOST", "0.0.0.0")
    port: int = int(os.getenv("PORT", "8765"))
    
    # Logging
    log_level: str = os.getenv("LOG_LEVEL", "INFO")


config = Config()
