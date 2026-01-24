import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/game_state.dart';

/// Dialog showing hand results with winners
class HandResultDialog extends StatelessWidget {
  final HandResult result;

  const HandResultDialog({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              PokerTheme.surfaceDark,
              PokerTheme.darkBackground,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: PokerTheme.goldAccent.withValues(alpha: 0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: PokerTheme.goldAccent.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Trophy icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: PokerTheme.goldAccent.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emoji_events,
                color: PokerTheme.goldAccent,
                size: 48,
              ),
            ).animate()
              .scale(duration: 400.ms, curve: Curves.elasticOut)
              .fadeIn(),
            const SizedBox(height: 16),
            // Title
            Text(
              result.winners.length > 1 ? 'SPLIT POT' : 'WINNER',
              style: const TextStyle(
                color: PokerTheme.goldAccent,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 24),
            // Winners list
            ...result.winners.asMap().entries.map((entry) {
              final index = entry.key;
              final winner = entry.value;
              return _buildWinnerRow(winner, index);
            }),
            const SizedBox(height: 24),
            // Total pot
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Total Pot: ',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    formatChips(result.pot),
                    style: const TextStyle(
                      color: PokerTheme.goldAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 600.ms),
            const SizedBox(height: 24),
            // Close button
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: PokerTheme.surfaceLight,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              child: const Text('Continue'),
            ).animate().fadeIn(delay: 800.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildWinnerRow(Winner winner, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Avatar
          CircleAvatar(
            backgroundColor: PokerTheme.tableFelt,
            child: Text(
              winner.username[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name and hand
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  winner.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (winner.handName != null)
                  Text(
                    winner.handName!,
                    style: const TextStyle(
                      color: PokerTheme.goldAccent,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
          // Amount won
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: PokerTheme.goldAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '+${formatChips(winner.amount)}',
              style: const TextStyle(
                color: PokerTheme.goldAccent,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ).animate().slideX(
      begin: index.isEven ? -0.2 : 0.2,
      end: 0,
      delay: (300 + index * 100).ms,
      duration: 300.ms,
    ).fadeIn(delay: (300 + index * 100).ms);
  }
}
