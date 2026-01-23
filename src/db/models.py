"""Database schema and initialization."""
from src.db.connection import db
from src.utils.logger import get_logger

logger = get_logger(__name__)

# SQL schema for all tables
SCHEMA = """
-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'player',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

-- Game sessions (a poker night)
CREATE TABLE IF NOT EXISTS game_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- Ledger transactions (buy-ins, cash-outs, adjustments)
CREATE TABLE IF NOT EXISTS ledger_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL,  -- buy_in, cash_out, adjustment
    amount INTEGER NOT NULL,
    admin_id UUID REFERENCES users(id),
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ledger_session ON ledger_transactions(session_id);
CREATE INDEX IF NOT EXISTS idx_ledger_user ON ledger_transactions(user_id);

-- Hand history (optional, for record keeping)
CREATE TABLE IF NOT EXISTS hand_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES game_sessions(id) ON DELETE CASCADE,
    hand_number INTEGER NOT NULL,
    pot_total INTEGER NOT NULL,
    community_cards TEXT,  -- JSON array of cards
    winner_ids TEXT,  -- JSON array of winner user IDs
    played_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hands_session ON hand_history(session_id);

-- Update trigger for users.updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS users_updated_at ON users;
CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();
"""


async def init_db() -> None:
    """Initialize database schema."""
    logger.info("Initializing database schema...")
    await db.execute(SCHEMA)
    logger.info("Database schema initialized")
