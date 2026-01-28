"""Pydantic message schemas for WebSocket protocol."""
from typing import Optional, Any, Literal, Union
from pydantic import BaseModel, Field


# ============= Client -> Server Messages =============

class AuthMessage(BaseModel):
    """Authentication message."""
    type: Literal["auth"] = "auth"
    token: str


class RegisterMessage(BaseModel):
    """Registration message."""
    type: Literal["register"] = "register"
    username: str
    password: str


class LoginMessage(BaseModel):
    """Login message."""
    type: Literal["login"] = "login"
    username: str
    password: str


class RefreshTokenMessage(BaseModel):
    """Refresh token message."""
    type: Literal["refresh_token"] = "refresh_token"
    refresh_token: str


class JoinTableMessage(BaseModel):
    """Join a table."""
    type: Literal["join_table"] = "join_table"
    table_id: str
    seat: Optional[int] = None  # Auto-assign if not specified


class LeaveTableMessage(BaseModel):
    """Leave current table."""
    type: Literal["leave_table"] = "leave_table"


class StandUpMessage(BaseModel):
    """Stand up from seat (become spectator)."""
    type: Literal["stand_up"] = "stand_up"


class ActionMessage(BaseModel):
    """Game action (fold, check, call, bet, raise, all_in)."""
    type: Literal["action"] = "action"
    action: str  # fold, check, call, bet, raise, all_in
    amount: int = 0


class ChatMessage(BaseModel):
    """Chat message."""
    type: Literal["chat"] = "chat"
    message: str


class StartGameMessage(BaseModel):
    """Request to start a new hand (admin/host)."""
    type: Literal["start_game"] = "start_game"


# Admin messages

class CreateTableMessage(BaseModel):
    """Admin: create a new table."""
    type: Literal["create_table"] = "create_table"
    table_name: str
    small_blind: int = 1
    big_blind: int = 2
    min_players: int = 2
    max_players: int = 10


class DeleteTableMessage(BaseModel):
    """Admin: delete a table."""
    type: Literal["delete_table"] = "delete_table"
    table_id: str

class GiveChipsMessage(BaseModel):
    """Admin: give chips to a player."""
    type: Literal["give_chips"] = "give_chips"
    player: str  # username
    amount: int


class TakeChipsMessage(BaseModel):
    """Admin: take chips from a player."""
    type: Literal["take_chips"] = "take_chips"
    player: str  # username
    amount: int


class SetChipsMessage(BaseModel):
    """Admin: set exact chip count."""
    type: Literal["set_chips"] = "set_chips"
    player: str  # username
    amount: int


class GetLedgerMessage(BaseModel):
    """Admin: get transaction ledger."""
    type: Literal["get_ledger"] = "get_ledger"


class GetStandingsMessage(BaseModel):
    """Admin: get current standings."""
    type: Literal["get_standings"] = "get_standings"


class EndSessionMessage(BaseModel):
    """Admin: end the session."""
    type: Literal["end_session"] = "end_session"


class PingMessage(BaseModel):
    """Keep-alive ping from client."""
    type: Literal["ping"] = "ping"


# Union of all client messages
ClientMessage = Union[
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
]


# ============= Server -> Client Messages =============

class ErrorMessage(BaseModel):
    """Error response."""
    type: Literal["error"] = "error"
    message: str
    code: Optional[str] = None


class AuthSuccessMessage(BaseModel):
    """Authentication success."""
    type: Literal["auth_success"] = "auth_success"
    user_id: str
    username: str
    role: str
    access_token: Optional[str] = None
    refresh_token: Optional[str] = None


class GameStateMessage(BaseModel):
    """Full game state update."""
    type: Literal["game_state"] = "game_state"
    table_id: str
    table_name: str
    state: str
    hand_number: int
    dealer_seat: int
    small_blind: int
    big_blind: int
    pot: int
    max_players: int = 10
    community_cards: list[str]
    players: list[dict]
    current_player: Optional[str]
    valid_actions: list[str]
    call_amount: int
    min_raise: int
    # Timer info
    turn_time_seconds: int = 30
    time_remaining: Optional[float] = None
    using_time_bank: bool = False
    current_player_time_bank: float = 0.0


class YourTurnMessage(BaseModel):
    """Notify player it's their turn."""
    type: Literal["your_turn"] = "your_turn"
    valid_actions: list[str]
    call_amount: int
    min_raise: int
    time_remaining: Optional[int] = None


class PlayerActionMessage(BaseModel):
    """Broadcast a player's action."""
    type: Literal["player_action"] = "player_action"
    user_id: str
    username: str
    action: str
    amount: int


class HandResultMessage(BaseModel):
    """Hand result announcement."""
    type: Literal["hand_result"] = "hand_result"
    winners: list[dict]  # {user_id, username, amount, hand}
    pot_total: int
    community_cards: list[str]
    shown_hands: dict[str, list[str]]


class PlayerJoinedMessage(BaseModel):
    """Player joined table."""
    type: Literal["player_joined"] = "player_joined"
    user_id: str
    username: str
    seat: int
    chips: int


class PlayerLeftMessage(BaseModel):
    """Player left table."""
    type: Literal["player_left"] = "player_left"
    user_id: str
    username: str


class PlayerDisconnectedMessage(BaseModel):
    """Player disconnected (within grace period)."""
    type: Literal["player_disconnected"] = "player_disconnected"
    user_id: str
    username: str
    grace_seconds: int


class PlayerReconnectedMessage(BaseModel):
    """Player reconnected."""
    type: Literal["player_reconnected"] = "player_reconnected"
    user_id: str
    username: str


class ChipsUpdatedMessage(BaseModel):
    """Chips updated by admin."""
    type: Literal["chips_updated"] = "chips_updated"
    player: str
    chips: int
    action: str  # buy_in, cash_out, adjustment
    amount: int


class LedgerMessage(BaseModel):
    """Ledger response."""
    type: Literal["ledger"] = "ledger"
    transactions: list[dict]


class StandingsMessage(BaseModel):
    """Standings response."""
    type: Literal["standings"] = "standings"
    players: list[dict]  # {name, buy_ins, cash_outs, net}


class ChatBroadcastMessage(BaseModel):
    """Chat broadcast."""
    type: Literal["chat_broadcast"] = "chat_broadcast"
    username: str
    message: str
    timestamp: str


class TableCreatedMessage(BaseModel):
    """Table created confirmation."""
    type: Literal["table_created"] = "table_created"
    table_id: str
    small_blind: int
    big_blind: int
    min_players: int
    max_players: int


class TableDeletedMessage(BaseModel):
    """Table deleted confirmation."""
    type: Literal["table_deleted"] = "table_deleted"
    table_id: str


class TablesListMessage(BaseModel):
    """List of available tables."""
    type: Literal["tables_list"] = "tables_list"
    tables: list[dict]


class PongMessage(BaseModel):
    """Keep-alive pong response."""
    type: Literal["pong"] = "pong"


# Union of all server messages
ServerMessage = Union[
    ErrorMessage,
    AuthSuccessMessage,
    GameStateMessage,
    YourTurnMessage,
    PlayerActionMessage,
    HandResultMessage,
    PlayerJoinedMessage,
    PlayerLeftMessage,
    PlayerDisconnectedMessage,
    PlayerReconnectedMessage,
    ChipsUpdatedMessage,
    LedgerMessage,
    StandingsMessage,
    ChatBroadcastMessage,
]


def parse_client_message(data: dict) -> ClientMessage:
    """Parse a client message from JSON dict.
    
    Args:
        data: Message data dictionary.
        
    Returns:
        Parsed client message.
        
    Raises:
        ValueError: If message type is unknown or invalid.
    """
    msg_type = data.get("type")
    
    type_map = {
        "auth": AuthMessage,
        "register": RegisterMessage,
        "login": LoginMessage,
        "refresh_token": RefreshTokenMessage,
        "join_table": JoinTableMessage,
        "leave_table": LeaveTableMessage,
        "stand_up": StandUpMessage,
        "action": ActionMessage,
        "chat": ChatMessage,
        "start_game": StartGameMessage,
        "create_table": CreateTableMessage,
        "delete_table": DeleteTableMessage,
        "give_chips": GiveChipsMessage,
        "take_chips": TakeChipsMessage,
        "set_chips": SetChipsMessage,
        "get_ledger": GetLedgerMessage,
        "get_standings": GetStandingsMessage,
        "end_session": EndSessionMessage,
        "ping": PingMessage,
    }
    
    if msg_type not in type_map:
        raise ValueError(f"Unknown message type: {msg_type}")
    
    return type_map[msg_type](**data)
