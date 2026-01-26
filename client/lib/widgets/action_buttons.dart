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
    required this.bigBlind,
    required this.onAction,
    super.key,
  });
  final List<PlayerAction> validActions;
  final int callAmount;
  final int minRaise;
  final int maxBet;
  final int bigBlind;
  final void Function(PlayerAction action, {int? amount}) onAction;

  @override
  State<ActionButtonsPanel> createState() => _ActionButtonsPanelState();
}

class _ActionButtonsPanelState extends State<ActionButtonsPanel> {
  double _raiseSliderValue = 0;
  final _debouncer = Debouncer();
  bool _showRaiseSlider = false;

  @override
  void didUpdateWidget(ActionButtonsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.minRaise != oldWidget.minRaise) {
      _raiseSliderValue = widget.minRaise.toDouble();
    }
  }

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
            // Raise slider (if showing)
            if (_showRaiseSlider) _buildRaiseSlider(),
            const SizedBox(height: 12),
            // Action buttons row
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildRaiseSlider() {
    final min = widget.minRaise.toDouble();
    final max = widget.maxBet.toDouble();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Raise to: ${formatChips(_raiseSliderValue.toInt())}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => setState(() => _showRaiseSlider = false),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              formatChips(min.toInt()),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: PokerTheme.goldAccent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: PokerTheme.goldAccent,
                  overlayColor: PokerTheme.goldAccent.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: _raiseSliderValue.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: ((max - min) / widget.bigBlind).round().clamp(
                    1,
                    100,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _raiseSliderValue = value;
                    });
                  },
                ),
              ),
            ),
            Text(
              formatChips(max.toInt()),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        // Quick bet buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _quickBetButton('Min', widget.minRaise.toDouble()),
            _quickBetButton(
              '1/2 Pot',
              (widget.callAmount * 1.5).clamp(min, max),
            ),
            _quickBetButton(
              'Pot',
              (widget.callAmount * 2).clamp(min, max).toDouble(),
            ),
            _quickBetButton('All In', max),
          ],
        ),
        const SizedBox(height: 8),
        // Confirm raise button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: PokerTheme.goldAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () {
              if (_debouncer.call()) {
                HapticFeedback.mediumImpact();
                final action = widget.validActions.contains(PlayerAction.raise)
                    ? PlayerAction.raise
                    : PlayerAction.bet;
                widget.onAction(action, amount: _raiseSliderValue.toInt());
                setState(() => _showRaiseSlider = false);
              }
            },
            child: Text(
              'Raise to ${formatChips(_raiseSliderValue.toInt())}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickBetButton(String label, double value) {
    return TextButton(
      onPressed: () {
        setState(() {
          _raiseSliderValue = value;
        });
      },
      child: Text(
        label,
        style: const TextStyle(
          color: PokerTheme.goldAccent,
          fontSize: 12,
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
                  _raiseSliderValue = widget.minRaise.toDouble();
                  _showRaiseSlider = true;
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
