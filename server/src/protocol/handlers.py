"""Message handlers for WebSocket protocol."""
import json
from typing import Optional, Any, TYPE_CHECKING
from datetime import datetime, timezone

from src.protocol.messages import (
    parse_client_message,
    ClientMessage,
    AuthMessage,
    RegisterMessage,
    LoginMessage,
    RefreshTokenMessage,
    JoinTableMessage,
    LeaveTableMessage,
    StandUpMessage,
    ActionMessage,
    ChatMessage,
    StartGameMessage,
    CreateTableMessage,
    DeleteTableMessage,
    GiveChipsMessage,
    TakeChipsMessage,
    SetChipsMessage,
    GetLedgerMessage,
    GetStandingsMessage,
    EndSessionMessage,
    PingMessage,
    ErrorMessage,
    AuthSuccessMessage,
    GameStateMessage,
    PlayerJoinedMessage,
    PlayerLeftMessage,
    ChipsUpdatedMessage,
    LedgerMessage,
    StandingsMessage,
    ChatBroadcastMessage,
    TableCreatedMessage,
    TableDeletedMessage,
    PongMessage,
)
from src.auth.middleware import AuthMiddleware, AuthenticatedUser
from src.auth.jwt_handler import TokenError, refresh_access_token
from src.auth.roles import Role
from src.state.user_store import user_store
from src.game.betting import Action, ActionType
from src.utils.logger import get_logger

if TYPE_CHECKING:
    from src.main import GameServer

logger = get_logger(__name__)


class MessageHandler:
    """Handles incoming WebSocket messages."""
    
    def __init__(self, server: "GameServer"):
        """Initialize handler.
        
        Args:
            server: The game server instance.
        """
        self.server = server
        self.auth = AuthMiddleware()
    
    async def handle_message(
        self,
        websocket: Any,
        raw_message: str,
        user: Optional[AuthenticatedUser] = None,
    ) -> tuple[Optional[dict], Optional[AuthenticatedUser]]:
        """Handle an incoming message.
        
        Args:
            websocket: The WebSocket connection.
            raw_message: Raw JSON message string.
            user: Currently authenticated user (if any).
            
        Returns:
            Tuple of (response dict or None, updated user or None).
        """
        try:
            data = json.loads(raw_message)
            message = parse_client_message(data)
        except json.JSONDecodeError as e:
            return ErrorMessage(message=f"Invalid JSON: {e}").model_dump(), user
        except ValueError as e:
            return ErrorMessage(message=str(e)).model_dump(), user
        
        # Handle auth-related messages first (don't require authentication)
        if isinstance(message, RegisterMessage):
            return await self._handle_register(message), user
        
        if isinstance(message, LoginMessage):
            return await self._handle_login(message), user
        
        if isinstance(message, AuthMessage):
            return await self._handle_auth(message, websocket)
        
        if isinstance(message, RefreshTokenMessage):
            return await self._handle_refresh(message), user
        
        # All other messages require authentication
        if user is None:
            return ErrorMessage(
                message="Not authenticated. Send auth message first.",
                code="AUTH_REQUIRED"
            ).model_dump(), None
        
        # Handle ping (keep-alive)
        if isinstance(message, PingMessage):
            return PongMessage().model_dump(), user
        
        # Route to appropriate handler
        if isinstance(message, JoinTableMessage):
            return await self._handle_join_table(message, user), user
        
        if isinstance(message, LeaveTableMessage):
            return await self._handle_leave_table(user), user
        
        if isinstance(message, StandUpMessage):
            return await self._handle_stand_up(user), user
        
        if isinstance(message, ActionMessage):
            return await self._handle_action(message, user), user
        
        if isinstance(message, ChatMessage):
            return await self._handle_chat(message, user), user
        
        if isinstance(message, StartGameMessage):
            return await self._handle_start_game(user), user
        
        # Admin messages - table management
        if isinstance(message, CreateTableMessage):
            return await self._handle_create_table(message, user), user
        
        if isinstance(message, DeleteTableMessage):
            return await self._handle_delete_table(message, user), user
        
        # Admin messages - chip operations
        if isinstance(message, (GiveChipsMessage, TakeChipsMessage, SetChipsMessage)):
            return await self._handle_chip_operation(message, user), user
        
        if isinstance(message, GetLedgerMessage):
            return await self._handle_get_ledger(user), user
        
        if isinstance(message, GetStandingsMessage):
            return await self._handle_get_standings(user), user
        
        if isinstance(message, EndSessionMessage):
            return await self._handle_end_session(user), user
        
        return ErrorMessage(message="Unhandled message type").model_dump(), user
    
    async def _handle_register(self, message: RegisterMessage) -> dict:
        """Handle registration."""
        try:
            tokens = await user_store.register(message.username, message.password)
            # Get user to return details
            user = await user_store.get_user(message.username)
            return AuthSuccessMessage(
                user_id=user.id,
                username=user.username,
                role=user.role.value,
                access_token=tokens.access_token,
                refresh_token=tokens.refresh_token,
            ).model_dump()
        except ValueError as e:
            return ErrorMessage(message=str(e), code="REGISTER_FAILED").model_dump()
    
    async def _handle_login(self, message: LoginMessage) -> dict:
        """Handle login."""
        try:
            tokens = await user_store.login(message.username, message.password)
            user = await user_store.get_user(message.username)
            return AuthSuccessMessage(
                user_id=user.id,
                username=user.username,
                role=user.role.value,
                access_token=tokens.access_token,
                refresh_token=tokens.refresh_token,
            ).model_dump()
        except ValueError as e:
            return ErrorMessage(message=str(e), code="LOGIN_FAILED").model_dump()
    
    async def _handle_auth(
        self, 
        message: AuthMessage,
        websocket: Any
    ) -> tuple[dict, Optional[AuthenticatedUser]]:
        """Handle WebSocket authentication."""
        try:
            user = await self.auth.authenticate(message.token)
            # Register connection
            self.server.register_connection(user.user_id, websocket)
            
            return AuthSuccessMessage(
                user_id=user.user_id,
                username=user.username,
                role=user.role.value,
            ).model_dump(), user
        except TokenError as e:
            return ErrorMessage(
                message=str(e), 
                code="AUTH_FAILED"
            ).model_dump(), None
    
    async def _handle_refresh(self, message: RefreshTokenMessage) -> dict:
        """Handle token refresh."""
        try:
            new_token = refresh_access_token(message.refresh_token)
            return {"type": "token_refreshed", "access_token": new_token}
        except TokenError as e:
            return ErrorMessage(message=str(e), code="REFRESH_FAILED").model_dump()
    
    async def _handle_join_table(
        self, 
        message: JoinTableMessage,
        user: AuthenticatedUser
    ) -> dict:
        """Handle joining a table.
        
        If seat is None, user joins as spectator.
        If seat is specified, user takes that seat.
        """
        try:
            # Check if table exists (tables must be created by admin first)
            table = self.server.tables.get(message.table_id)
            if not table:
                return ErrorMessage(
                    message=f"Table '{message.table_id}' does not exist. Ask an admin to create it.",
                    code="TABLE_NOT_FOUND"
                ).model_dump()
            
            # Check if already seated at table
            existing = table.get_player_by_id(user.user_id)
            
            # Log for debugging seat assignment issues
            logger.debug(
                f"join_table: user={user.username}, requested_seat={message.seat} (type={type(message.seat).__name__}), "
                f"existing={'seat ' + str(existing.seat) if existing else 'None'}"
            )
            
            # Handle reconnection case: user exists but is disconnected
            # This handles the edge case where session expired but player is still in table
            if existing and existing.is_disconnected:
                logger.info(f"Reconnecting disconnected player {user.username} at seat {existing.seat}")
                existing.is_disconnected = False
                
                # Ensure not in spectators list (cleanup any inconsistency)
                self.server.remove_spectator(user.user_id, message.table_id)
                
                # If they requested a different seat, allow seat change
                if message.seat is not None and message.seat != existing.seat:
                    # Validate new seat
                    if message.seat < 0 or message.seat >= table.max_players:
                        return ErrorMessage(
                            message=f"Invalid seat {message.seat}. Must be 0-{table.max_players - 1}.",
                            code="INVALID_SEAT"
                        ).model_dump()
                    if message.seat in table.players:
                        return ErrorMessage(
                            message=f"Seat {message.seat} is already taken.",
                            code="SEAT_TAKEN"
                        ).model_dump()
                    
                    # Move to new seat
                    old_seat = existing.seat
                    del table.players[old_seat]
                    existing.seat = message.seat
                    table.players[message.seat] = existing
                    logger.info(f"{user.username} moved from seat {old_seat} to seat {message.seat}")
                
                # Track user's table
                self.server.user_tables[user.user_id] = message.table_id
                
                # Broadcast updated game state
                await self._broadcast_game_state(message.table_id)
                
                # Return their state
                return GameStateMessage(
                    **table.get_state_for_player(user.user_id)
                ).model_dump()
            
            # If no seat specified, join as spectator
            if message.seat is None:
                if existing:
                    # Already seated - ensure not in spectators list (cleanup)
                    self.server.remove_spectator(user.user_id, message.table_id)
                    # Track user's table
                    self.server.user_tables[user.user_id] = message.table_id
                    # Return current state
                    return GameStateMessage(
                        **table.get_state_for_player(user.user_id)
                    ).model_dump()
                
                # Join as spectator
                self.server.add_spectator(user.user_id, message.table_id)
                self.server.user_tables[user.user_id] = message.table_id
                
                logger.info(f"{user.username} joined table {message.table_id} as spectator")
                
                # Return spectator state
                return GameStateMessage(
                    **table.get_state_for_spectator()
                ).model_dump()
            
            # Seat specified - take that seat
            seat = message.seat
            
            # Check if seat is valid
            if seat < 0 or seat >= table.max_players:
                return ErrorMessage(
                    message=f"Invalid seat {seat}. Must be 0-{table.max_players - 1}.",
                    code="INVALID_SEAT"
                ).model_dump()
            
            # Check if seat is available
            if seat in table.players:
                return ErrorMessage(
                    message=f"Seat {seat} is already taken.",
                    code="SEAT_TAKEN"
                ).model_dump()
            
            # If already seated at a different seat, that's not allowed (use stand_up first)
            if existing:
                return ErrorMessage(
                    message="Already seated. Use stand_up first to change seats.",
                    code="ALREADY_SEATED"
                ).model_dump()
            
            # Remove from spectators if was spectating
            self.server.remove_spectator(user.user_id, message.table_id)
            
            # Create player
            from src.game.player import Player
            player = Player(
                user_id=user.user_id,
                username=user.username,
                seat=seat,
                chips=0,  # Admin will give chips
            )
            
            if not table.add_player(player):
                return ErrorMessage(message="Could not join table", code="JOIN_FAILED").model_dump()
            
            # Track user's table
            self.server.user_tables[user.user_id] = message.table_id
            
            # Broadcast join to players and spectators
            await self.server.broadcast_to_table(
                message.table_id,
                PlayerJoinedMessage(
                    user_id=user.user_id,
                    username=user.username,
                    seat=seat,
                    chips=0,
                ).model_dump()
            )
            
            # Broadcast updated game state to ALL players and spectators at table
            await self._broadcast_game_state(message.table_id)
            
            # Auto-start if enough players with chips and game is waiting
            await self._try_auto_start(table, message.table_id)
            
            # Broadcast lobby update so player counts are accurate
            await self.server.broadcast_tables_update()
            
            # Return game state
            return GameStateMessage(
                **table.get_state_for_player(user.user_id)
            ).model_dump()
            
        except Exception as e:
            logger.error(f"Join table error: {e}")
            return ErrorMessage(message=str(e), code="JOIN_ERROR").model_dump()
    
    async def _handle_leave_table(self, user: AuthenticatedUser) -> dict:
        """Handle leaving a table (both players and spectators).
        
        Players can always leave. If they're in an active hand, they will be
        auto-folded before leaving.
        """
        table_id = self.server.get_player_table(user.user_id)
        if not table_id:
            return ErrorMessage(message="Not at a table", code="NOT_AT_TABLE").model_dump()
        
        table = self.server.tables.get(table_id)
        was_in_hand = False
        if table:
            player = table.get_player_by_id(user.user_id)
            if player:
                # Check if player will be auto-folded
                was_in_hand = (
                    table.state.value != "waiting" 
                    and player.is_active 
                    and not player.is_folded
                )
                
                if was_in_hand:
                    logger.info(f"Auto-folding {user.username} who is leaving table {table_id} during hand")
                
                # Remove player - this will auto-fold if in active hand
                await table.remove_player_during_hand(user.user_id)
                
                await self.server.broadcast_to_table(
                    table_id,
                    PlayerLeftMessage(
                        user_id=user.user_id,
                        username=user.username,
                    ).model_dump()
                )
                # Broadcast updated state
                await self._broadcast_game_state(table_id)
                
                # Save table state
                from src.state.game_store import game_store
                await game_store.save_table_state(table_id, table.to_dict())
        
        # Remove from spectators if was spectating
        self.server.remove_spectator(user.user_id, table_id)
        
        # Remove table tracking
        if user.user_id in self.server.user_tables:
            del self.server.user_tables[user.user_id]
        
        # Broadcast lobby update so player counts are accurate
        await self.server.broadcast_tables_update()
        
        return {"type": "left_table", "table_id": table_id, "was_folded": was_in_hand}
    
    async def _handle_stand_up(self, user: AuthenticatedUser) -> dict:
        """Handle standing up from seat (become spectator).
        
        Players can always stand up. If they're in an active hand, they will be
        auto-folded before standing up.
        """
        table_id = self.server.get_player_table(user.user_id)
        if not table_id:
            return ErrorMessage(message="Not at a table", code="NOT_AT_TABLE").model_dump()
        
        table = self.server.tables.get(table_id)
        if not table:
            return ErrorMessage(message="Table not found", code="TABLE_NOT_FOUND").model_dump()
        
        player = table.get_player_by_id(user.user_id)
        if not player:
            # Already a spectator
            return GameStateMessage(
                **table.get_state_for_spectator()
            ).model_dump()
        
        # Check if player will be auto-folded
        was_in_hand = (
            table.state.value != "waiting" 
            and player.is_active 
            and not player.is_folded
        )
        
        if was_in_hand:
            logger.info(f"Auto-folding {user.username} who is standing up from table {table_id} during hand")
        
        # Remove from table (will auto-fold if in active hand)
        await table.remove_player_during_hand(user.user_id)
        
        # Add as spectator
        self.server.add_spectator(user.user_id, table_id)
        
        # Broadcast that player left seat
        await self.server.broadcast_to_table(
            table_id,
            PlayerLeftMessage(
                user_id=user.user_id,
                username=user.username,
            ).model_dump()
        )
        
        # Broadcast updated game state
        await self._broadcast_game_state(table_id)
        
        # Save table state
        from src.state.game_store import game_store
        await game_store.save_table_state(table_id, table.to_dict())
        
        logger.info(f"{user.username} stood up from table {table_id}")
        
        # Broadcast lobby update so player counts are accurate
        await self.server.broadcast_tables_update()
        
        return GameStateMessage(
            **table.get_state_for_spectator()
        ).model_dump()
    
    async def _handle_action(
        self,
        message: ActionMessage,
        user: AuthenticatedUser
    ) -> dict:
        """Handle a game action."""
        table_id = self.server.get_player_table(user.user_id)
        if not table_id:
            return ErrorMessage(message="Not at a table", code="NOT_AT_TABLE").model_dump()
        
        table = self.server.tables.get(table_id)
        if not table:
            return ErrorMessage(message="Table not found", code="TABLE_NOT_FOUND").model_dump()
        
        try:
            action_type = ActionType(message.action)
            action = Action(type=action_type, amount=message.amount)
            
            success = await table.process_action(user.user_id, action)
            if not success:
                return ErrorMessage(
                    message="Invalid action or not your turn",
                    code="INVALID_ACTION"
                ).model_dump()
            
            # Broadcast updated state to ALL players (the table callbacks handle this too,
            # but we ensure it here for reliability)
            await self._broadcast_game_state(table_id)
            
            # Return updated state to the acting player
            return GameStateMessage(
                **table.get_state_for_player(user.user_id)
            ).model_dump()
            
        except ValueError as e:
            return ErrorMessage(message=str(e), code="ACTION_ERROR").model_dump()
    
    async def _handle_chat(
        self,
        message: ChatMessage,
        user: AuthenticatedUser
    ) -> dict:
        """Handle chat message."""
        table_id = self.server.get_player_table(user.user_id)
        if table_id:
            await self.server.broadcast_to_table(
                table_id,
                ChatBroadcastMessage(
                    username=user.username,
                    message=message.message,
                    timestamp=datetime.now(timezone.utc).isoformat(),
                ).model_dump()
            )
        return {"type": "chat_sent"}
    
    async def _try_auto_start(self, table, table_id: str) -> bool:
        """Try to auto-start the game if conditions are met."""
        from src.game.table import TableState
        
        # Only auto-start if waiting and can start
        if table.state == TableState.WAITING and table.can_start_hand():
            success = await table.start_hand()
            if success:
                logger.info(f"Auto-started hand on table {table_id}")
                await self._broadcast_game_state(table_id)
                return True
        return False
    
    async def _handle_start_game(self, user: AuthenticatedUser) -> dict:
        """Handle start game request."""
        table_id = self.server.get_player_table(user.user_id)
        if not table_id:
            return ErrorMessage(message="Not at a table", code="NOT_AT_TABLE").model_dump()
        
        table = self.server.tables.get(table_id)
        if not table:
            return ErrorMessage(message="Table not found", code="TABLE_NOT_FOUND").model_dump()
        
        # Only admin can start
        if user.role != Role.ADMIN:
            return ErrorMessage(message="Only admin can start game", code="NOT_ADMIN").model_dump()
        
        success = await table.start_hand()
        if not success:
            return ErrorMessage(
                message="Cannot start hand. Need more players or hand in progress.",
                code="CANNOT_START"
            ).model_dump()
        
        # Broadcast new state to all
        await self._broadcast_game_state(table_id)
        
        return {"type": "game_started"}
    
    async def _handle_create_table(
        self,
        message: CreateTableMessage,
        user: AuthenticatedUser
    ) -> dict:
        """Handle create table request (admin only)."""
        if user.role != Role.ADMIN:
            return ErrorMessage(message="Only admin can create tables", code="NOT_ADMIN").model_dump()
        
        # Create the table (UUID is generated automatically)
        table = self.server.create_table(
            table_name=message.table_name,
            small_blind=message.small_blind,
            big_blind=message.big_blind,
            min_players=message.min_players,
            max_players=message.max_players,
        )
        
        # Notify all connected clients about the new table
        await self.server.broadcast_tables_update()
        
        return TableCreatedMessage(
            table_id=table.table_id,
            small_blind=table.small_blind,
            big_blind=table.big_blind,
            min_players=table.min_players,
            max_players=table.max_players,
        ).model_dump()
    
    async def _handle_delete_table(
        self,
        message: DeleteTableMessage,
        user: AuthenticatedUser
    ) -> dict:
        """Handle delete table request (admin only)."""
        if user.role != Role.ADMIN:
            return ErrorMessage(message="Only admin can delete tables", code="NOT_ADMIN").model_dump()
        
        # Check if table exists
        if message.table_id not in self.server.tables:
            return ErrorMessage(
                message=f"Table '{message.table_id}' does not exist",
                code="TABLE_NOT_FOUND"
            ).model_dump()
        
        table = self.server.tables[message.table_id]
        
        # Check if table has players
        if table.players:
            return ErrorMessage(
                message="Cannot delete table with players. Remove all players first.",
                code="TABLE_HAS_PLAYERS"
            ).model_dump()
        
        # Delete the table
        await self.server.delete_table(message.table_id)
        
        return TableDeletedMessage(table_id=message.table_id).model_dump()
    
    async def _handle_chip_operation(
        self,
        message: Any,
        user: AuthenticatedUser
    ) -> dict:
        """Handle chip operations (give/take/set)."""
        if user.role != Role.ADMIN:
            return ErrorMessage(message="Admin only", code="NOT_ADMIN").model_dump()
        
        table_id = self.server.get_player_table(user.user_id)
        if not table_id:
            return ErrorMessage(message="Not at a table", code="NOT_AT_TABLE").model_dump()
        
        chip_manager = self.server.get_chip_manager(table_id)
        if not chip_manager:
            return ErrorMessage(message="No chip manager", code="NO_CHIP_MANAGER").model_dump()
        
        # Get target player from table
        table = self.server.tables.get(table_id)
        if not table:
            return ErrorMessage(message="Table not found", code="TABLE_NOT_FOUND").model_dump()
        
        target_player = table.get_player(message.player)
        if not target_player:
            return ErrorMessage(message=f"Player {message.player} not at table", code="PLAYER_NOT_FOUND").model_dump()
        
        try:
            if isinstance(message, GiveChipsMessage):
                await chip_manager.give_chips(
                    user_id=target_player.user_id,
                    player_name=target_player.username,
                    amount=message.amount,
                    admin_id=user.user_id,
                )
                action = "buy_in"
            elif isinstance(message, TakeChipsMessage):
                await chip_manager.take_chips(
                    user_id=target_player.user_id,
                    player_name=target_player.username,
                    amount=message.amount,
                    admin_id=user.user_id,
                )
                action = "cash_out"
            elif isinstance(message, SetChipsMessage):
                await chip_manager.set_chips(
                    user_id=target_player.user_id,
                    player_name=target_player.username,
                    amount=message.amount,
                    admin_id=user.user_id,
                )
                action = "adjustment"
            
            # Get updated chips
            new_chips = target_player.chips
            
            # Broadcast update
            await self.server.broadcast_to_table(
                table_id,
                ChipsUpdatedMessage(
                    player=message.player,
                    chips=new_chips,
                    action=action,
                    amount=message.amount,
                ).model_dump()
            )
            
            # Broadcast updated game state to all players
            await self._broadcast_game_state(table_id)
            
            # Try auto-start after chips given
            if action == "buy_in":
                await self._try_auto_start(table, table_id)
            
            return {"type": "chips_updated", "player": message.player, "chips": new_chips}
            
        except ValueError as e:
            return ErrorMessage(message=str(e), code="CHIP_ERROR").model_dump()
    
    async def _handle_get_ledger(self, user: AuthenticatedUser) -> dict:
        """Handle get ledger request."""
        if user.role != Role.ADMIN:
            return ErrorMessage(message="Admin only", code="NOT_ADMIN").model_dump()
        
        table_id = self.server.get_player_table(user.user_id)
        if not table_id:
            return ErrorMessage(message="Not at a table", code="NOT_AT_TABLE").model_dump()
        
        chip_manager = self.server.get_chip_manager(table_id)
        if not chip_manager:
            return ErrorMessage(message="No chip manager", code="NO_CHIP_MANAGER").model_dump()
        
        transactions = await chip_manager.get_ledger()
        return LedgerMessage(
            transactions=[t.to_dict() for t in transactions]
        ).model_dump()
    
    async def _handle_get_standings(self, user: AuthenticatedUser) -> dict:
        """Handle get standings request."""
        table_id = self.server.get_player_table(user.user_id)
        if not table_id:
            return ErrorMessage(message="Not at a table", code="NOT_AT_TABLE").model_dump()
        
        chip_manager = self.server.get_chip_manager(table_id)
        if not chip_manager:
            return ErrorMessage(message="No chip manager", code="NO_CHIP_MANAGER").model_dump()
        
        standings = await chip_manager.get_standings()
        return StandingsMessage(
            players=[s.to_dict() for s in standings]
        ).model_dump()
    
    async def _handle_end_session(self, user: AuthenticatedUser) -> dict:
        """Handle end session request."""
        if user.role != Role.ADMIN:
            return ErrorMessage(message="Admin only", code="NOT_ADMIN").model_dump()
        
        # Get final standings
        return await self._handle_get_standings(user)
    
    async def _broadcast_game_state(self, table_id: str) -> None:
        """Broadcast game state to all players and spectators at table."""
        table = self.server.tables.get(table_id)
        if not table:
            return
        
        # Get set of seated player IDs to avoid sending spectator state to them
        seated_player_ids = {p.user_id for p in table.players.values()}
        
        # Send to seated players
        for player in table.players.values():
            state = table.get_state_for_player(player.user_id)
            await self.server.send_to_user(
                player.user_id,
                GameStateMessage(**state).model_dump()
            )
        
        # Send to spectators (skip anyone who is also a seated player)
        spectators = self.server.get_spectators(table_id)
        spectator_state = table.get_state_for_spectator()
        for user_id in spectators:
            if user_id in seated_player_ids:
                # User is seated - they already got player state, don't send spectator state
                # Also clean up the inconsistency
                self.server.remove_spectator(user_id, table_id)
                continue
            await self.server.send_to_user(
                user_id,
                GameStateMessage(**spectator_state).model_dump()
            )