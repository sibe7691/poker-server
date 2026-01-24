"""Player model."""
from dataclasses import dataclass, field
from typing import Optional
from src.game.deck import Card


@dataclass
class Player:
    """A player at the poker table."""
    
    user_id: str
    username: str
    seat: int
    chips: int = 0
    hole_cards: list[Card] = field(default_factory=list)
    is_folded: bool = False
    is_all_in: bool = False
    current_bet: int = 0
    is_sitting_out: bool = False
    is_disconnected: bool = False
    
    def reset_for_new_hand(self) -> None:
        """Reset player state for a new hand."""
        self.hole_cards = []
        self.is_folded = False
        self.is_all_in = False
        self.current_bet = 0
    
    def bet(self, amount: int) -> int:
        """Place a bet, going all-in if necessary.
        
        Args:
            amount: Amount to bet.
            
        Returns:
            Actual amount bet (may be less if all-in).
        """
        actual_bet = min(amount, self.chips)
        self.chips -= actual_bet
        self.current_bet += actual_bet
        
        if self.chips == 0:
            self.is_all_in = True
        
        return actual_bet
    
    def fold(self) -> None:
        """Fold the hand."""
        self.is_folded = True
    
    def receive_cards(self, cards: list[Card]) -> None:
        """Receive hole cards.
        
        Args:
            cards: Cards to receive.
        """
        self.hole_cards = cards
    
    def win_pot(self, amount: int) -> None:
        """Win chips from the pot.
        
        Args:
            amount: Amount won.
        """
        self.chips += amount
    
    @property
    def is_active(self) -> bool:
        """Check if player is active in the current hand."""
        return (
            not self.is_folded 
            and not self.is_sitting_out 
            and len(self.hole_cards) > 0
        )
    
    @property
    def can_act(self) -> bool:
        """Check if player can take an action."""
        return self.is_active and not self.is_all_in
    
    def to_dict(self, hide_cards: bool = True) -> dict:
        """Convert to dictionary for serialization.
        
        Args:
            hide_cards: If True, don't include hole cards.
            
        Returns:
            Player state dictionary.
        """
        data = {
            "user_id": self.user_id,
            "username": self.username,
            "seat": self.seat,
            "chips": self.chips,
            "is_folded": self.is_folded,
            "is_all_in": self.is_all_in,
            "current_bet": self.current_bet,
            "is_sitting_out": self.is_sitting_out,
            "is_disconnected": self.is_disconnected,
            "has_cards": len(self.hole_cards) > 0,
        }
        
        if not hide_cards:
            data["hole_cards"] = [str(c) for c in self.hole_cards]
        
        return data
    
    def to_private_dict(self) -> dict:
        """Convert to dictionary including hole cards (for the player themselves)."""
        return self.to_dict(hide_cards=False)
    
    @classmethod
    def from_dict(cls, data: dict) -> "Player":
        """Create from dictionary."""
        player = cls(
            user_id=data["user_id"],
            username=data["username"],
            seat=data["seat"],
            chips=data["chips"],
            is_folded=data.get("is_folded", False),
            is_all_in=data.get("is_all_in", False),
            current_bet=data.get("current_bet", 0),
            is_sitting_out=data.get("is_sitting_out", False),
            is_disconnected=data.get("is_disconnected", False),
        )
        
        if "hole_cards" in data:
            player.hole_cards = [Card.from_string(c) for c in data["hole_cards"]]
        
        return player
