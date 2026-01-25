"""Betting round logic."""
from enum import Enum
from dataclasses import dataclass
from typing import Optional, TYPE_CHECKING

from src.utils.logger import get_logger

if TYPE_CHECKING:
    from src.game.player import Player

logger = get_logger(__name__)


class ActionType(str, Enum):
    """Player action types."""
    FOLD = "fold"
    CHECK = "check"
    CALL = "call"
    BET = "bet"
    RAISE = "raise"
    ALL_IN = "all_in"


@dataclass
class Action:
    """A player's action."""
    type: ActionType
    amount: int = 0
    
    def to_dict(self) -> dict:
        """Convert to dictionary."""
        return {
            "type": self.type.value,
            "amount": self.amount,
        }


class BettingRound:
    """Manages a single betting round."""
    
    def __init__(
        self,
        players: list["Player"],
        small_blind: int = 0,
        big_blind: int = 0,
        is_preflop: bool = False,
    ):
        """Initialize betting round.
        
        Args:
            players: Active players in seat order.
            small_blind: Small blind amount.
            big_blind: Big blind amount.
            is_preflop: Whether this is the preflop round.
        """
        self.players = players
        self.small_blind = small_blind
        self.big_blind = big_blind
        self.is_preflop = is_preflop
        
        self.current_bet = 0
        self.min_raise = big_blind
        self.last_raiser: Optional[str] = None
        self._action_on: int = 0  # Index into players
        self._actions_taken: dict[str, int] = {}  # user_id -> number of actions
        self._round_complete = False
    
    def get_current_player(self) -> Optional["Player"]:
        """Get the player whose turn it is.
        
        Returns:
            Current player or None if round is complete.
        """
        if self._round_complete:
            return None
        
        active = [p for p in self.players if p.can_act]
        if not active:
            self._round_complete = True
            return None
        
        # Find next player who can act
        for _ in range(len(self.players)):
            player = self.players[self._action_on % len(self.players)]
            if player.can_act:
                return player
            self._action_on += 1
        
        self._round_complete = True
        return None
    
    def get_valid_actions(self, player: "Player") -> list[ActionType]:
        """Get valid actions for a player.
        
        Args:
            player: The player to check.
            
        Returns:
            List of valid action types.
        """
        actions = [ActionType.FOLD]
        
        to_call = self.current_bet - player.current_bet
        
        if to_call == 0:
            actions.append(ActionType.CHECK)
        else:
            actions.append(ActionType.CALL)
        
        # Can always go all-in
        if player.chips > 0:
            actions.append(ActionType.ALL_IN)
        
        # Can raise if has enough chips
        min_raise_to = self.current_bet + self.min_raise
        if player.chips + player.current_bet >= min_raise_to:
            if self.current_bet == 0:
                actions.append(ActionType.BET)
            else:
                actions.append(ActionType.RAISE)
        
        return actions
    
    def get_call_amount(self, player: "Player") -> int:
        """Get the amount needed to call.
        
        Args:
            player: The player.
            
        Returns:
            Amount to call (may be less than current_bet - player_bet if short-stacked).
        """
        to_call = self.current_bet - player.current_bet
        return min(to_call, player.chips)
    
    def get_min_raise(self) -> int:
        """Get the minimum raise amount (total bet, not raise increment)."""
        return self.current_bet + self.min_raise
    
    def process_action(self, player: "Player", action: Action) -> bool:
        """Process a player's action.
        
        Args:
            player: The acting player.
            action: The action to process.
            
        Returns:
            True if action was valid and processed.
            
        Raises:
            ValueError: If action is invalid.
        """
        valid_actions = self.get_valid_actions(player)
        
        if action.type not in valid_actions:
            raise ValueError(f"Invalid action {action.type}. Valid: {valid_actions}")
        
        if action.type == ActionType.FOLD:
            player.fold()
            logger.info(f"{player.username} folds")
        
        elif action.type == ActionType.CHECK:
            if self.current_bet != player.current_bet:
                raise ValueError("Cannot check when there's a bet to call")
            logger.info(f"{player.username} checks")
        
        elif action.type == ActionType.CALL:
            call_amount = self.get_call_amount(player)
            player.bet(call_amount)
            logger.info(f"{player.username} calls {call_amount}")
        
        elif action.type == ActionType.BET:
            if self.current_bet > 0:
                raise ValueError("Cannot bet when there's already a bet")
            if action.amount < self.big_blind:
                raise ValueError(f"Bet must be at least {self.big_blind}")
            
            player.bet(action.amount)
            self.current_bet = player.current_bet
            self.min_raise = action.amount
            self.last_raiser = player.user_id
            logger.info(f"{player.username} bets {action.amount}")
        
        elif action.type == ActionType.RAISE:
            min_raise_to = self.get_min_raise()
            if action.amount < min_raise_to:
                raise ValueError(f"Raise must be at least {min_raise_to}")
            
            raise_amount = action.amount - player.current_bet
            player.bet(raise_amount)
            
            raise_increment = player.current_bet - self.current_bet
            self.min_raise = max(self.min_raise, raise_increment)
            self.current_bet = player.current_bet
            self.last_raiser = player.user_id
            logger.info(f"{player.username} raises to {action.amount}")
        
        elif action.type == ActionType.ALL_IN:
            all_in_amount = player.chips
            actual_bet = player.bet(all_in_amount)
            
            if player.current_bet > self.current_bet:
                # This is a raise
                raise_increment = player.current_bet - self.current_bet
                self.min_raise = max(self.min_raise, raise_increment)
                self.current_bet = player.current_bet
                self.last_raiser = player.user_id
            
            logger.info(f"{player.username} goes all-in for {actual_bet}")
        
        # Track action taken
        self._actions_taken[player.user_id] = self._actions_taken.get(player.user_id, 0) + 1
        
        # Move to next player
        self._action_on = (self._action_on + 1) % len(self.players)
        
        # Check if round is complete
        self._check_round_complete()
        
        return True
    
    def _check_round_complete(self) -> None:
        """Check if the betting round is complete."""
        active_players = [p for p in self.players if p.can_act]
        non_folded_players = [p for p in self.players if not p.is_folded]
        
        # Round complete if no one can act (all folded or all-in)
        if len(active_players) == 0:
            self._round_complete = True
            return
        
        # If only one non-folded player remains, they win (everyone else folded)
        if len(non_folded_players) <= 1:
            self._round_complete = True
            return
        
        # Check if all non-folded players have matched the bet (or are all-in)
        all_matched = all(
            p.current_bet == self.current_bet or p.is_all_in
            for p in non_folded_players
        )
        
        # Check if all active players have had a chance to act
        all_acted = all(
            self._actions_taken.get(p.user_id, 0) > 0
            for p in active_players
        )
        
        # Special case: if someone raised, others need another chance to respond
        if self.last_raiser:
            # Check if the raiser can still act (not all-in)
            raiser_can_act = any(
                p.user_id == self.last_raiser and p.can_act 
                for p in self.players
            )
            
            if raiser_can_act:
                # Action must come back to the raiser for round to complete
                current_player = self.get_current_player()
                if current_player and current_player.user_id == self.last_raiser:
                    if all_matched:
                        self._round_complete = True
            else:
                # Raiser is all-in, round completes when everyone else has 
                # matched the bet and had a chance to act
                if all_matched and all_acted:
                    self._round_complete = True
        elif all_matched and all_acted:
            self._round_complete = True
    
    @property
    def is_complete(self) -> bool:
        """Check if the betting round is complete."""
        return self._round_complete
    
    def force_complete(self) -> None:
        """Force the round to complete (e.g., all but one folded)."""
        self._round_complete = True
