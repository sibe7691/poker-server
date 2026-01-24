import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/widgets.dart';

/// The visual poker table with player seats arranged in an oval
class PokerTable extends StatelessWidget {
  final GameState gameState;
  final Function(PlayerAction action, {int? amount}) onAction;
  final Function(int seatIndex)? onSeatSelected;
  final Function(int seatIndex)? onChangeSeat;

  const PokerTable({
    super.key,
    required this.gameState,
    required this.onAction,
    this.onSeatSelected,
    this.onChangeSeat,
  });

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
        border: Border.all(
          color: const Color(0xFF5D4037),
          width: 12,
        ),
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
              // Pot display
              if (gameState.pot > 0)
                PotDisplay(pot: gameState.pot),
              const SizedBox(height: 16),
              // Community cards
              CommunityCards(cards: gameState.communityCards),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPlayerSeats(BuildContext context, BoxConstraints constraints) {
    final List<Widget> seats = [];
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

    for (int i = 0; i < maxSeats; i++) {
      // Calculate position around the oval
      // Start from bottom center and go clockwise
      final angle = (math.pi / 2) + (2 * math.pi * i / maxSeats);
      final x = centerX + radiusX * math.cos(angle);
      final y = centerY + radiusY * math.sin(angle);

      final player = seatMap[i];
      
      final isSeated = gameState.me != null;
      final canChangeSeat = isSeated && onChangeSeat != null && !gameState.isInProgress;
      
      seats.add(
        Positioned(
          left: x - 60, // Center the widget (approximately 120px wide)
          top: y - 50,  // Center the widget (approximately 100px tall)
          child: player != null
              ? PlayerSeat(
                  player: player,
                  seatNumber: i + 1,
                  isDealer: gameState.dealerSeat == i,
                  isCurrentTurn: gameState.currentPlayerId == player.userId,
                  isSmallBlind: _isSmallBlind(i),
                  isBigBlind: _isBigBlind(i),
                )
              : EmptySeat(
                  seatNumber: i + 1,
                  onTap: onSeatSelected != null 
                      ? () => onSeatSelected!(i) 
                      : (canChangeSeat ? () => onChangeSeat!(i) : null),
                  isChangeSeat: canChangeSeat && onSeatSelected == null,
                ),
        ),
      );
    }

    return seats;
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
}
