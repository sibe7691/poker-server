import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:poker_app/core/constants.dart';
import 'package:poker_app/core/theme.dart';
import 'package:poker_app/core/utils.dart';
import 'package:poker_app/models/models.dart';
import 'package:poker_app/widgets/widgets.dart';

/// The visual poker table with player seats arranged in an oval
class PokerTable extends StatelessWidget {
  const PokerTable({
    required this.gameState,
    required this.onAction,
    super.key,
    this.onSeatSelected,
  });
  final GameState gameState;
  final void Function(PlayerAction action, {int? amount}) onAction;
  final void Function(int seatIndex)? onSeatSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth * 0.85;
        final tableHeight = constraints.maxHeight * 0.5;

        return Stack(
          children: [
            // Centered content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Table surface
                  _buildTableSurface(tableWidth, tableHeight),
                ],
              ),
            ),
            // Player seats around the table
            ..._buildPlayerSeats(context, constraints),
            // Dealer button on the table
            _buildDealerButton(constraints),
            // Bet chips on the table (rendered on top of table surface)
            ..._buildBetChips(constraints),
          ],
        );
      },
    );
  }

  Widget _buildTableSurface(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            PokerTheme.tableFelt.withValues(alpha: 0.9),
            PokerTheme.tableGreen,
          ],
        ),
        borderRadius: BorderRadius.all(
          Radius.elliptical(width / 2, height / 2),
        ),
        border: Border.all(color: const Color(0xFF5D4037), width: 12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Inner border
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(
                Radius.elliptical((width - 16) / 2, (height - 16) / 2),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 2,
              ),
            ),
          ),
          // Center content
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pot display (only during active game)
              if (gameState.pot > 0 && gameState.isInProgress)
                PotDisplay(pot: gameState.pot),
              if (gameState.isInProgress) const SizedBox(height: 16),
              // Community cards (only during active game)
              if (gameState.isInProgress)
                CommunityCards(cards: gameState.communityCards)
              else
                _buildWaitingMessage(),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPlayerSeats(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final seats = <Widget>[];
    final centerX = constraints.maxWidth / 2;
    final centerY = constraints.maxHeight / 2;

    // Oval dimensions for seat placement
    final radiusX = constraints.maxWidth * 0.42;
    final radiusY = constraints.maxHeight * 0.38;

    // Use the table's configured max players
    final maxSeats = gameState.maxPlayers;

    // Create a map of seat number to player
    final seatMap = <int, Player>{};
    for (final player in gameState.players) {
      seatMap[player.seat] = player;
    }

    for (var i = 0; i < maxSeats; i++) {
      // Calculate visual position around the oval
      // Start from bottom center and go counter-clockwise
      // Use consistent positions regardless of whether player is seated
      // or spectating
      // This prevents seats from jumping when sitting down or standing up
      final angle = (math.pi / 2) + (2 * math.pi * i / maxSeats);
      final x = centerX + radiusX * math.cos(angle);
      final y = centerY + radiusY * math.sin(angle);

      final player = seatMap[i];

      // Clamp position to keep widget within bounds
      const widgetWidth = 120.0;
      // Cards (84 for current player, 49 for others) + spacing (4) + info (~50)
      const widgetHeight = 115.0;
      final clampedX = (x - widgetWidth / 2).clamp(
        0.0,
        constraints.maxWidth - widgetWidth,
      );
      final clampedY = (y - widgetHeight / 2).clamp(
        0.0,
        constraints.maxHeight - widgetHeight,
      );

      seats.add(
        Positioned(
          left: clampedX,
          top: clampedY,
          child: player != null
              ? PlayerSeat(
                  player: player,
                  isCurrentTurn: gameState.currentPlayerId == player.userId,
                  isSmallBlind: _isSmallBlind(i),
                  isBigBlind: _isBigBlind(i),
                  gamePhase: gameState.phase,
                )
              : EmptySeat(
                  seatNumber: i + 1,
                  onTap: onSeatSelected != null
                      ? () => onSeatSelected!(i)
                      : null,
                ),
        ),
      );
    }

    return seats;
  }

  /// Build the dealer button positioned on the table, in front of the dealer
  Widget _buildDealerButton(BoxConstraints constraints) {
    final centerX = constraints.maxWidth / 2;
    final centerY = constraints.maxHeight / 2;

    // Position dealer button at same radius as bet chips
    final dealerRadiusX = constraints.maxWidth * 0.28;
    final dealerRadiusY = constraints.maxHeight * 0.24;

    final maxSeats = gameState.maxPlayers;
    final dealerSeat = gameState.dealerSeat;

    // Check if there's a player at the dealer seat
    final hasDealer = gameState.players.any((p) => p.seat == dealerSeat);
    if (!hasDealer) {
      return const SizedBox.shrink();
    }

    // Calculate dealer button position with perpendicular offset to avoid
    // overlap with bet chips
    final angle = (math.pi / 2) + (2 * math.pi * dealerSeat / maxSeats);
    final baseX = centerX + dealerRadiusX * math.cos(angle);
    final baseY = centerY + dealerRadiusY * math.sin(angle);

    // Offset perpendicular to the radial direction (to the right when looking
    // from center)
    final perpAngle = angle + math.pi / 2;
    const offsetDistance = 35.0;
    final buttonX = baseX + offsetDistance * math.cos(perpAngle);
    final buttonY = baseY + offsetDistance * math.sin(perpAngle);

    const buttonSize = 28.0;

    return Positioned(
      left: buttonX - buttonSize / 2,
      top: buttonY - buttonSize / 2,
      child: const _DealerButton(),
    );
  }

  /// Build bet chips positioned on the table, between players and the center
  List<Widget> _buildBetChips(BoxConstraints constraints) {
    final betChips = <Widget>[];
    final centerX = constraints.maxWidth / 2;
    final centerY = constraints.maxHeight / 2;

    // Use a smaller radius for bet placement (closer to center than seats)
    final betRadiusX = constraints.maxWidth * 0.28;
    final betRadiusY = constraints.maxHeight * 0.24;

    final maxSeats = gameState.maxPlayers;

    // Create a map of seat number to player
    final seatMap = <int, Player>{};
    for (final player in gameState.players) {
      seatMap[player.seat] = player;
    }

    for (var i = 0; i < maxSeats; i++) {
      final player = seatMap[i];
      if (player == null || player.currentBet <= 0) continue;

      // Calculate bet position - same angle as seat but closer to center
      final angle = (math.pi / 2) + (2 * math.pi * i / maxSeats);
      final betX = centerX + betRadiusX * math.cos(angle);
      final betY = centerY + betRadiusY * math.sin(angle);

      // Center the bet chip widget
      const chipWidth = 60.0;
      const chipHeight = 28.0;

      betChips.add(
        Positioned(
          left: betX - chipWidth / 2,
          top: betY - chipHeight / 2,
          child: _BetChip(amount: player.currentBet),
        ),
      );
    }

    return betChips;
  }

  bool _isSmallBlind(int seat) {
    if (gameState.players.length < 2) return false;
    final maxSeats = gameState.maxPlayers;
    final sbSeat = (gameState.dealerSeat + 1) % maxSeats;
    // Handle heads-up where dealer is SB
    if (gameState.players.length == 2) {
      return seat == gameState.dealerSeat;
    }
    return seat == sbSeat;
  }

  bool _isBigBlind(int seat) {
    if (gameState.players.length < 2) return false;
    final maxSeats = gameState.maxPlayers;
    final bbSeat = (gameState.dealerSeat + 2) % maxSeats;
    // Handle heads-up where non-dealer is BB
    if (gameState.players.length == 2) {
      return seat != gameState.dealerSeat;
    }
    return seat == bbSeat;
  }

  Widget _buildWaitingMessage() {
    // Count players with chips who can play
    final playersWithChips = gameState.players.where((p) => p.chips > 0).length;
    const minPlayers = 2;

    String message;
    if (playersWithChips < minPlayers) {
      final needed = minPlayers - playersWithChips;
      message =
          'Waiting for $needed more player${needed > 1 ? 's' : ''} with chips';
    } else {
      message = 'Waiting for next hand';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Dealer button widget that displays on the table
class _DealerButton extends StatelessWidget {
  const _DealerButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5F5F5), Color(0xFFE0E0E0)],
        ),
        border: Border.all(color: const Color(0xFF424242), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'D',
          style: TextStyle(
            color: Color(0xFF212121),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// Bet chip widget that displays on the table
class _BetChip extends StatelessWidget {
  const _BetChip({required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: PokerTheme.surfaceDark.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PokerTheme.goldAccent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Small chip icon
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  PokerTheme.goldAccent,
                  PokerTheme.goldAccent.withValues(alpha: 0.7),
                ],
              ),
              border: Border.all(color: Colors.white54),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            formatChips(amount),
            style: const TextStyle(
              color: PokerTheme.goldAccent,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    ).animate().scale(duration: 200.ms, curve: Curves.easeOut);
  }
}
