import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/theme.dart';
import '../core/utils.dart';

/// Displays the pot amount with animation
class PotDisplay extends StatelessWidget {
  final int pot;
  final int? sidePot;

  const PotDisplay({
    super.key,
    required this.pot,
    this.sidePot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black54,
            Colors.black38,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PokerTheme.goldAccent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildChipStack(),
              const SizedBox(width: 8),
              Text(
                'POT',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formatChips(pot),
            style: const TextStyle(
              color: PokerTheme.goldAccent,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ).animate(
            key: ValueKey(pot),
          ).scale(
            begin: const Offset(1.2, 1.2),
            end: const Offset(1, 1),
            duration: 200.ms,
          ),
          if (sidePot != null && sidePot! > 0)
            Text(
              'Side pot: ${formatChips(sidePot!)}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChipStack() {
    return SizedBox(
      width: 24,
      height: 20,
      child: Stack(
        children: [
          Positioned(
            bottom: 0,
            child: _buildChip(PokerTheme.chipRed),
          ),
          Positioned(
            bottom: 4,
            left: 2,
            child: _buildChip(PokerTheme.chipBlue),
          ),
          Positioned(
            bottom: 8,
            left: 4,
            child: _buildChip(PokerTheme.goldAccent),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(Color color) {
    return Container(
      width: 16,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.white24, width: 1),
      ),
    );
  }
}

/// Game phase indicator
class PhaseIndicator extends StatelessWidget {
  final String phase;
  final int handNumber;

  const PhaseIndicator({
    super.key,
    required this.phase,
    required this.handNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: PokerTheme.surfaceDark.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Hand #$handNumber',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 12,
            color: Colors.white24,
          ),
          const SizedBox(width: 8),
          Text(
            phase.toUpperCase(),
            style: const TextStyle(
              color: PokerTheme.goldAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
