"""Pot and side-pot calculation."""
from dataclasses import dataclass, field
from typing import Optional

from src.utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class SidePot:
    """A pot or side pot."""
    amount: int
    eligible_players: list[str]  # user_ids of players eligible to win this pot
    
    def to_dict(self) -> dict:
        """Convert to dictionary."""
        return {
            "amount": self.amount,
            "eligible_players": self.eligible_players,
        }
    
    @classmethod
    def from_dict(cls, data: dict) -> "SidePot":
        """Restore from dictionary."""
        return cls(
            amount=data["amount"],
            eligible_players=data["eligible_players"],
        )


@dataclass
class Pot:
    """Manages pot and side pots for a hand."""
    
    main_pot: int = 0
    side_pots: list[SidePot] = field(default_factory=list)
    _contributions: dict[str, int] = field(default_factory=dict)  # user_id -> total contributed
    
    def add_bet(self, user_id: str, amount: int) -> None:
        """Add a bet to the pot.
        
        Args:
            user_id: Player's user ID.
            amount: Bet amount.
        """
        if user_id not in self._contributions:
            self._contributions[user_id] = 0
        self._contributions[user_id] += amount
        self.main_pot += amount
    
    def calculate_side_pots(self, all_in_players: dict[str, int]) -> None:
        """Calculate side pots based on all-in amounts.
        
        Args:
            all_in_players: Dict of user_id -> total chips put in when going all-in.
        """
        if not all_in_players:
            # No side pots needed
            self.side_pots = [SidePot(
                amount=self.main_pot,
                eligible_players=list(self._contributions.keys())
            )]
            return
        
        # Sort all-in amounts
        sorted_all_ins = sorted(set(all_in_players.values()))
        
        # Build side pots
        pots = []
        prev_level = 0
        remaining_players = set(self._contributions.keys())
        
        for level in sorted_all_ins:
            level_amount = level - prev_level
            pot_amount = 0
            
            for user_id, contrib in self._contributions.items():
                if user_id in remaining_players:
                    contribution_at_level = min(contrib - prev_level, level_amount)
                    if contribution_at_level > 0:
                        pot_amount += contribution_at_level
            
            if pot_amount > 0:
                pots.append(SidePot(
                    amount=pot_amount,
                    eligible_players=list(remaining_players)
                ))
            
            # Remove players who are all-in at this level
            for user_id, all_in_amount in all_in_players.items():
                if all_in_amount == level:
                    remaining_players.discard(user_id)
            
            prev_level = level
        
        # Final pot for remaining players
        remaining_amount = self.main_pot - sum(p.amount for p in pots)
        if remaining_amount > 0 and remaining_players:
            pots.append(SidePot(
                amount=remaining_amount,
                eligible_players=list(remaining_players)
            ))
        
        self.side_pots = pots
        logger.debug(f"Calculated {len(pots)} side pots")
    
    def get_total(self) -> int:
        """Get total pot amount."""
        return self.main_pot
    
    def reset(self) -> None:
        """Reset pot for new hand."""
        self.main_pot = 0
        self.side_pots = []
        self._contributions = {}
    
    def get_contribution(self, user_id: str) -> int:
        """Get a player's total contribution to the pot."""
        return self._contributions.get(user_id, 0)
    
    def to_dict(self) -> dict:
        """Convert to dictionary."""
        return {
            "total": self.main_pot,
            "side_pots": [sp.to_dict() for sp in self.side_pots],
            "contributions": self._contributions,
        }
    
    @classmethod
    def from_dict(cls, data: dict) -> "Pot":
        """Restore from dictionary."""
        pot = cls()
        pot.main_pot = data.get("total", 0)
        pot.side_pots = [SidePot.from_dict(sp) for sp in data.get("side_pots", [])]
        pot._contributions = data.get("contributions", {})
        return pot


def calculate_winnings(
    side_pots: list[SidePot],
    winners_by_pot: dict[int, list[str]]
) -> dict[str, int]:
    """Calculate how much each player wins.
    
    Args:
        side_pots: List of side pots.
        winners_by_pot: Dict of pot_index -> list of winner user_ids.
        
    Returns:
        Dict of user_id -> amount won.
    """
    winnings: dict[str, int] = {}
    
    for pot_idx, pot in enumerate(side_pots):
        if pot_idx not in winners_by_pot:
            continue
        
        winners = winners_by_pot[pot_idx]
        if not winners:
            continue
        
        # Split pot among winners
        share = pot.amount // len(winners)
        remainder = pot.amount % len(winners)
        
        for i, winner in enumerate(winners):
            amount = share + (1 if i < remainder else 0)
            if winner not in winnings:
                winnings[winner] = 0
            winnings[winner] += amount
    
    return winnings
