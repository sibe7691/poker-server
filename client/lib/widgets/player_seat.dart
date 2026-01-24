import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/player.dart';
import 'playing_card.dart';

/// A player seat widget showing player info, chips, and cards
class PlayerSeat extends StatelessWidget {
  final Player player;
  final int seatNumber;
  final bool isDealer;
  final bool isCurrentTurn;
  final bool isSmallBlind;
  final bool isBigBlind;
  final int? lastAction; // For showing action animation

  const PlayerSeat({
    super.key,
    required this.player,
    required this.seatNumber,
    this.isDealer = false,
    this.isCurrentTurn = false,
    this.isSmallBlind = false,
    this.isBigBlind = false,
    this.lastAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Seat number badge
        _buildSeatNumber(),
        const SizedBox(height: 2),
        // Cards (if player has cards)
        if (player.holeCards.isNotEmpty || player.hasCards || !player.isFolded)
          _buildCards(),
        const SizedBox(height: 4),
        // Player info container
        _buildPlayerInfo(context),
        const SizedBox(height: 4),
        // Current bet (if any)
        if (player.currentBet > 0)
          _buildBetChip(),
      ],
    );
  }

  Widget _buildSeatNumber() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: PokerTheme.surfaceDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '#$seatNumber',
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCards() {
    if (player.isFolded) {
      return Opacity(
        opacity: 0.3,
        child: HoleCards(
          cards: const [],
          isHidden: true,
          isSmall: true,
        ),
      );
    }

    return HoleCards(
      cards: player.holeCards,
      isHidden: player.holeCards.isEmpty && !player.isYou,
      isSmall: !player.isYou,
    );
  }

  Widget _buildPlayerInfo(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: player.isFolded
              ? [Colors.grey.shade800, Colors.grey.shade900]
              : isCurrentTurn
                  ? [PokerTheme.goldAccent.withValues(alpha: 0.3), PokerTheme.surfaceLight]
                  : player.isYou
                      ? [PokerTheme.tableFelt.withValues(alpha: 0.5), PokerTheme.surfaceLight]
                      : [PokerTheme.surfaceLight, PokerTheme.surfaceDark],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentTurn
              ? PokerTheme.goldAccent
              : player.isYou
                  ? PokerTheme.tableFelt
                  : Colors.transparent,
          width: isCurrentTurn ? 2 : 1,
        ),
        boxShadow: isCurrentTurn
            ? [
                BoxShadow(
                  color: PokerTheme.goldAccent.withValues(alpha: 0.5),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Username with position badges
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDealer) _buildBadge('D', PokerTheme.goldAccent),
              if (isSmallBlind) _buildBadge('SB', PokerTheme.chipBlue),
              if (isBigBlind) _buildBadge('BB', PokerTheme.chipRed),
              const SizedBox(width: 4),
              Text(
                player.username,
                style: TextStyle(
                  color: player.isFolded ? Colors.grey : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (!player.isConnected)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.wifi_off,
                    size: 14,
                    color: Colors.orange,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Chip count
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 12,
                color: player.isAllIn
                    ? PokerTheme.chipRed
                    : PokerTheme.goldAccent,
              ),
              const SizedBox(width: 4),
              Text(
                player.isAllIn ? 'ALL IN' : formatChips(player.chips),
                style: TextStyle(
                  color: player.isAllIn
                      ? PokerTheme.chipRed
                      : PokerTheme.goldAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBetChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: PokerTheme.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PokerTheme.goldAccent, width: 1),
      ),
      child: Text(
        formatChips(player.currentBet),
        style: const TextStyle(
          color: PokerTheme.goldAccent,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    ).animate().scale(
      duration: 200.ms,
      curve: Curves.easeOut,
    );
  }
}

/// Empty seat widget for available positions
class EmptySeat extends StatelessWidget {
  final int seatNumber;
  final VoidCallback? onTap;
  final bool isChangeSeat; // Whether this is for changing seats (vs initial seat selection)

  const EmptySeat({
    super.key,
    required this.seatNumber,
    this.onTap,
    this.isChangeSeat = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSelectable = onTap != null;
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelectable
              ? PokerTheme.tableFelt.withValues(alpha: 0.3)
              : PokerTheme.surfaceDark.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelectable 
                ? (isChangeSeat ? PokerTheme.chipBlue : PokerTheme.goldAccent) 
                : Colors.white24,
            width: isSelectable ? 2 : 1,
            style: BorderStyle.solid,
          ),
          boxShadow: isSelectable
              ? [
                  BoxShadow(
                    color: (isChangeSeat ? PokerTheme.chipBlue : PokerTheme.goldAccent)
                        .withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seat number badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isSelectable 
                    ? (isChangeSeat ? PokerTheme.chipBlue : PokerTheme.goldAccent)
                        .withValues(alpha: 0.2)
                    : PokerTheme.surfaceDark.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '#$seatNumber',
                style: TextStyle(
                  color: isSelectable 
                      ? (isChangeSeat ? PokerTheme.chipBlue : PokerTheme.goldAccent)
                      : Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              isSelectable 
                  ? (isChangeSeat ? Icons.swap_horiz : Icons.add_circle_outline) 
                  : Icons.person_add_outlined,
              color: isSelectable 
                  ? (isChangeSeat ? PokerTheme.chipBlue : PokerTheme.goldAccent) 
                  : Colors.white38,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              isSelectable 
                  ? (isChangeSeat ? 'Move Here' : 'Sit Here') 
                  : 'Empty',
              style: TextStyle(
                color: isSelectable 
                    ? (isChangeSeat ? PokerTheme.chipBlue : PokerTheme.goldAccent) 
                    : Colors.white38,
                fontSize: 12,
                fontWeight: isSelectable ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
