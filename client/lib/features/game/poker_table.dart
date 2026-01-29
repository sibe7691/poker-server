import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poker_app/core/constants.dart';
import 'package:poker_app/core/theme.dart';
import 'package:poker_app/core/utils.dart';
import 'package:poker_app/models/models.dart';
import 'package:poker_app/providers/game_provider.dart';
import 'package:poker_app/services/websocket_service.dart';
import 'package:poker_app/widgets/widgets.dart';

/// Data class to track a player's recent action
class _PlayerActionData {
  _PlayerActionData({required this.action});
  final PlayerAction action;
}

/// Data class to track a player's winner status
class _PlayerWinnerData {
  _PlayerWinnerData({required this.amount, this.handName});
  final int amount;
  final String? handName;
}

/// Data class to track a player's chat bubble
class _PlayerChatData {
  _PlayerChatData({required this.message, required this.timestamp});
  final String message;
  final DateTime timestamp;
}

/// The visual poker table with player seats arranged in an oval
class PokerTable extends ConsumerStatefulWidget {
  const PokerTable({
    required this.gameState,
    required this.onAction,
    super.key,
    this.onSeatSelected,
    this.handResult,
    this.chatMessages = const [],
  });
  final GameState gameState;
  final void Function(PlayerAction action, {int? amount}) onAction;
  final void Function(int seatIndex)? onSeatSelected;
  final HandResult? handResult;

  /// Chat messages to display as bubbles above players
  final List<ChatMessage> chatMessages;

  @override
  ConsumerState<PokerTable> createState() => _PokerTableState();
}

class _PokerTableState extends ConsumerState<PokerTable> {
  /// Track recent actions by player userId
  final Map<String, _PlayerActionData> _playerActions = {};

  /// Track winners by player odId (user_id)
  final Map<String, _PlayerWinnerData> _playerWinners = {};

  /// Track chat bubbles by player username
  final Map<String, _PlayerChatData> _playerChats = {};

  /// Track last hand number to clear actions on new hand
  int _lastHandNumber = 0;

  /// Track last processed hand result to avoid duplicate processing
  HandResult? _lastHandResult;

  /// Track community cards from last hand result for display during showdown
  List<PlayingCard> _handResultCommunityCards = [];

  /// Track the number of processed chat messages to detect new ones
  int _lastChatCount = 0;

  /// Get the rotation offset to position the current user at the bottom
  /// Returns the angle offset in radians
  double get _rotationOffset {
    final me = widget.gameState.me;
    if (me == null) return 0;
    final maxSeats = widget.gameState.maxPlayers;
    // Calculate how much to rotate so the user's seat is at the bottom
    return 2 * math.pi * me.seat / maxSeats;
  }

  @override
  Widget build(BuildContext context) {
    // Listen for player action events
    ref.listen<AsyncValue<PlayerActionEvent>>(
      playerActionProvider,
      (previous, next) {
        next.whenData((event) {
          setState(() {
            _playerActions[event.userId] = _PlayerActionData(
              action: PlayerAction.fromString(event.action),
            );
          });
        });
      },
    );

    // Clear actions and winners when a new hand starts
    if (widget.gameState.handNumber != _lastHandNumber) {
      _lastHandNumber = widget.gameState.handNumber;
      _playerActions.clear();
      _playerWinners.clear();
      _lastHandResult = null;
      _handResultCommunityCards = [];
    }

    // Process new chat messages
    if (widget.chatMessages.length > _lastChatCount) {
      // Process only new messages
      for (var i = _lastChatCount; i < widget.chatMessages.length; i++) {
        final chatMsg = widget.chatMessages[i];
        // Use username as key since server doesn't send user_id with chat
        _playerChats[chatMsg.username] = _PlayerChatData(
          message: chatMsg.message,
          timestamp: chatMsg.timestamp,
        );
      }
      _lastChatCount = widget.chatMessages.length;
    }

    // Process new hand result if provided
    if (widget.handResult != null && widget.handResult != _lastHandResult) {
      _lastHandResult = widget.handResult;
      _playerWinners.clear();
      for (final winner in widget.handResult!.winners) {
        _playerWinners[winner.odId] = _PlayerWinnerData(
          amount: winner.amount,
          handName: winner.handName,
        );
      }
      // Store community cards from hand result for display
      _handResultCommunityCards = widget.handResult!.communityCards;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth * 0.70;
        final tableHeight = constraints.maxHeight * 0.40;

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
        border: Border.all(color: const Color(0xFF5D4037), width: 8),
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
              // Pot display (during active game or
              // when showing hand result)
              if (widget.gameState.pot > 0 && widget.gameState.isInProgress)
                PotDisplay(pot: widget.gameState.pot)
              else if (_playerWinners.isNotEmpty && widget.handResult != null)
                PotDisplay(pot: widget.handResult!.pot),
              if (widget.gameState.isInProgress ||
                  _handResultCommunityCards.isNotEmpty)
                const SizedBox(height: 16),
              // Community cards (during active game or
              // when showing hand result)
              if (widget.gameState.isInProgress)
                CommunityCards(cards: widget.gameState.communityCards)
              else if (_handResultCommunityCards.isNotEmpty)
                // Show community cards from hand result
                // when winner is displayed
                CommunityCards(cards: _handResultCommunityCards)
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

    // Oval dimensions for seat placement (reduced for better fit)
    final radiusX = constraints.maxWidth * 0.35;
    final radiusY = constraints.maxHeight * 0.30;

    // Use the table's configured max players
    final maxSeats = widget.gameState.maxPlayers;

    // Create a map of seat number to player
    final seatMap = <int, Player>{};
    for (final player in widget.gameState.players) {
      seatMap[player.seat] = player;
    }

    for (var i = 0; i < maxSeats; i++) {
      // Calculate visual position around the oval
      // Start from bottom center and go counter-clockwise
      // Apply rotation offset so the current user is always at the bottom
      final angle =
          (math.pi / 2) + (2 * math.pi * i / maxSeats) - _rotationOffset;
      final x = centerX + radiusX * math.cos(angle);
      final y = centerY + radiusY * math.sin(angle);

      final player = seatMap[i];

      // Clamp position to keep widget within bounds
      const widgetWidth = 100.0;
      // Cards (smaller: 70 for current player, 42 for others) + spacing (3) + info (~35) + timer bar (6)
      const widgetHeight = 95.0;
      final clampedX = (x - widgetWidth / 2).clamp(
        0.0,
        constraints.maxWidth - widgetWidth,
      );
      final clampedY = (y - widgetHeight / 2).clamp(
        0.0,
        constraints.maxHeight - widgetHeight,
      );

      // Get the player's recent action if any
      final actionData = player != null ? _playerActions[player.userId] : null;

      // Get the player's winner info if any
      final winnerData = player != null ? _playerWinners[player.userId] : null;

      // Get the player's chat bubble if any (keyed by username)
      final chatData = player != null ? _playerChats[player.username] : null;

      // Get showdown cards from hand result if available
      final showdownCards = player != null && _lastHandResult != null
          ? _lastHandResult!.shownHands[player.userId]
          : null;

      // Skip empty seats when player is seated (onSeatSelected is null)
      // Only show empty seats when spectating so user can choose a seat
      if (player == null && widget.onSeatSelected == null) {
        continue;
      }

      seats.add(
        Positioned(
          left: clampedX,
          top: clampedY,
          child: player != null
              ? PlayerSeat(
                  player: player,
                  isCurrentTurn:
                      widget.gameState.currentPlayerId == player.userId,
                  isSmallBlind: _isSmallBlind(i),
                  isBigBlind: _isBigBlind(i),
                  gamePhase: widget.gameState.phase,
                  lastAction: actionData?.action,
                  winnerInfo: winnerData != null
                      ? WinnerDisplayInfo(
                          amount: winnerData.amount,
                          handName: winnerData.handName,
                        )
                      : null,
                  chatBubble: chatData != null
                      ? ChatBubbleInfo(
                          message: chatData.message,
                          timestamp: chatData.timestamp,
                        )
                      : null,
                  showdownCards: showdownCards,
                  // Timer props - only pass if it's the current player's turn
                  timeRemaining:
                      widget.gameState.currentPlayerId == player.userId
                      ? widget.gameState.timeRemaining
                      : null,
                  turnTimeSeconds: widget.gameState.turnTimeSeconds,
                  usingTimeBank: widget.gameState.usingTimeBank,
                  timeBank: player.timeBank,
                )
              : EmptySeat(
                  seatNumber: i + 1,
                  onTap: () => widget.onSeatSelected!(i),
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

    // Position dealer button on the table, same radius as bet chips
    final dealerRadiusX = constraints.maxWidth * 0.23;
    final dealerRadiusY = constraints.maxHeight * 0.15;

    final maxSeats = widget.gameState.maxPlayers;
    final dealerSeat = widget.gameState.dealerSeat;

    // Check if there's a player at the dealer seat
    final hasDealer = widget.gameState.players.any((p) => p.seat == dealerSeat);
    if (!hasDealer) {
      return const SizedBox.shrink();
    }

    // Calculate dealer button position with perpendicular offset to avoid
    // overlap with bet chips
    // Apply rotation offset so positions match the rotated seat positions
    final angle =
        (math.pi / 2) + (2 * math.pi * dealerSeat / maxSeats) - _rotationOffset;
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

    // Position bets ON the table surface (inside the table ellipse)
    // Table extends to 0.35 X and 0.20 Y from center, so keep bets inside
    // but outside the community cards area in the center
    final betRadiusX = constraints.maxWidth * 0.23;
    final betRadiusY = constraints.maxHeight * 0.15;

    final maxSeats = widget.gameState.maxPlayers;

    // Create a map of seat number to player
    final seatMap = <int, Player>{};
    for (final player in widget.gameState.players) {
      seatMap[player.seat] = player;
    }

    for (var i = 0; i < maxSeats; i++) {
      final player = seatMap[i];
      if (player == null || player.currentBet <= 0) continue;

      // Calculate bet position - same angle as seat but closer to center
      // Apply rotation offset so positions match the rotated seat positions
      final angle =
          (math.pi / 2) + (2 * math.pi * i / maxSeats) - _rotationOffset;
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
    if (widget.gameState.players.length < 2) return false;
    final maxSeats = widget.gameState.maxPlayers;
    final sbSeat = (widget.gameState.dealerSeat + 1) % maxSeats;
    // Handle heads-up where dealer is SB
    if (widget.gameState.players.length == 2) {
      return seat == widget.gameState.dealerSeat;
    }
    return seat == sbSeat;
  }

  bool _isBigBlind(int seat) {
    if (widget.gameState.players.length < 2) return false;
    final maxSeats = widget.gameState.maxPlayers;
    final bbSeat = (widget.gameState.dealerSeat + 2) % maxSeats;
    // Handle heads-up where non-dealer is BB
    if (widget.gameState.players.length == 2) {
      return seat != widget.gameState.dealerSeat;
    }
    return seat == bbSeat;
  }

  Widget _buildWaitingMessage() {
    // Count players with chips who can play
    final playersWithChips = widget.gameState.players
        .where((p) => p.chips > 0)
        .length;
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
