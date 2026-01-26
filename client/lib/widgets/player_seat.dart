import 'package:flutter/material.dart';
import 'package:poker_app/core/constants.dart';
import 'package:poker_app/core/theme.dart';
import 'package:poker_app/core/utils.dart';
import 'package:poker_app/models/player.dart';
import 'package:poker_app/widgets/playing_card.dart';

/// A player seat widget showing player info, chips, and cards
class PlayerSeat extends StatelessWidget {
  const PlayerSeat({
    required this.player,
    super.key,
    this.isCurrentTurn = false,
    this.isSmallBlind = false,
    this.isBigBlind = false,
    this.lastAction,
    this.gamePhase = GamePhase.waiting,
  });
  final Player player;
  final bool isCurrentTurn;
  final bool isSmallBlind;
  final bool isBigBlind;
  final int? lastAction; // For showing action animation
  final GamePhase gamePhase;

  /// Whether the player is out of chips and waiting for a rebuy
  bool get _isOutOfChips => player.chips == 0 && !player.isAllIn;

  @override
  Widget build(BuildContext context) {
    // Only show cards during active game phases, not when waiting
    final isGameActive = gamePhase != GamePhase.waiting;
    final shouldShowCards =
        isGameActive &&
        (player.holeCards.isNotEmpty || player.hasCards) &&
        !_isOutOfChips;

    return Opacity(
      opacity: _isOutOfChips ? 0.5 : 1.0,
      child: SizedBox(
        width: 120,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cards (only if player has cards and game is active)
            if (shouldShowCards && !player.isFolded)
              _buildCards()
            else if (shouldShowCards && player.isFolded)
              _buildFoldedCards(),
            if (shouldShowCards) const SizedBox(height: 4),
            // Player info container
            _buildPlayerInfo(context),
            // Note: Bet chips are now rendered separately in PokerTable
            // to position them on the table surface
          ],
        ),
      ),
    );
  }

  Widget _buildFoldedCards() {
    return const Opacity(
      opacity: 0.3,
      child: HoleCards(cards: [], isHidden: true, isSmall: true),
    );
  }

  Widget _buildCards() {
    return HoleCards(
      cards: player.holeCards,
      isHidden: player.holeCards.isEmpty && !player.isYou,
      isSmall: !player.isYou,
    );
  }

  Widget _buildPlayerInfo(BuildContext context) {
    // Determine gradient colors based on player state
    List<Color> gradientColors;
    if (_isOutOfChips) {
      gradientColors = [Colors.grey.shade700, Colors.grey.shade800];
    } else if (player.isFolded) {
      gradientColors = [Colors.grey.shade800, Colors.grey.shade900];
    } else if (isCurrentTurn) {
      gradientColors = [
        PokerTheme.goldAccent.withValues(alpha: 0.3),
        PokerTheme.surfaceLight,
      ];
    } else if (player.isYou) {
      gradientColors = [
        PokerTheme.tableFelt.withValues(alpha: 0.5),
        PokerTheme.surfaceLight,
      ];
    } else {
      gradientColors = [PokerTheme.surfaceLight, PokerTheme.surfaceDark];
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
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
          // Username with position badges (dealer button is rendered
          // on the table)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSmallBlind) _buildBadge('SB', PokerTheme.chipBlue),
              if (isBigBlind) _buildBadge('BB', PokerTheme.chipRed),
              if (isSmallBlind || isBigBlind) const SizedBox(width: 4),
              Flexible(
                child: Text(
                  player.username,
                  style: TextStyle(
                    color: player.isFolded ? Colors.grey : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (!player.isConnected)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.wifi_off, size: 14, color: Colors.orange),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Chip count or status
          if (_isOutOfChips)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 12,
                  color: Colors.orange.shade300,
                ),
                const SizedBox(width: 4),
                Text(
                  'Needs chips',
                  style: TextStyle(
                    color: Colors.orange.shade300,
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  ),
                ),
              ],
            )
          else
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
}

/// Empty seat widget for available positions
class EmptySeat extends StatelessWidget {
  const EmptySeat({required this.seatNumber, super.key, this.onTap});
  final int seatNumber;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isSelectable = onTap != null;

    return SizedBox(
      width: 120,
      child: GestureDetector(
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
              color: isSelectable ? PokerTheme.goldAccent : Colors.white24,
              width: isSelectable ? 2 : 1,
            ),
            boxShadow: isSelectable
                ? [
                    BoxShadow(
                      color: PokerTheme.goldAccent.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelectable
                    ? Icons.add_circle_outline
                    : Icons.person_add_outlined,
                color: isSelectable ? PokerTheme.goldAccent : Colors.white38,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                isSelectable ? 'Sit Here' : 'Seat $seatNumber',
                style: TextStyle(
                  color: isSelectable ? PokerTheme.goldAccent : Colors.white38,
                  fontSize: 12,
                  fontWeight: isSelectable
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
