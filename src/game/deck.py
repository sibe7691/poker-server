"""Card deck implementation."""
import random
from enum import Enum
from dataclasses import dataclass
from typing import Optional


class Suit(str, Enum):
    """Card suits."""
    HEARTS = "h"
    DIAMONDS = "d"
    CLUBS = "c"
    SPADES = "s"
    
    def __str__(self) -> str:
        return self.value


class Rank(int, Enum):
    """Card ranks (2-14, where 14 is Ace)."""
    TWO = 2
    THREE = 3
    FOUR = 4
    FIVE = 5
    SIX = 6
    SEVEN = 7
    EIGHT = 8
    NINE = 9
    TEN = 10
    JACK = 11
    QUEEN = 12
    KING = 13
    ACE = 14
    
    def __str__(self) -> str:
        if self.value <= 10:
            return str(self.value)
        return {11: "J", 12: "Q", 13: "K", 14: "A"}[self.value]


@dataclass(frozen=True)
class Card:
    """A playing card."""
    rank: Rank
    suit: Suit
    
    def __str__(self) -> str:
        return f"{self.rank}{self.suit}"
    
    def __repr__(self) -> str:
        return str(self)
    
    def to_dict(self) -> dict:
        """Convert to dictionary for serialization."""
        return {"rank": self.rank.value, "suit": self.suit.value}
    
    @classmethod
    def from_dict(cls, data: dict) -> "Card":
        """Create from dictionary."""
        return cls(rank=Rank(data["rank"]), suit=Suit(data["suit"]))
    
    @classmethod
    def from_string(cls, s: str) -> "Card":
        """Parse card from string like 'Ah', '10s', '2c'.
        
        Args:
            s: Card string (rank + suit).
            
        Returns:
            Card instance.
        """
        suit = Suit(s[-1].lower())
        rank_str = s[:-1]
        
        rank_map = {"A": 14, "K": 13, "Q": 12, "J": 11, "T": 10}
        if rank_str in rank_map:
            rank = Rank(rank_map[rank_str])
        else:
            rank = Rank(int(rank_str))
        
        return cls(rank=rank, suit=suit)


class Deck:
    """A standard 52-card deck."""
    
    def __init__(self):
        """Initialize and shuffle a new deck."""
        self._cards: list[Card] = []
        self.reset()
    
    def reset(self) -> None:
        """Reset and shuffle the deck."""
        self._cards = [
            Card(rank=rank, suit=suit)
            for suit in Suit
            for rank in Rank
        ]
        self.shuffle()
    
    def shuffle(self) -> None:
        """Shuffle the deck."""
        random.shuffle(self._cards)
    
    def deal(self, count: int = 1) -> list[Card]:
        """Deal cards from the deck.
        
        Args:
            count: Number of cards to deal.
            
        Returns:
            List of dealt cards.
            
        Raises:
            ValueError: If not enough cards remain.
        """
        if count > len(self._cards):
            raise ValueError(f"Cannot deal {count} cards, only {len(self._cards)} remain")
        
        dealt = self._cards[:count]
        self._cards = self._cards[count:]
        return dealt
    
    def deal_one(self) -> Card:
        """Deal a single card.
        
        Returns:
            The dealt card.
        """
        return self.deal(1)[0]
    
    def burn(self) -> Card:
        """Burn (discard) a card from the top of the deck.
        
        Returns:
            The burned card.
        """
        return self.deal_one()
    
    @property
    def remaining(self) -> int:
        """Number of cards remaining in the deck."""
        return len(self._cards)
    
    def __len__(self) -> int:
        return len(self._cards)
