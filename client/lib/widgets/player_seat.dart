import 'package:flutter/material.dart';
import 'package:poker_app/core/constants.dart';
import 'package:poker_app/core/theme.dart';
import 'package:poker_app/core/utils.dart';
import 'package:poker_app/models/card.dart';
import 'package:poker_app/models/player.dart';
import 'package:poker_app/widgets/playing_card.dart';

/// Data class to hold winner display info
class WinnerDisplayInfo {
  const WinnerDisplayInfo({
    required this.amount,
    this.handName,
  });
  final int amount;
  final String? handName;
}

/// A player seat widget showing player info, chips, and cards
class PlayerSeat extends StatefulWidget {
  const PlayerSeat({
    required this.player,
    super.key,
    this.isCurrentTurn = false,
    this.isSmallBlind = false,
    this.isBigBlind = false,
    this.lastAction,
    this.winnerInfo,
    this.gamePhase = GamePhase.waiting,
    this.showdownCards,
  });
  final Player player;
  final bool isCurrentTurn;
  final bool isSmallBlind;
  final bool isBigBlind;
  final PlayerAction? lastAction;
  final WinnerDisplayInfo? winnerInfo;
  final GamePhase gamePhase;
  /// Cards revealed during showdown (from hand result)
  final List<PlayingCard>? showdownCards;

  @override
  State<PlayerSeat> createState() => _PlayerSeatState();
}

class _PlayerSeatState extends State<PlayerSeat> with TickerProviderStateMixin {
  late AnimationController _actionAnimationController;
  late Animation<double> _actionFadeAnimation;
  late AnimationController _winnerAnimationController;
  late Animation<double> _winnerFadeAnimation;
  PlayerAction? _displayedAction;
  WinnerDisplayInfo? _displayedWinner;

  /// Whether the player is out of chips and waiting for a rebuy
  bool get _isOutOfChips => widget.player.chips == 0 && !widget.player.isAllIn;

  @override
  void initState() {
    super.initState();
    // Action animation controller
    _actionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _actionFadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _actionAnimationController,
        curve: Curves.easeOut,
      ),
    );

    // Winner animation controller (longer display time)
    _winnerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _winnerFadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _winnerAnimationController,
        curve: Curves.easeOut,
      ),
    );

    // Show action if already set
    if (widget.lastAction != null) {
      _showAction(widget.lastAction!);
    }

    // Show winner if already set
    if (widget.winnerInfo != null) {
      _showWinner(widget.winnerInfo!);
    }
  }

  @override
  void didUpdateWidget(PlayerSeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Show new action when it changes
    if (widget.lastAction != null &&
        widget.lastAction != oldWidget.lastAction) {
      _showAction(widget.lastAction!);
    }
    // Show winner when it changes
    if (widget.winnerInfo != null &&
        widget.winnerInfo != oldWidget.winnerInfo) {
      _showWinner(widget.winnerInfo!);
    }
  }

  void _showAction(PlayerAction action) {
    setState(() {
      _displayedAction = action;
    });
    _actionAnimationController.forward(from: 0).then((_) {
      // Hold for a moment, then fade out
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          _actionAnimationController.reverse().then((_) {
            if (mounted) {
              setState(() {
                _displayedAction = null;
              });
            }
          });
        }
      });
    });
  }

  void _showWinner(WinnerDisplayInfo winnerInfo) {
    setState(() {
      _displayedWinner = winnerInfo;
    });
    _winnerAnimationController.forward(from: 0).then((_) {
      // Hold for longer (3 seconds), then fade out
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (mounted) {
          _winnerAnimationController.reverse().then((_) {
            if (mounted) {
              setState(() {
                _displayedWinner = null;
              });
            }
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _actionAnimationController.dispose();
    _winnerAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only show cards during active game phases, not when waiting
    final isGameActive = widget.gamePhase != GamePhase.waiting;
    // Check if we have showdown cards to display (revealed during showdown)
    final hasShowdownCards =
        widget.showdownCards != null && widget.showdownCards!.isNotEmpty;
    final shouldShowCards =
        (isGameActive || hasShowdownCards) &&
        (widget.player.holeCards.isNotEmpty ||
            widget.player.hasCards ||
            hasShowdownCards) &&
        !_isOutOfChips;

    return Opacity(
      opacity: _isOutOfChips ? 0.5 : 1.0,
      child: SizedBox(
        width: 120,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cards (only if player has cards and game is active)
            // Show face-up cards if not folded OR if we have showdown cards
            if (shouldShowCards &&
                (!widget.player.isFolded || hasShowdownCards))
              _buildCards()
            else if (shouldShowCards && widget.player.isFolded)
              _buildFoldedCards(),
            if (shouldShowCards) const SizedBox(height: 4),
            // Player info container with action label overlay
            _buildPlayerInfoWithActionOverlay(context),
            // Note: Bet chips are now rendered separately in PokerTable
            // to position them on the table surface
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerInfoWithActionOverlay(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Player info container (base layer)
        _buildPlayerInfo(context),
        // Winner label overlay (higher priority than action)
        if (_displayedWinner != null)
          _buildWinnerLabel()
        // Action label overlay (top layer)
        else if (_displayedAction != null)
          _buildActionLabel(),
      ],
    );
  }

  Widget _buildActionLabel() {
    final (label, color) = _getActionDisplay(_displayedAction!);

    return FadeTransition(
      opacity: _actionFadeAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.6),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildWinnerLabel() {
    return FadeTransition(
      opacity: _winnerFadeAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              PokerTheme.goldAccent,
              Color(0xFFD4A574),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: PokerTheme.goldAccent.withValues(alpha: 0.6),
              blurRadius: 12,
              spreadRadius: 3,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'WINNER',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            Text(
              '+${formatChips(_displayedWinner!.amount)}',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, Color) _getActionDisplay(PlayerAction action) {
    return switch (action) {
      PlayerAction.fold => ('FOLD', Colors.grey.shade600),
      PlayerAction.check => ('CHECK', PokerTheme.chipBlue),
      PlayerAction.call => ('CALL', PokerTheme.tableGreen),
      PlayerAction.bet => ('BET', PokerTheme.goldAccent),
      PlayerAction.raise => ('RAISE', PokerTheme.chipRed),
      PlayerAction.allIn => ('ALL IN', PokerTheme.chipRed),
    };
  }

  Widget _buildFoldedCards() {
    return const Opacity(
      opacity: 0.3,
      child: HoleCards(cards: [], isHidden: true, isSmall: true),
    );
  }

  Widget _buildCards() {
    // During showdown, use showdown cards if available (revealed hands)
    final cardsToShow = widget.showdownCards ?? widget.player.holeCards;
    final hasShowdownCards =
        widget.showdownCards != null && widget.showdownCards!.isNotEmpty;

    return HoleCards(
      cards: cardsToShow,
      // Show cards face-up if: it's the current player, OR we have showdown
      // cards. Hidden only if empty AND not yours AND no showdown cards.
      isHidden:
          cardsToShow.isEmpty && !widget.player.isYou && !hasShowdownCards,
      isSmall: !widget.player.isYou,
    );
  }

  Widget _buildPlayerInfo(BuildContext context) {
    // Determine gradient colors based on player state
    List<Color> gradientColors;
    if (_isOutOfChips) {
      gradientColors = [Colors.grey.shade700, Colors.grey.shade800];
    } else if (widget.player.isFolded) {
      gradientColors = [Colors.grey.shade800, Colors.grey.shade900];
    } else if (widget.isCurrentTurn) {
      gradientColors = [
        PokerTheme.goldAccent.withValues(alpha: 0.3),
        PokerTheme.surfaceLight,
      ];
    } else if (widget.player.isYou) {
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
          color: widget.isCurrentTurn
              ? PokerTheme.goldAccent
              : widget.player.isYou
              ? PokerTheme.tableFelt
              : Colors.transparent,
          width: widget.isCurrentTurn ? 2 : 1,
        ),
        boxShadow: widget.isCurrentTurn
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
              if (widget.isSmallBlind) _buildBadge('SB', PokerTheme.chipBlue),
              if (widget.isBigBlind) _buildBadge('BB', PokerTheme.chipRed),
              if (widget.isSmallBlind || widget.isBigBlind)
                const SizedBox(width: 4),
              Flexible(
                child: Text(
                  widget.player.username,
                  style: TextStyle(
                    color: widget.player.isFolded ? Colors.grey : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (!widget.player.isConnected)
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
                  color: widget.player.isAllIn
                      ? PokerTheme.chipRed
                      : PokerTheme.goldAccent,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.player.isAllIn
                      ? 'ALL IN'
                      : formatChips(widget.player.chips),
                  style: TextStyle(
                    color: widget.player.isAllIn
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
