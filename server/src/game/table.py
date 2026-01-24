"""Table state machine for Texas Hold'em."""
import uuid
from enum import Enum
from dataclasses import dataclass, field
from typing import Optional, Callable, Any, Awaitable

from src.game.deck import Deck, Card
from src.game.player import Player
from src.game.pot import Pot, SidePot, calculate_winnings
from src.game.betting import BettingRound, Action, ActionType
from src.game.hand_eval import evaluate_hand, compare_hands, HandResult
from src.config import config
from src.utils.logger import get_logger

logger = get_logger(__name__)


class TableState(str, Enum):
    """Table states."""
    WAITING = "waiting"          # Waiting for players
    STARTING = "starting"        # About to start hand
    PREFLOP = "preflop"          # Pre-flop betting
    FLOP = "flop"                # Flop betting
    TURN = "turn"                # Turn betting
    RIVER = "river"              # River betting
    SHOWDOWN = "showdown"        # Showing hands
    HAND_COMPLETE = "hand_complete"  # Hand finished


@dataclass
class HandResult:
    """Result of a completed hand."""
    winners: list[dict]  # [{user_id, username, amount, hand_description}]
    pot_total: int
    community_cards: list[str]
    shown_hands: dict[str, list[str]]  # user_id -> hole cards (for those who showed)


class Table:
    """A poker table managing a game of Texas Hold'em."""
    
    def __init__(
        self,
        table_id: str,
        small_blind: int = 1,
        big_blind: int = 2,
        min_players: int = 2,
        max_players: int = 10,
    ):
        """Initialize a poker table.
        
        Args:
            table_id: Unique table identifier.
            small_blind: Small blind amount.
            big_blind: Big blind amount.
            min_players: Minimum players to start.
            max_players: Maximum players at table.
        """
        self.table_id = table_id
        self.small_blind = small_blind
        self.big_blind = big_blind
        self.min_players = min_players
        self.max_players = max_players
        
        self.state = TableState.WAITING
        self.players: dict[int, Player] = {}  # seat -> player
        self.deck = Deck()
        self.pot = Pot()
        self.community_cards: list[Card] = []
        
        self.dealer_seat: int = 0
        self.current_betting_round: Optional[BettingRound] = None
        self.hand_number: int = 0
        
        # Callbacks for broadcasting events
        self._event_callback: Optional[Callable[[str, Any], Awaitable[None]]] = None
    
    def set_event_callback(self, callback: Callable[[str, Any], Awaitable[None]]) -> None:
        """Set callback for broadcasting events.
        
        Args:
            callback: Async function(event_type, data) to call on events.
        """
        self._event_callback = callback
    
    async def _emit(self, event_type: str, data: Any) -> None:
        """Emit an event via callback."""
        if self._event_callback:
            await self._event_callback(event_type, data)
    
    # Player management
    
    def add_player(self, player: Player) -> bool:
        """Add a player to the table.
        
        Args:
            player: Player to add.
            
        Returns:
            True if player was added.
        """
        if player.seat in self.players:
            return False
        if player.seat < 0 or player.seat >= self.max_players:
            return False
        if len(self.players) >= self.max_players:
            return False
        
        self.players[player.seat] = player
        logger.info(f"{player.username} joined table {self.table_id} at seat {player.seat}")
        return True
    
    def remove_player(self, user_id: str) -> Optional[Player]:
        """Remove a player from the table.
        
        Args:
            user_id: User ID to remove.
            
        Returns:
            Removed player or None.
        """
        for seat, player in list(self.players.items()):
            if player.user_id == user_id:
                del self.players[seat]
                logger.info(f"{player.username} left table {self.table_id}")
                return player
        return None
    
    def get_player(self, username: str) -> Optional[Player]:
        """Get player by username.
        
        Args:
            username: Player's username.
            
        Returns:
            Player if found.
        """
        for player in self.players.values():
            if player.username.lower() == username.lower():
                return player
        return None
    
    def get_player_by_id(self, user_id: str) -> Optional[Player]:
        """Get player by user ID.
        
        Args:
            user_id: User's ID.
            
        Returns:
            Player if found.
        """
        for player in self.players.values():
            if player.user_id == user_id:
                return player
        return None
    
    def get_next_available_seat(self) -> Optional[int]:
        """Get the next available seat.
        
        Returns:
            Seat number or None if full.
        """
        for seat in range(self.max_players):
            if seat not in self.players:
                return seat
        return None
    
    def get_active_players(self) -> list[Player]:
        """Get players active in the current hand."""
        return [p for p in self._get_players_in_order() if p.is_active]
    
    def _get_players_in_order(self) -> list[Player]:
        """Get players in seat order starting from dealer + 1."""
        if not self.players:
            return []
        
        seats = sorted(self.players.keys())
        dealer_idx = 0
        for i, seat in enumerate(seats):
            if seat >= self.dealer_seat:
                dealer_idx = i
                break
        
        # Rotate so first player after dealer is first
        ordered_seats = seats[dealer_idx:] + seats[:dealer_idx]
        if ordered_seats and ordered_seats[0] == self.dealer_seat:
            ordered_seats = ordered_seats[1:] + ordered_seats[:1]
        
        return [self.players[seat] for seat in ordered_seats]
    
    # Game flow
    
    def can_start_hand(self) -> bool:
        """Check if a hand can be started."""
        active_players = [p for p in self.players.values() 
                        if not p.is_sitting_out and p.chips > 0]
        return len(active_players) >= self.min_players
    
    async def start_hand(self) -> bool:
        """Start a new hand.
        
        Returns:
            True if hand started successfully.
        """
        if not self.can_start_hand():
            return False
        
        if self.state != TableState.WAITING:
            return False
        
        self.hand_number += 1
        self.state = TableState.STARTING
        
        # Reset for new hand
        self.deck.reset()
        self.pot.reset()
        self.community_cards = []
        
        for player in self.players.values():
            player.reset_for_new_hand()
        
        # Move dealer button
        self._advance_dealer()
        
        # Post blinds
        self._post_blinds()
        
        # Deal hole cards
        self._deal_hole_cards()
        
        # Start preflop betting
        self.state = TableState.PREFLOP
        self._start_betting_round()
        
        logger.info(f"Started hand #{self.hand_number} on table {self.table_id}")
        
        await self._emit("hand_started", {
            "hand_number": self.hand_number,
            "dealer_seat": self.dealer_seat,
        })
        
        return True
    
    def _advance_dealer(self) -> None:
        """Move dealer button to next player."""
        seats = sorted(self.players.keys())
        if not seats:
            return
        
        current_idx = 0
        for i, seat in enumerate(seats):
            if seat > self.dealer_seat:
                current_idx = i
                break
        else:
            current_idx = 0
        
        self.dealer_seat = seats[current_idx]
    
    def _post_blinds(self) -> None:
        """Post small and big blinds."""
        players = self._get_players_in_order()
        active = [p for p in players if not p.is_sitting_out and p.chips > 0]
        
        if len(active) < 2:
            return
        
        # Heads-up: dealer posts SB, other posts BB
        # Otherwise: player after dealer posts SB, next posts BB
        if len(active) == 2:
            sb_player = active[1]  # Dealer
            bb_player = active[0]
        else:
            sb_player = active[0]
            bb_player = active[1]
        
        # Post blinds
        sb_amount = sb_player.bet(min(self.small_blind, sb_player.chips))
        self.pot.add_bet(sb_player.user_id, sb_amount)
        
        bb_amount = bb_player.bet(min(self.big_blind, bb_player.chips))
        self.pot.add_bet(bb_player.user_id, bb_amount)
        
        logger.info(f"Blinds posted: {sb_player.username}={sb_amount}, {bb_player.username}={bb_amount}")
    
    def _deal_hole_cards(self) -> None:
        """Deal 2 hole cards to each active player."""
        for player in self._get_players_in_order():
            if not player.is_sitting_out and player.chips >= 0:
                cards = self.deck.deal(2)
                player.receive_cards(cards)
    
    def _start_betting_round(self) -> None:
        """Start a new betting round."""
        active_players = [p for p in self._get_players_in_order() 
                         if not p.is_folded and not p.is_sitting_out]
        
        # Reset current bets for new round (except preflop where blinds are already in)
        if self.state != TableState.PREFLOP:
            for player in self.players.values():
                player.current_bet = 0
        
        self.current_betting_round = BettingRound(
            players=active_players,
            small_blind=self.small_blind,
            big_blind=self.big_blind,
            is_preflop=(self.state == TableState.PREFLOP),
        )
        
        if self.state == TableState.PREFLOP:
            self.current_betting_round.current_bet = self.big_blind
    
    async def process_action(self, user_id: str, action: Action) -> bool:
        """Process a player's action.
        
        Args:
            user_id: Acting player's user ID.
            action: The action.
            
        Returns:
            True if action processed.
        """
        if not self.current_betting_round:
            return False
        
        current_player = self.current_betting_round.get_current_player()
        if not current_player or current_player.user_id != user_id:
            return False
        
        # Process the action
        self.current_betting_round.process_action(current_player, action)
        
        # Add bet to pot
        if action.type in (ActionType.BET, ActionType.RAISE, ActionType.CALL, ActionType.ALL_IN):
            # The bet amount was already applied to player, add to pot
            pass  # Pot tracking happens at end of round
        
        await self._emit("player_action", {
            "user_id": user_id,
            "username": current_player.username,
            "action": action.to_dict(),
        })
        
        # Check if round is complete
        if self.current_betting_round.is_complete:
            await self._end_betting_round()
        
        return True
    
    async def _end_betting_round(self) -> None:
        """End the current betting round and advance game state."""
        # Collect bets into pot
        for player in self.players.values():
            if player.current_bet > 0:
                self.pot.add_bet(player.user_id, player.current_bet)
                player.current_bet = 0
        
        # Check if only one player remains
        active = [p for p in self.players.values() if not p.is_folded and p.is_active]
        if len(active) <= 1:
            await self._end_hand()
            return
        
        # Check if all but one are all-in
        can_act = [p for p in active if p.can_act]
        if len(can_act) <= 1:
            # Run out the board
            await self._run_out_board()
            return
        
        # Advance to next state
        if self.state == TableState.PREFLOP:
            self.state = TableState.FLOP
            self._deal_community_cards(3)
        elif self.state == TableState.FLOP:
            self.state = TableState.TURN
            self._deal_community_cards(1)
        elif self.state == TableState.TURN:
            self.state = TableState.RIVER
            self._deal_community_cards(1)
        elif self.state == TableState.RIVER:
            await self._showdown()
            return
        
        self._start_betting_round()
        
        await self._emit("state_changed", {
            "state": self.state.value,
            "community_cards": [str(c) for c in self.community_cards],
            "pot": self.pot.get_total(),
        })
    
    def _deal_community_cards(self, count: int) -> None:
        """Deal community cards.
        
        Args:
            count: Number of cards to deal.
        """
        self.deck.burn()  # Burn one card
        cards = self.deck.deal(count)
        self.community_cards.extend(cards)
        logger.info(f"Dealt {count} community cards: {cards}")
    
    async def _run_out_board(self) -> None:
        """Run out remaining community cards when all are all-in."""
        while len(self.community_cards) < 5:
            if len(self.community_cards) == 0:
                self._deal_community_cards(3)
            else:
                self._deal_community_cards(1)
        
        await self._showdown()
    
    async def _showdown(self) -> None:
        """Handle showdown and determine winners."""
        self.state = TableState.SHOWDOWN
        
        active = [p for p in self.players.values() if not p.is_folded and p.is_active]
        
        # Calculate side pots
        all_in_players = {p.user_id: self.pot.get_contribution(p.user_id) 
                        for p in self.players.values() if p.is_all_in}
        self.pot.calculate_side_pots(all_in_players)
        
        # Evaluate hands
        hand_results: list[tuple[str, Any]] = []
        for player in active:
            from src.game.hand_eval import evaluate_hand as eval_hand
            result = eval_hand(player.hole_cards, self.community_cards)
            hand_results.append((player.user_id, result))
        
        # Determine winners for each pot
        winners_by_pot: dict[int, list[str]] = {}
        shown_hands: dict[str, list[str]] = {}
        
        for pot_idx, side_pot in enumerate(self.pot.side_pots):
            eligible_hands = [
                (uid, hand) for uid, hand in hand_results 
                if uid in side_pot.eligible_players
            ]
            
            if eligible_hands:
                winner_groups = compare_hands(eligible_hands)
                winners_by_pot[pot_idx] = winner_groups[0]  # First group has best hands
                
                # Record shown hands
                for uid in winner_groups[0]:
                    player = self.get_player_by_id(uid)
                    if player:
                        shown_hands[uid] = [str(c) for c in player.hole_cards]
        
        # Calculate and distribute winnings
        winnings = calculate_winnings(self.pot.side_pots, winners_by_pot)
        
        winner_info = []
        for user_id, amount in winnings.items():
            player = self.get_player_by_id(user_id)
            if player:
                player.win_pot(amount)
                hand_desc = ""
                for uid, hand in hand_results:
                    if uid == user_id:
                        hand_desc = hand.description
                        break
                winner_info.append({
                    "user_id": user_id,
                    "username": player.username,
                    "amount": amount,
                    "hand": hand_desc,
                })
        
        logger.info(f"Hand #{self.hand_number} winners: {winner_info}")
        
        await self._emit("hand_result", {
            "winners": winner_info,
            "pot_total": self.pot.get_total(),
            "community_cards": [str(c) for c in self.community_cards],
            "shown_hands": shown_hands,
        })
        
        await self._end_hand()
    
    async def _end_hand(self) -> None:
        """End the current hand."""
        self.state = TableState.HAND_COMPLETE
        
        # If only one player left (everyone else folded)
        active = [p for p in self.players.values() if not p.is_folded and p.is_active]
        if len(active) == 1:
            winner = active[0]
            amount = self.pot.get_total()
            winner.win_pot(amount)
            
            await self._emit("hand_result", {
                "winners": [{
                    "user_id": winner.user_id,
                    "username": winner.username,
                    "amount": amount,
                    "hand": "Others folded",
                }],
                "pot_total": amount,
                "community_cards": [str(c) for c in self.community_cards],
                "shown_hands": {},
            })
        
        # Reset to waiting
        self.state = TableState.WAITING
        self.current_betting_round = None
        
        logger.info(f"Hand #{self.hand_number} complete on table {self.table_id}")
    
    # State serialization
    
    def get_state_for_player(self, user_id: str) -> dict:
        """Get table state from a player's perspective.
        
        Args:
            user_id: The player requesting state (can be spectator).
            
        Returns:
            State dictionary with appropriate visibility.
        """
        players_data = []
        for seat in sorted(self.players.keys()):
            player = self.players[seat]
            if player.user_id == user_id:
                player_data = player.to_private_dict()
                player_data["is_you"] = True
                player_data["is_connected"] = not player.is_disconnected
                players_data.append(player_data)
            else:
                player_data = player.to_dict(hide_cards=True)
                player_data["is_you"] = False
                player_data["is_connected"] = not player.is_disconnected
                players_data.append(player_data)
        
        current_player_id = None
        valid_actions = []
        call_amount = 0
        min_raise = 0
        
        if self.current_betting_round:
            current = self.current_betting_round.get_current_player()
            if current:
                current_player_id = current.user_id
                if current.user_id == user_id:
                    valid_actions = [a.value for a in 
                                    self.current_betting_round.get_valid_actions(current)]
                    call_amount = self.current_betting_round.get_call_amount(current)
                    min_raise = self.current_betting_round.get_min_raise()
        
        return {
            "table_id": self.table_id,
            "state": self.state.value,
            "hand_number": self.hand_number,
            "dealer_seat": self.dealer_seat,
            "small_blind": self.small_blind,
            "big_blind": self.big_blind,
            "pot": self.pot.get_total(),
            "max_players": self.max_players,
            "community_cards": [str(c) for c in self.community_cards],
            "players": players_data,
            "current_player": current_player_id,
            "valid_actions": valid_actions,
            "call_amount": call_amount,
            "min_raise": min_raise,
        }
    
    def get_state_for_spectator(self) -> dict:
        """Get table state from a spectator's perspective.
        
        Returns:
            State dictionary with no player marked as 'you'.
        """
        players_data = []
        for seat in sorted(self.players.keys()):
            player = self.players[seat]
            player_data = player.to_dict(hide_cards=True)
            player_data["is_you"] = False
            player_data["is_connected"] = not player.is_disconnected
            players_data.append(player_data)
        
        return {
            "table_id": self.table_id,
            "state": self.state.value,
            "hand_number": self.hand_number,
            "dealer_seat": self.dealer_seat,
            "small_blind": self.small_blind,
            "big_blind": self.big_blind,
            "pot": self.pot.get_total(),
            "max_players": self.max_players,
            "community_cards": [str(c) for c in self.community_cards],
            "players": players_data,
            "current_player": None,
            "valid_actions": [],
            "call_amount": 0,
            "min_raise": 0,
        }
    
    def to_dict(self) -> dict:
        """Serialize full table state for persistence."""
        return {
            "table_id": self.table_id,
            "state": self.state.value,
            "hand_number": self.hand_number,
            "dealer_seat": self.dealer_seat,
            "small_blind": self.small_blind,
            "big_blind": self.big_blind,
            "min_players": self.min_players,
            "max_players": self.max_players,
            "pot": self.pot.to_dict(),
            "community_cards": [c.to_dict() for c in self.community_cards],
            "players": {
                seat: player.to_dict(hide_cards=False)
                for seat, player in self.players.items()
            },
        }
    
    @classmethod
    def from_dict(cls, data: dict) -> "Table":
        """Restore table from serialized state."""
        table = cls(
            table_id=data["table_id"],
            small_blind=data["small_blind"],
            big_blind=data["big_blind"],
            min_players=data.get("min_players", 2),
            max_players=data.get("max_players", 10),
        )
        table.state = TableState(data["state"])
        table.hand_number = data["hand_number"]
        table.dealer_seat = data["dealer_seat"]
        
        for seat_str, player_data in data["players"].items():
            player = Player.from_dict(player_data)
            table.players[int(seat_str)] = player
        
        for card_data in data["community_cards"]:
            table.community_cards.append(Card.from_dict(card_data))
        
        return table
