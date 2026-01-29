import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:poker_app/core/constants.dart';
import 'package:poker_app/core/theme.dart';
import 'package:poker_app/core/utils.dart';
import 'package:poker_app/widgets/turn_timer.dart';

// Fire-and-forget futures are intentional for haptic feedback
// ignore_for_file: discarded_futures

/// Action buttons panel for player actions
class ActionButtonsPanel extends StatefulWidget {
  const ActionButtonsPanel({
    required this.validActions,
    required this.callAmount,
    required this.minRaise,
    required this.maxBet,
    required this.pot,
    required this.onAction,
    this.timeRemaining,
    this.turnTimeSeconds = 30,
    this.usingTimeBank = false,
    this.timeBank = 0,
    super.key,
  });
  final List<PlayerAction> validActions;
  final int callAmount;
  final int minRaise;
  final int maxBet;
  final int pot;
  final void Function(PlayerAction action, {int? amount}) onAction;
  final double? timeRemaining;
  final int turnTimeSeconds;
  final bool usingTimeBank;
  final double timeBank;

  @override
  State<ActionButtonsPanel> createState() => _ActionButtonsPanelState();
}

class _ActionButtonsPanelState extends State<ActionButtonsPanel> {
  final _debouncer = Debouncer();
  double _currentBetSliderValue = 0; // 0.0 to 1.0

  @override
  void initState() {
    super.initState();
    // Initialize slider to minimum raise value
    _currentBetSliderValue = 0.0;
  }

  @override
  void didUpdateWidget(ActionButtonsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset slider if min/max changed significantly
    if (oldWidget.minRaise != widget.minRaise ||
        oldWidget.maxBet != widget.maxBet) {
      // Keep slider at same relative position, but clamp to valid range
      _currentBetSliderValue = _currentBetSliderValue.clamp(0.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRaiseOrBet =
        widget.validActions.contains(PlayerAction.raise) ||
        widget.validActions.contains(PlayerAction.bet);

    // Calculate width as 25% of screen width, with minimum constraint
    final screenWidth = MediaQuery.of(context).size.width;
    final targetWidth = screenWidth * 0.25;
    const minWidth = 320.0; // Minimum width to prevent it from being too small
    const maxWidth = 450.0; // Maximum width to prevent it from being too large
    final panelWidth = targetWidth.clamp(minWidth, maxWidth);

    return Container(
      width: panelWidth,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PokerTheme.surfaceDark.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 10,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bet amount controls (only show if can raise/bet)
            if (canRaiseOrBet) ...[
              _buildBetAmountControls(),
              const SizedBox(height: 16),
            ],
            // Action buttons row
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  /// Whether this is a raise (someone has bet) vs a bet (first to act)
  bool get _isRaise => widget.validActions.contains(PlayerAction.raise);

  /// Get current bet amount from slider value
  int get _currentBetAmount {
    if (widget.minRaise >= widget.maxBet) return widget.maxBet;
    final range = widget.maxBet - widget.minRaise;
    final amount = widget.minRaise + (_currentBetSliderValue * range).round();
    return amount.clamp(widget.minRaise, widget.maxBet);
  }

  /// Calculate raise amount for a given pot percentage
  int _calculateRaiseAmount(double percentage) {
    // Total pot for calculation:
    // - For a bet (first to act): just the pot
    // - For a raise (someone has bet): pot + the bet we need to call
    final totalPot = _isRaise ? widget.pot + widget.callAmount : widget.pot;
    // Raise amount = total pot × percentage
    final raiseAmount = (totalPot * percentage).round();
    // Clamp between min raise and max bet (all-in)
    return raiseAmount.clamp(widget.minRaise, widget.maxBet);
  }

  Widget _buildBetAmountControls() {
    return Column(
      children: [
        // Preset bet buttons row
        Row(
          children: [
            Expanded(
              child: _PresetBetButton(
                label: 'MIN',
                onPressed: () {
                  setState(() => _currentBetSliderValue = 0.0);
                  HapticFeedback.lightImpact();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PresetBetButton(
                label: '3/4',
                onPressed: () {
                  final amount = _calculateRaiseAmount(0.75);
                  final normalized = widget.maxBet > widget.minRaise
                      ? (amount - widget.minRaise) /
                            (widget.maxBet - widget.minRaise)
                      : 0.0;
                  setState(
                    () => _currentBetSliderValue = normalized.clamp(0.0, 1.0),
                  );
                  HapticFeedback.lightImpact();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PresetBetButton(
                label: 'POT',
                onPressed: () {
                  final amount = _calculateRaiseAmount(1);
                  final normalized = widget.maxBet > widget.minRaise
                      ? (amount - widget.minRaise) /
                            (widget.maxBet - widget.minRaise)
                      : 0.0;
                  setState(
                    () => _currentBetSliderValue = normalized.clamp(0.0, 1.0),
                  );
                  HapticFeedback.lightImpact();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PresetBetButton(
                label: 'MAX',
                onPressed: () {
                  setState(() => _currentBetSliderValue = 1.0);
                  HapticFeedback.lightImpact();
                },
              ),
            ),
            const SizedBox(width: 8),
            // Bet amount display
            Container(
              width: 80,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                color: PokerTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatChips(_currentBetAmount),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    height: 1,
                    color: Colors.white30,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF00BCD4), // Bright cyan
            inactiveTrackColor: PokerTheme.surfaceLight,
            thumbColor: const Color(0xFF00BCD4),
            overlayColor: const Color(0xFF00BCD4).withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            trackHeight: 4,
          ),
          child: Slider(
            value: _currentBetSliderValue,
            onChanged: (value) {
              setState(() {
                _currentBetSliderValue = value;
              });
              HapticFeedback.selectionClick();
            },
          ),
        ),
      ],
    );
  }

  /// Check if slider is at max position (all-in)
  bool get _isAllIn => _currentBetSliderValue >= 0.99;

  Widget _buildActionButtons() {
    final canRaiseOrBet =
        widget.validActions.contains(PlayerAction.raise) ||
        widget.validActions.contains(PlayerAction.bet);
    final raiseAmount = canRaiseOrBet ? _currentBetAmount : 0;

    // Determine raise button label - show "All In" when at max
    String raiseLabel;
    if (_isAllIn) {
      raiseLabel = 'All In';
    } else if (_isRaise) {
      raiseLabel = 'Raise';
    } else {
      raiseLabel = 'Bet';
    }

    return Row(
      children: [
        // Fold button
        if (widget.validActions.contains(PlayerAction.fold))
          Expanded(
            child: _ActionButton(
              label: 'Fold',
              color: const Color(0xFFFF6B9D), // Reddish-pink
              textColor: Colors.black,
              onPressed: () {
                if (_debouncer.call()) {
                  HapticFeedback.mediumImpact();
                  widget.onAction(PlayerAction.fold);
                }
              },
            ),
          ),
        if (widget.validActions.contains(PlayerAction.fold))
          const SizedBox(width: 8),
        // Check button
        if (widget.validActions.contains(PlayerAction.check))
          Expanded(
            child: _ActionButton(
              label: 'Check',
              color: const Color(0xFF3A4A5C), // Dark grayish-blue
              onPressed: () {
                if (_debouncer.call()) {
                  HapticFeedback.mediumImpact();
                  widget.onAction(PlayerAction.check);
                }
              },
            ),
          ),
        // Call button
        if (widget.validActions.contains(PlayerAction.call))
          Expanded(
            child: _ActionButton(
              label: 'Call',
              amount: widget.callAmount,
              color: const Color(0xFF3A4A5C), // Dark grayish-blue
              onPressed: () {
                if (_debouncer.call()) {
                  HapticFeedback.mediumImpact();
                  widget.onAction(PlayerAction.call);
                }
              },
            ),
          ),
        if (widget.validActions.contains(PlayerAction.call))
          const SizedBox(width: 8),
        // Raise/Bet button (becomes "All In" when at max)
        if (canRaiseOrBet)
          Expanded(
            child: _ActionButton(
              label: raiseLabel,
              amount: raiseAmount,
              color: _isAllIn
                  ? PokerTheme
                        .chipRed // Red for all-in
                  : const Color(0xFF00BCD4), // Bright cyan for raise
              textColor: _isAllIn ? Colors.white : Colors.black,
              onPressed: () {
                if (_debouncer.call()) {
                  if (_isAllIn) {
                    HapticFeedback.heavyImpact();
                    widget.onAction(PlayerAction.allIn);
                  } else {
                    HapticFeedback.mediumImpact();
                    final action = _isRaise
                        ? PlayerAction.raise
                        : PlayerAction.bet;
                    widget.onAction(action, amount: raiseAmount);
                  }
                }
              },
            ),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.textColor = Colors.white,
    this.amount,
  });
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;
  final int? amount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60, // Fixed height for consistent button sizing
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
            // Always reserve space for amount line to maintain consistent height
            const SizedBox(height: 2),
            Text(
              amount != null ? formatChips(amount!) : '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetBetButton extends StatelessWidget {
  const _PresetBetButton({
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: PokerTheme.surfaceLight,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Waiting indicator when it's not your turn
class WaitingIndicator extends StatelessWidget {
  const WaitingIndicator({
    super.key,
    this.currentPlayerName,
    this.showAutoAction = false,
    this.autoActionEnabled = false,
    this.autoActionLabel = 'Check / Fold',
    this.onAutoActionChanged,
    this.timeRemaining,
    this.turnTimeSeconds = 30,
    this.usingTimeBank = false,
    this.timeBank = 0,
  });
  final String? currentPlayerName;

  /// Whether to show the auto-action checkbox
  /// (only for seated players in the hand)
  final bool showAutoAction;

  /// Whether auto-action is currently enabled
  final bool autoActionEnabled;

  /// The label for the auto-action checkbox ("Check / Fold" or "Fold")
  final String autoActionLabel;

  /// Callback when auto-action checkbox is toggled
  final ValueChanged<bool>? onAutoActionChanged;

  /// Timer info
  final double? timeRemaining;
  final int turnTimeSeconds;
  final bool usingTimeBank;
  final double timeBank;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PokerTheme.surfaceDark.withValues(alpha: 0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Timer and waiting message
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (timeRemaining != null) ...[
                  TurnTimer(
                    timeRemaining: timeRemaining!,
                    totalTime: turnTimeSeconds,
                    usingTimeBank: usingTimeBank,
                    timeBank: timeBank,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                ] else ...[
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(PokerTheme.goldAccent),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  currentPlayerName != null
                      ? 'Waiting for $currentPlayerName...'
                      : 'Waiting for other players...',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            // Auto-action checkbox
            if (showAutoAction) ...[
              const SizedBox(height: 12),
              _AutoActionCheckbox(
                label: autoActionLabel,
                value: autoActionEnabled,
                onChanged: onAutoActionChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Checkbox for auto-action (Check/Fold or Fold)
class _AutoActionCheckbox extends StatelessWidget {
  const _AutoActionCheckbox({
    required this.label,
    required this.value,
    this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: value
              ? PokerTheme.chipBlue.withValues(alpha: 0.3)
              : PokerTheme.surfaceLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? PokerTheme.chipBlue : Colors.white24,
            width: value ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: onChanged != null
                    ? (v) => onChanged!(v ?? false)
                    : null,
                activeColor: PokerTheme.chipBlue,
                checkColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: value ? Colors.white : Colors.white70,
                fontSize: 14,
                fontWeight: value ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
