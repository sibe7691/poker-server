"""Main FastAPI server with WebSocket support."""
import asyncio
import json
from typing import Optional, Any
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel

from src.config import config
from src.db.connection import db
from src.db.models import init_db
from src.state.redis_client import redis_client
from src.state.session_store import session_store, PlayerSession
from src.state.game_store import game_store
from src.state.user_store import user_store
from src.auth.middleware import AuthenticatedUser, auth_middleware
from src.auth.jwt_handler import verify_token, refresh_access_token, TokenError
from src.auth.roles import Role
from src.game.table import Table
from src.game.player import Player
from src.admin.chip_manager import ChipManager
from src.admin.ledger import GameSession
from src.admin.standings import calculate_standings
from src.protocol.handlers import MessageHandler
from src.protocol.messages import (
    ErrorMessage,
    GameStateMessage,
    PlayerDisconnectedMessage,
    PlayerReconnectedMessage,
)
from src.utils.logger import get_logger

logger = get_logger(__name__)


# Pydantic models for HTTP API
class RegisterRequest(BaseModel):
    username: str
    password: str


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: str
    username: str
    role: str


class RefreshRequest(BaseModel):
    refresh_token: str


class RefreshResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class StandingItem(BaseModel):
    player: str
    buy_ins: int
    cash_outs: int
    net: int


class StandingsResponse(BaseModel):
    session_id: str
    players: list[StandingItem]


# Global server state
class GameServer:
    """Main poker game server state."""
    
    def __init__(self):
        self.tables: dict[str, Table] = {}
        self.chip_managers: dict[str, ChipManager] = {}
        self.connections: dict[str, WebSocket] = {}  # user_id -> websocket
        self.user_tables: dict[str, str] = {}  # user_id -> table_id
        self.spectators: dict[str, set[str]] = {}  # table_id -> set of user_ids
        self.handler: Optional[MessageHandler] = None
        self.game_session: Optional[GameSession] = None
        self._timeout_task: Optional[asyncio.Task] = None

    async def initialize(self):
        """Initialize server resources."""
        # Connect to databases
        await db.connect()
        await redis_client.connect()
        
        # Initialize database schema
        await init_db()
        
        # Get or create active game session
        self.game_session = await GameSession.get_or_create_active()
        logger.info(f"Using game session: {self.game_session.id}")
        
        # Initialize message handler
        self.handler = MessageHandler(self)
        
        # Restore tables from Redis
        await self._restore_tables()
        
        # Start background timeout checker
        self._timeout_task = asyncio.create_task(self._check_timeouts_loop())
        
        logger.info("Game server initialized")

    async def cleanup(self):
        """Clean up server resources."""
        # Cancel timeout checker
        if self._timeout_task:
            self._timeout_task.cancel()
            try:
                await self._timeout_task
            except asyncio.CancelledError:
                pass
        
        # Save all table states
        for table_id, table in self.tables.items():
            await game_store.save_table_state(table_id, table.to_dict())
        
        # Disconnect from databases
        await redis_client.disconnect()
        await db.disconnect()
        
        logger.info("Game server shutdown complete")

    async def _check_timeouts_loop(self):
        """Background task to check for turn timeouts."""
        while True:
            try:
                await asyncio.sleep(1)  # Check every second
                await self._check_all_table_timeouts()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in timeout checker: {e}")
    
    async def _check_all_table_timeouts(self):
        """Check all tables for timeout."""
        for table_id, table in list(self.tables.items()):
            await self._check_table_timeout(table_id, table)
    
    async def _check_table_timeout(self, table_id: str, table: Table):
        """Check if current player has timed out at a table."""
        if not table.current_betting_round:
            return
        
        current_player = table.current_betting_round.get_current_player()
        if not current_player:
            return
        
        # Get time remaining
        time_remaining, using_time_bank = table.current_betting_round.get_time_remaining(
            table.turn_time_seconds,
            current_player.time_bank_remaining
        )
        
        # If time expired
        if time_remaining <= 0:
            # Deduct used time bank
            if using_time_bank:
                elapsed = table.current_betting_round.get_time_elapsed()
                time_bank_used = elapsed - table.turn_time_seconds
                current_player.use_time_bank(time_bank_used)
            
            logger.info(
                f"Player {current_player.username} timed out at table {table_id}"
            )
            
            # Auto-action: check if possible, otherwise fold
            from src.game.betting import Action, ActionType
            valid_actions = table.current_betting_round.get_valid_actions(current_player)
            
            if ActionType.CHECK in valid_actions:
                action = Action(type=ActionType.CHECK)
                logger.info(f"Auto-check for {current_player.username}")
            else:
                action = Action(type=ActionType.FOLD)
                logger.info(f"Auto-fold for {current_player.username}")
            
            # Process the action
            await table.process_action(current_player.user_id, action)
            
            # Broadcast updated state
            await self.broadcast_game_state(table_id)
            
            # Save table state
            await game_store.save_table_state(table_id, table.to_dict())

    async def _restore_tables(self):
        """Restore tables from Redis."""
        table_ids = await game_store.list_tables()
        for table_id in table_ids:
            state = await game_store.get_table_state(table_id)
            if state:
                try:
                    table = Table.from_dict(state)
                    self.tables[table_id] = table
                    self._setup_table_callbacks(table)
                    
                    # Create chip manager using game session
                    self.chip_managers[table_id] = ChipManager(self.game_session.id)
                    self.chip_managers[table_id].set_table(table)
                    
                    logger.info(f"Restored table {table_id}")
                except Exception as e:
                    logger.error(f"Failed to restore table {table_id}: {e}")

    def register_connection(self, user_id: str, websocket: WebSocket):
        """Register a user's WebSocket connection."""
        self.connections[user_id] = websocket

    def create_table(
        self,
        table_id: str,
        small_blind: int = 1,
        big_blind: int = 2,
        min_players: int = 2,
        max_players: int = 10,
    ) -> Table:
        """Create a new table (admin only)."""
        if table_id in self.tables:
            raise ValueError(f"Table '{table_id}' already exists")
        
        table = Table(
            table_id=table_id,
            small_blind=small_blind,
            big_blind=big_blind,
            min_players=min_players,
            max_players=max_players,
        )
        self._setup_table_callbacks(table)
        self.tables[table_id] = table
        
        # Create chip manager using game session
        self.chip_managers[table_id] = ChipManager(self.game_session.id)
        self.chip_managers[table_id].set_table(table)
        
        logger.info(f"Created table {table_id} (blinds: {small_blind}/{big_blind})")
        return table

    async def delete_table(self, table_id: str) -> None:
        """Delete a table."""
        if table_id in self.tables:
            del self.tables[table_id]
        if table_id in self.chip_managers:
            del self.chip_managers[table_id]
        
        # Remove from Redis
        await game_store.delete_table(table_id)
        
        logger.info(f"Deleted table {table_id}")
        
        # Notify all connected clients about the updated tables list
        await self.broadcast_tables_update()

    def _setup_table_callbacks(self, table: Table):
        """Set up event callbacks for a table."""
        async def event_callback(event_type: str, data: Any):
            await self.broadcast_to_table(table.table_id, {
                "type": event_type,
                **data
            })
            
            if event_type in ("hand_started", "state_changed", "hand_result", "player_action"):
                # Get set of seated player IDs to avoid sending spectator state to them
                seated_player_ids = {p.user_id for p in table.players.values()}
                
                # Send to seated players
                for player in table.players.values():
                    state = table.get_state_for_player(player.user_id)
                    await self.send_to_user(
                        player.user_id,
                        GameStateMessage(**state).model_dump()
                    )
                
                # Send to spectators (skip anyone who is also a seated player)
                spectators = self.get_spectators(table.table_id)
                spectator_state = table.get_state_for_spectator()
                for user_id in spectators:
                    if user_id in seated_player_ids:
                        # User is seated - they already got player state, clean up inconsistency
                        self.remove_spectator(user_id, table.table_id)
                        continue
                    await self.send_to_user(
                        user_id,
                        GameStateMessage(**spectator_state).model_dump()
                    )
            
            # Auto-start next hand after hand_result with a delay
            if event_type == "hand_result":
                asyncio.create_task(self._auto_start_next_hand(table))
        
        table.set_event_callback(event_callback)
    
    async def _auto_start_next_hand(self, table: Table):
        """Auto-start the next hand after a delay."""
        from src.game.table import TableState
        
        # Wait for players to see the results
        await asyncio.sleep(5)
        
        # Check if we can still start (table might have changed)
        if table.state == TableState.WAITING and table.can_start_hand():
            success = await table.start_hand()
            if success:
                logger.info(f"Auto-started next hand on table {table.table_id}")

    def get_player_table(self, user_id: str) -> Optional[str]:
        """Get the table a player or spectator is at."""
        if user_id in self.user_tables:
            return self.user_tables[user_id]
        
        for table_id, table in self.tables.items():
            if table.get_player_by_id(user_id):
                self.user_tables[user_id] = table_id
                return table_id
        
        # Check if spectating
        for table_id, spectators in self.spectators.items():
            if user_id in spectators:
                self.user_tables[user_id] = table_id
                return table_id
        
        return None
    
    def add_spectator(self, user_id: str, table_id: str) -> None:
        """Add a spectator to a table."""
        if table_id not in self.spectators:
            self.spectators[table_id] = set()
        self.spectators[table_id].add(user_id)
    
    def remove_spectator(self, user_id: str, table_id: str) -> None:
        """Remove a spectator from a table."""
        if table_id in self.spectators:
            self.spectators[table_id].discard(user_id)
    
    def get_spectators(self, table_id: str) -> set[str]:
        """Get all spectators at a table."""
        return self.spectators.get(table_id, set())

    def get_chip_manager(self, table_id: str) -> Optional[ChipManager]:
        """Get chip manager for a table."""
        return self.chip_managers.get(table_id)

    async def send_to_user(self, user_id: str, message: dict) -> bool:
        """Send a message to a specific user."""
        websocket = self.connections.get(user_id)
        if websocket:
            try:
                await websocket.send_json(message)
                return True
            except Exception as e:
                logger.error(f"Failed to send to {user_id}: {e}")
        return False

    async def broadcast_to_table(
        self,
        table_id: str,
        message: dict,
        exclude_user: Optional[str] = None
    ):
        """Broadcast a message to all players and spectators at a table."""
        table = self.tables.get(table_id)
        if not table:
            return
        
        # Send to seated players
        for player in table.players.values():
            if exclude_user and player.user_id == exclude_user:
                continue
            await self.send_to_user(player.user_id, message)
        
        # Send to spectators
        spectators = self.get_spectators(table_id)
        for user_id in spectators:
            if exclude_user and user_id == exclude_user:
                continue
            await self.send_to_user(user_id, message)

    async def broadcast_to_all(self, message: dict):
        """Broadcast a message to all connected users."""
        for user_id in list(self.connections.keys()):
            await self.send_to_user(user_id, message)

    def get_tables_list(self) -> list[dict]:
        """Get list of tables formatted for clients."""
        return [
            {
                "table_id": table_id,
                "players": len(table.players),
                "max_players": table.max_players,
                "state": table.state.value,
                "small_blind": table.small_blind,
                "big_blind": table.big_blind,
            }
            for table_id, table in self.tables.items()
        ]

    async def broadcast_tables_update(self):
        """Broadcast updated tables list to all connected users."""
        from src.protocol.messages import TablesListMessage
        message = TablesListMessage(tables=self.get_tables_list())
        await self.broadcast_to_all(message.model_dump())

    async def broadcast_game_state(self, table_id: str):
        """Broadcast game state to all players at a table."""
        table = self.tables.get(table_id)
        if not table:
            return
        
        # Send to seated players
        for player in table.players.values():
            state = table.get_state_for_player(player.user_id)
            await self.send_to_user(
                player.user_id,
                GameStateMessage(**state).model_dump()
            )
        
        # Send to spectators
        spectator_state = table.get_state_for_spectator()
        for user_id in self.get_spectators(table_id):
            await self.send_to_user(
                user_id,
                GameStateMessage(**spectator_state).model_dump()
            )


# Global server instance
server = GameServer()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    await server.initialize()
    yield
    await server.cleanup()


# Create FastAPI app
app = FastAPI(
    title="Poker WebSocket Server",
    description="Texas Hold'em poker server with WebSocket and REST API",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS middleware - allow local development
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",  # Allow any localhost port
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Health check
@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy"}


# Auth endpoints
@app.post("/api/register", response_model=TokenResponse)
async def register(request: RegisterRequest):
    """Register a new user."""
    try:
        tokens = await user_store.register(request.username, request.password)
        user = await user_store.get_user(request.username)
        return TokenResponse(
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            user_id=user.id,
            username=user.username,
            role=user.role.value,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/api/login", response_model=TokenResponse)
async def login(request: LoginRequest):
    """Login and get tokens."""
    try:
        tokens = await user_store.login(request.username, request.password)
        user = await user_store.get_user(request.username)
        return TokenResponse(
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            user_id=user.id,
            username=user.username,
            role=user.role.value,
        )
    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e))


@app.post("/api/refresh", response_model=RefreshResponse)
async def refresh_token(request: RefreshRequest):
    """Refresh access token."""
    try:
        new_token = refresh_access_token(request.refresh_token)
        return RefreshResponse(access_token=new_token)
    except TokenError as e:
        raise HTTPException(status_code=401, detail=str(e))


# Game info endpoints
@app.get("/api/standings", response_model=StandingsResponse)
async def get_standings():
    """Get current session standings."""
    if not server.game_session:
        raise HTTPException(status_code=503, detail="No active game session")
    
    standings = await calculate_standings(server.game_session.id)
    return StandingsResponse(
        session_id=server.game_session.id,
        players=[
            StandingItem(
                player=s.player,
                buy_ins=s.buy_ins,
                cash_outs=s.cash_outs,
                net=s.net,
            )
            for s in standings
        ]
    )


@app.get("/api/tables")
async def list_tables():
    """List active tables."""
    return {
        "tables": [
            {
                "table_id": table_id,
                "players": len(table.players),
                "max_players": table.max_players,
                "state": table.state.value,
                "small_blind": table.small_blind,
                "big_blind": table.big_blind,
            }
            for table_id, table in server.tables.items()
        ]
    }


# Admin table management
class CreateTableRequest(BaseModel):
    table_id: str
    small_blind: int = 1
    big_blind: int = 2
    min_players: int = 2
    max_players: int = 10


class TableResponse(BaseModel):
    table_id: str
    small_blind: int
    big_blind: int
    min_players: int
    max_players: int
    players: int
    state: str


async def get_admin_user(authorization: str = Header(None)) -> None:
    """Verify admin authorization from header."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing authorization header")
    
    token = authorization.split(" ")[1]
    try:
        payload = verify_token(token, expected_type="access")
        if payload.role != Role.ADMIN:
            raise HTTPException(status_code=403, detail="Admin access required")
    except TokenError as e:
        raise HTTPException(status_code=401, detail=str(e))


@app.post("/api/tables", response_model=TableResponse)
async def create_table(
    request: CreateTableRequest,
    authorization: str = Header(None),
):
    """Create a new table (admin only)."""
    await get_admin_user(authorization)
    
    if request.table_id in server.tables:
        raise HTTPException(status_code=400, detail=f"Table '{request.table_id}' already exists")
    
    table = server.create_table(
        table_id=request.table_id,
        small_blind=request.small_blind,
        big_blind=request.big_blind,
        min_players=request.min_players,
        max_players=request.max_players,
    )
    
    # Notify all connected clients about the new table
    await server.broadcast_tables_update()
    
    return TableResponse(
        table_id=table.table_id,
        small_blind=table.small_blind,
        big_blind=table.big_blind,
        min_players=table.min_players,
        max_players=table.max_players,
        players=len(table.players),
        state=table.state.value,
    )


@app.delete("/api/tables/{table_id}")
async def delete_table(
    table_id: str,
    authorization: str = Header(None),
):
    """Delete a table (admin only)."""
    await get_admin_user(authorization)
    
    if table_id not in server.tables:
        raise HTTPException(status_code=404, detail=f"Table '{table_id}' not found")
    
    table = server.tables[table_id]
    if table.players:
        raise HTTPException(status_code=400, detail="Cannot delete table with players")
    
    await server.delete_table(table_id)
    
    return {"message": f"Table '{table_id}' deleted"}


# WebSocket endpoint
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for game communication."""
    await websocket.accept()
    
    user: Optional[AuthenticatedUser] = None
    
    try:
        while True:
            data = await websocket.receive_text()
            
            response, user = await server.handler.handle_message(websocket, data, user)
            
            if response:
                await websocket.send_json(response)
            
            # Check for reconnection after auth
            if user and response and response.get("type") == "auth_success":
                await _handle_potential_reconnect(user, websocket)
    
    except WebSocketDisconnect:
        logger.debug("WebSocket disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        try:
            await websocket.send_json(
                ErrorMessage(message=str(e), code="SERVER_ERROR").model_dump()
            )
        except:
            pass
    finally:
        if user:
            await _handle_disconnect(user)


async def _handle_potential_reconnect(user: AuthenticatedUser, websocket: WebSocket):
    """Handle potential reconnection."""
    session = await session_store.get_session(user.user_id)
    if not session:
        return
    
    reconnected = await session_store.mark_reconnected(user.user_id, session.table_id)
    
    if reconnected:
        table = server.tables.get(session.table_id)
        if table:
            player = table.get_player_by_id(user.user_id)
            if player:
                player.is_disconnected = False
                
                await server.broadcast_to_table(
                    session.table_id,
                    PlayerReconnectedMessage(
                        user_id=user.user_id,
                        username=user.username,
                    ).model_dump(),
                    exclude_user=user.user_id
                )
                
                state = table.get_state_for_player(user.user_id)
                logger.info(
                    f"Reconnect state for {user.username}: "
                    f"current_player={state.get('current_player')}, "
                    f"valid_actions={state.get('valid_actions')}, "
                    f"state={state.get('state')}"
                )
                await websocket.send_json(GameStateMessage(**state).model_dump())
                
                logger.info(f"User {user.username} reconnected to table {session.table_id}")
        
        server.user_tables[user.user_id] = session.table_id


async def _handle_disconnect(user: AuthenticatedUser):
    """Handle user disconnection."""
    if user.user_id in server.connections:
        del server.connections[user.user_id]
    
    table_id = server.user_tables.get(user.user_id)
    if not table_id:
        return
    
    # Remove from user_tables tracking
    if user.user_id in server.user_tables:
        del server.user_tables[user.user_id]
    
    # Check if spectator
    if user.user_id in server.get_spectators(table_id):
        server.remove_spectator(user.user_id, table_id)
        logger.info(f"Spectator {user.username} disconnected from table {table_id}")
        return
    
    table = server.tables.get(table_id)
    if not table:
        return
    
    player = table.get_player_by_id(user.user_id)
    if not player:
        return
    
    player.is_disconnected = True
    
    session = PlayerSession(
        user_id=user.user_id,
        username=user.username,
        table_id=table_id,
        seat=player.seat,
        chips=player.chips,
        hole_cards=[str(c) for c in player.hole_cards],
        is_folded=player.is_folded,
        current_bet=player.current_bet,
    )
    await session_store.save_session(session)
    await session_store.mark_disconnected(user.user_id, table_id)
    
    await server.broadcast_to_table(
        table_id,
        PlayerDisconnectedMessage(
            user_id=user.user_id,
            username=user.username,
            grace_seconds=config.reconnect_grace_seconds,
        ).model_dump(),
        exclude_user=user.user_id
    )
    
    logger.info(f"User {user.username} disconnected from table {table_id}")
    
    # Schedule grace period cleanup
    asyncio.create_task(_grace_period_cleanup(user.user_id, table_id))


async def _grace_period_cleanup(user_id: str, table_id: str):
    """Clean up after grace period expires."""
    await asyncio.sleep(config.reconnect_grace_seconds)
    
    session = await session_store.get_session(user_id)
    if session and session.disconnected_at:
        table = server.tables.get(table_id)
        if table:
            player = table.get_player_by_id(user_id)
            if player and player.is_disconnected:
                username = player.username
                
                # Auto-fold if in active hand
                if player.is_active and not player.is_folded:
                    player.fold()
                    logger.info(f"Auto-folded {username} after grace period")
                
                # Remove player from table entirely
                # They can rejoin later at any seat
                table.remove_player(user_id)
                logger.info(f"Removed {username} from table {table_id} after grace period expired")
                
                # Broadcast updated state to remaining players
                for remaining_player in table.players.values():
                    state = table.get_state_for_player(remaining_player.user_id)
                    await server.send_to_user(
                        remaining_player.user_id,
                        GameStateMessage(**state).model_dump()
                    )
        
        await session_store.delete_session(user_id)
        if user_id in server.user_tables:
            del server.user_tables[user_id]


# Entry point
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "src.main:app",
        host=config.host,
        port=config.port,
        reload=True,
    )
