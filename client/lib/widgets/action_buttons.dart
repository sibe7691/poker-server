import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:poker_app/core/constants.dart';
import 'package:poker_app/core/theme.dart';
import 'package:poker_app/core/utils.dart';

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
    super.key,
  });
  final List<PlayerAction> validActions;
  final int callAmount;
  final int minRaise;
  final int maxBet;
  final int pot;
  final void Function(PlayerAction action, {int? amount}) onAction;

  @override
  State<ActionButtonsPanel> createState() => _ActionButtonsPanelState();
}

class _ActionButtonsPanelState extends State<ActionButtonsPanel> {
  final _debouncer = Debouncer();
  bool _showRaiseMenu = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PokerTheme.surfaceDark.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
            // Raise menu (if showing)
            if (_showRaiseMenu) _buildRaiseMenu(),
            const SizedBox(height: 12),
            // Action buttons row
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  /// Whether this is a raise (someone has bet) vs a bet (first to act)
  bool get _isRaise => widget.validActions.contains(PlayerAction.raise);

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

  Widget _buildRaiseMenu() {
    final action = _isRaise ? PlayerAction.raise : PlayerAction.bet;
    final actionLabel = _isRaise ? 'Raise' : 'Bet';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$actionLabel Amount',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => setState(() => _showRaiseMenu = false),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Percentage raise buttons
        Row(
          children: [
            _raisePercentButton('33%', 0.33, action),
            const SizedBox(width: 8),
            _raisePercentButton('50%', 0.50, action),
            const SizedBox(width: 8),
            _raisePercentButton('75%', 0.75, action),
            const SizedBox(width: 8),
            _raisePercentButton('100%', 1, action),
          ],
        ),
      ],
    );
  }

  Widget _raisePercentButton(
    String label,
    double percentage,
    PlayerAction action,
  ) {
    final amount = _calculateRaiseAmount(percentage);
    final isAllIn = amount >= widget.maxBet;

    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isAllIn
              ? PokerTheme.chipRed
              : PokerTheme.goldAccent.withValues(alpha: 0.9),
          foregroundColor: isAllIn ? Colors.white : Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: () {
          if (_debouncer.call()) {
            HapticFeedback.mediumImpact();
            widget.onAction(action, amount: amount);
            setState(() => _showRaiseMenu = false);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isAllIn ? 'All In' : formatChips(amount),
              style: TextStyle(
                fontSize: 11,
                fontWeight: isAllIn ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Fold button
        if (widget.validActions.contains(PlayerAction.fold))
          Expanded(
            child: _ActionButton(
              label: 'Fold',
              color: PokerTheme.chipRed,
              onPressed: () {
                if (_debouncer.call()) {
                  HapticFeedback.mediumImpact();
                  widget.onAction(PlayerAction.fold);
                }
              },
            ),
          ),
        const SizedBox(width: 8),
        // Check button
        if (widget.validActions.contains(PlayerAction.check))
          Expanded(
            child: _ActionButton(
              label: 'Check',
              color: PokerTheme.chipBlue,
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
              label: 'Call ${formatChips(widget.callAmount)}',
              color: PokerTheme.chipBlue,
              onPressed: () {
                if (_debouncer.call()) {
                  HapticFeedback.mediumImpact();
                  widget.onAction(PlayerAction.call);
                }
              },
            ),
          ),
        const SizedBox(width: 8),
        // Raise/Bet button
        if (widget.validActions.contains(PlayerAction.raise) ||
            widget.validActions.contains(PlayerAction.bet))
          Expanded(
            child: _ActionButton(
              label: widget.validActions.contains(PlayerAction.raise)
                  ? 'Raise'
                  : 'Bet',
              color: PokerTheme.goldAccent,
              textColor: Colors.black,
              onPressed: () {
                setState(() {
                  _showRaiseMenu = !_showRaiseMenu;
                });
              },
            ),
          ),
        // All-In button
        if (widget.validActions.contains(PlayerAction.allIn))
          Expanded(
            child: _ActionButton(
              label: 'All In',
              color: PokerTheme.chipRed,
              onPressed: () {
                if (_debouncer.call()) {
                  HapticFeedback.heavyImpact();
                  widget.onAction(PlayerAction.allIn);
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
  });
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 4,
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
        textAlign: TextAlign.center,
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
            // Waiting message
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(PokerTheme.goldAccent),
                  ),
                ),
                const SizedBox(width: 12),
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
