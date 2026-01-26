import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poker_app/core/theme.dart';
import 'package:poker_app/models/models.dart';
import 'package:poker_app/providers/providers.dart';

/// Dialog for admin to manage player chips (buy-in/cash-out)
class CashierDialog extends ConsumerStatefulWidget {
  const CashierDialog({required this.gameState, super.key});
  final GameState gameState;

  @override
  ConsumerState<CashierDialog> createState() => _CashierDialogState();
}

class _CashierDialogState extends ConsumerState<CashierDialog> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _getController(String playerId) {
    return _controllers.putIfAbsent(
      playerId,
      TextEditingController.new,
    );
  }

  void _giveChips(Player player) {
    final controller = _getController(player.userId);
    final amount = int.tryParse(controller.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ref
        .read(gameControllerProvider.notifier)
        .giveChips(
          playerId: player.username,
          amount: amount,
        );

    controller.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Gave $amount chips to ${player.username}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _takeChips(Player player) {
    final controller = _getController(player.userId);
    final amount = int.tryParse(controller.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (amount > player.chips) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${player.username} only has ${player.chips} chips'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ref
        .read(gameControllerProvider.notifier)
        .takeChips(
          playerId: player.username,
          amount: amount,
        );

    controller.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Took $amount chips from ${player.username}'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the game state provider to get live updates when chips change
    final gameStateAsync = ref.watch(gameStateProvider);
    final gameState = gameStateAsync.valueOrNull ?? widget.gameState;
    final players = gameState.players;

    return Dialog(
      backgroundColor: PokerTheme.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: PokerTheme.goldAccent.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance,
                    color: PokerTheme.goldAccent,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Cashier',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Player list
            Flexible(
              child: players.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No players at the table',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: players.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final player = players[index];
                        return _PlayerChipRow(
                          player: player,
                          controller: _getController(player.userId),
                          onGive: () => _giveChips(player),
                          onTake: () => _takeChips(player),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerChipRow extends StatelessWidget {
  const _PlayerChipRow({
    required this.player,
    required this.controller,
    required this.onGive,
    required this.onTake,
  });
  final Player player;
  final TextEditingController controller;
  final VoidCallback onGive;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PokerTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Player info row
          Row(
            children: [
              // Seat indicator
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: PokerTheme.goldAccent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${player.seat + 1}',
                    style: const TextStyle(
                      color: PokerTheme.goldAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Player name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Chips: ${player.chips}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Connection status
              if (!player.isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Disconnected',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Amount input and buttons
          Row(
            children: [
              // Amount input
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Amount',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: PokerTheme.surfaceDark,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Give button
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: onGive,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Give'),
                ),
              ),
              const SizedBox(width: 8),
              // Take button
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: onTake,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.remove, size: 18),
                  label: const Text('Take'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
