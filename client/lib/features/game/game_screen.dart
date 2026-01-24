import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/websocket_service.dart';
import '../../widgets/widgets.dart';
import 'hand_result_dialog.dart';
import 'poker_table.dart';

class GameScreen extends ConsumerStatefulWidget {
  final String tableId;

  const GameScreen({super.key, required this.tableId});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  GameState? _gameState;
  final List<ChatMessage> _chatMessages = [];
  StreamSubscription? _handResultSub;
  TableInfo? _tableInfo;

  @override
  void initState() {
    super.initState();
    // Defer connection to after the widget tree is built to avoid
    // modifying provider state during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureConnection();
    });
  }

  Future<void> _ensureConnection() async {
    if (!mounted) return;

    final controller = ref.read(gameControllerProvider.notifier);
    final state = ref.read(gameControllerProvider);

    debugPrint(
      'GameScreen: _ensureConnection - isAuthenticated: ${state.isAuthenticated}, currentTableId: ${state.currentTableId}',
    );

    if (!state.isAuthenticated) {
      debugPrint('GameScreen: Not authenticated, connecting...');
      await controller.connectAndAuth();
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;

    // Always fetch table info to get the authoritative maxPlayers value
    debugPrint('GameScreen: Fetching table info');
    await _fetchTableInfo();

    if (!mounted) return;

    // Check if we already have a game state for this table AND we're seated
    // Only use cached state if user is actually at the table (has 'me' player)
    final existingGameState = ref.read(gameStateProvider).valueOrNull;

    if (existingGameState != null &&
        existingGameState.tableId == widget.tableId &&
        existingGameState.me != null) {
      debugPrint(
        'GameScreen: Using cached game state (already seated at table), maxPlayers: ${existingGameState.maxPlayers}',
      );
      setState(() => _gameState = existingGameState);
    }
  }

  Future<void> _fetchTableInfo() async {
    try {
      final tables = await ref
          .read(gameControllerProvider.notifier)
          .fetchTables();
      if (!mounted) return;

      final tableInfo = tables
          .where((t) => t.tableId == widget.tableId)
          .firstOrNull;
      if (tableInfo != null) {
        setState(() => _tableInfo = tableInfo);
        debugPrint(
          'GameScreen: Got table info - ${tableInfo.name}, max players: ${tableInfo.maxPlayers}',
        );
      } else {
        debugPrint(
          'GameScreen: Table ${widget.tableId} not found in tables list, using defaults',
        );
        // Table not found - create a placeholder TableInfo with defaults
        // This allows the user to attempt joining (they'll get an error if table doesn't exist)
        setState(
          () => _tableInfo = TableInfo(
            tableId: widget.tableId,
            name: widget.tableId,
            playerCount: 0,
            maxPlayers: 10,
            smallBlind: 1,
            bigBlind: 2,
          ),
        );
      }
    } catch (e) {
      debugPrint('GameScreen: Failed to fetch table info: $e');
      // On error, still allow attempting to join with defaults
      if (mounted) {
        setState(
          () => _tableInfo = TableInfo(
            tableId: widget.tableId,
            name: widget.tableId,
            playerCount: 0,
            maxPlayers: 10,
            smallBlind: 1,
            bigBlind: 2,
          ),
        );
      }
    }
  }

  /// Creates a preview game state for displaying the table before joining
  GameState _createPreviewState() {
    final maxPlayers = _tableInfo?.maxPlayers ?? 10;
    debugPrint(
      'GameScreen: Creating preview state with maxPlayers: $maxPlayers (from tableInfo: ${_tableInfo != null})',
    );
    return GameState(
      tableId: widget.tableId,
      phase: GamePhase.waiting,
      maxPlayers: maxPlayers,
      smallBlind: _tableInfo?.smallBlind ?? 1,
      bigBlind: _tableInfo?.bigBlind ?? 2,
      players: const [],
      communityCards: const [],
    );
  }

  void _selectSeat(int seatIndex) {
    // Join the table at the selected seat
    // This is the first join_table call - it happens when the user clicks a seat
    debugPrint(
      'GameScreen: User selected seat $seatIndex, joining table ${widget.tableId}',
    );
    final controller = ref.read(gameControllerProvider.notifier);
    controller.joinTable(widget.tableId, seat: seatIndex);
  }

  Future<void> _changeSeat(int newSeatIndex) async {
    final currentSeat = _gameState?.me?.seat;
    if (currentSeat == null) return;

    final shouldChange = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PokerTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Change Seat?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Move from seat #${currentSeat + 1} to seat #${newSeatIndex + 1}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: PokerTheme.chipBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (shouldChange == true && mounted) {
      final controller = ref.read(gameControllerProvider.notifier);
      // Stand up first, then join the new seat
      controller.standUp();
      // Small delay to ensure stand up is processed
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        controller.joinTable(widget.tableId, seat: newSeatIndex);
      }
    }
  }

  void _leaveTable() {
    // Only call leaveTable if we've actually joined (not in preview mode)
    if (_gameState != null) {
      ref.read(gameControllerProvider.notifier).leaveTable();
    }
    context.go('/lobby');
  }

  Future<void> _standUp() async {
    final shouldStandUp = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PokerTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Stand Up?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to leave your seat? You will continue watching as a spectator.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: PokerTheme.goldAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Stand Up'),
          ),
        ],
      ),
    );

    if (shouldStandUp == true && mounted) {
      ref.read(gameControllerProvider.notifier).standUp();
    }
  }

  void _sendAction(PlayerAction action, {int? amount}) {
    ref
        .read(gameControllerProvider.notifier)
        .sendAction(action, amount: amount);
  }

  void _showHandResult(HandResult result) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => HandResultDialog(result: result),
    );
  }

  void _showCashierDialog() {
    final players = _gameState?.players ?? [];

    if (players.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No players at the table'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _CashierDialog(
        players: players,
        onGiveChips: (playerId, amount) {
          ref
              .read(gameControllerProvider.notifier)
              .giveChips(playerId: playerId, amount: amount);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen for game state updates
    ref.listen(gameStateProvider, (previous, next) {
      debugPrint(
        'GameScreen: gameStateProvider changed - hasData: ${next.hasValue}, hasError: ${next.hasError}',
      );
      next.whenData((state) {
        debugPrint(
          'GameScreen: Received game state for table ${state.tableId}, players: ${state.players.length}, maxPlayers: ${state.maxPlayers}',
        );
        if (_tableInfo != null && state.maxPlayers != _tableInfo!.maxPlayers) {
          debugPrint(
            'GameScreen: WARNING - maxPlayers mismatch! tableInfo: ${_tableInfo!.maxPlayers}, gameState: ${state.maxPlayers}. Using tableInfo value.',
          );
        }
        setState(() => _gameState = state);
      });
      next.whenOrNull(
        error: (e, st) {
          debugPrint('GameScreen: gameStateProvider error: $e');
        },
      );
    });

    // Listen for hand results
    ref.listen(handResultProvider, (previous, next) {
      next.whenData((result) {
        _showHandResult(result);
      });
    });

    // Listen for chat messages
    ref.listen(chatMessagesProvider, (previous, next) {
      next.whenData((message) {
        setState(() => _chatMessages.add(message));
      });
    });

    // Listen for errors
    ref.listen(wsErrorProvider, (previous, next) {
      next.whenData((error) {
        debugPrint('GameScreen: WebSocket error: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      });
    });

    final controllerState = ref.watch(gameControllerProvider);

    // Determine if we have enough data to show the table
    // In preview mode, we need _tableInfo to know the correct seat count
    final hasGameState = _gameState != null;
    final hasTableInfo = _tableInfo != null;
    final canShowTable = hasGameState || hasTableInfo;

    // Use actual game state if available, otherwise create a preview state
    // IMPORTANT: Always use _tableInfo.maxPlayers when available to ensure
    // consistent seat count between preview and joined states
    GameState displayState;
    if (_gameState != null) {
      // Use game state but override maxPlayers from tableInfo for consistency
      if (_tableInfo != null &&
          _gameState!.maxPlayers != _tableInfo!.maxPlayers) {
        debugPrint(
          'GameScreen: Overriding maxPlayers from ${_gameState!.maxPlayers} to ${_tableInfo!.maxPlayers}',
        );
        displayState = _gameState!.copyWith(maxPlayers: _tableInfo!.maxPlayers);
      } else {
        displayState = _gameState!;
      }
    } else {
      displayState = _createPreviewState();
    }
    final isPreviewMode = !hasGameState;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [
              PokerTheme.tableFelt,
              PokerTheme.primaryGreen,
              PokerTheme.darkBackground,
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar
              _buildTopBar(),
              // Preview banner (if not yet joined) or Spectator banner (if joined but not seated)
              if (isPreviewMode && canShowTable)
                _buildPreviewBanner()
              else if (_gameState != null && _gameState!.me == null)
                _buildSpectatorBanner(),
              // Main game area
              Expanded(
                child: !controllerState.isAuthenticated || !canShowTable
                    ? _buildLoadingState(controllerState)
                    : PokerTable(
                        gameState: displayState,
                        onAction: _sendAction,
                        onSeatSelected: displayState.me == null
                            ? _selectSeat
                            : null,
                        onChangeSeat: !isPreviewMode && displayState.me != null
                            ? _changeSeat
                            : null,
                      ),
              ),
              // Action buttons (if it's your turn)
              if (_gameState != null && _gameState!.isMyTurn)
                ActionButtonsPanel(
                  validActions: _gameState!.validActions,
                  callAmount: _gameState!.callAmount,
                  minRaise: _gameState!.minRaise,
                  maxBet: _gameState!.me?.chips ?? 0,
                  bigBlind: _gameState!.bigBlind,
                  onAction: _sendAction,
                )
              else if (_gameState != null && _gameState!.isInProgress)
                WaitingIndicator(
                  currentPlayerName: _gameState!.currentPlayer?.username,
                ),
            ],
          ),
        ),
      ),
      // Chat FAB
      floatingActionButton: _gameState != null
          ? FloatingActionButton(
              mini: true,
              backgroundColor: PokerTheme.surfaceDark,
              onPressed: () => _showChatSheet(context),
              child: Badge(
                isLabelVisible: _chatMessages.isNotEmpty,
                child: const Icon(Icons.chat, color: Colors.white70),
              ),
            )
          : null,
    );
  }

  Widget _buildTopBar() {
    final isSeated = _gameState?.me != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Stand Up button (if seated) or Leave button (if spectator)
          if (isSeated)
            TextButton.icon(
              onPressed: _standUp,
              icon: const Icon(
                Icons.event_seat,
                color: PokerTheme.goldAccent,
                size: 20,
              ),
              label: const Text(
                'Stand Up',
                style: TextStyle(color: PokerTheme.goldAccent),
              ),
              style: TextButton.styleFrom(
                backgroundColor: PokerTheme.surfaceDark.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: PokerTheme.goldAccent.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: _leaveTable,
              icon: const Icon(
                Icons.exit_to_app,
                color: Colors.white70,
                size: 20,
              ),
              label: const Text(
                'Leave',
                style: TextStyle(color: Colors.white70),
              ),
              style: TextButton.styleFrom(
                backgroundColor: PokerTheme.surfaceDark.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Table name
          Expanded(
            child: Column(
              children: [
                Text(
                  _tableInfo?.name ?? widget.tableId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_gameState != null)
                  Text(
                    '${_gameState!.smallBlind}/${_gameState!.bigBlind} blinds',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  )
                else if (_tableInfo != null)
                  Text(
                    '${_tableInfo!.smallBlind}/${_tableInfo!.bigBlind} blinds',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
              ],
            ),
          ),
          // Phase indicator
          if (_gameState != null && _gameState!.isInProgress)
            PhaseIndicator(
              phase: _gameState!.phase.name,
              handNumber: _gameState!.handNumber,
            ),
          // Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              switch (value) {
                case 'start':
                  ref.read(gameControllerProvider.notifier).startGame();
                  break;
                case 'cashier':
                  _showCashierDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'start',
                child: Row(
                  children: [
                    Icon(Icons.play_arrow, size: 20),
                    SizedBox(width: 8),
                    Text('Start Game'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'cashier',
                child: Row(
                  children: [
                    Icon(Icons.account_balance, size: 20),
                    SizedBox(width: 8),
                    Text('Cashier'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(GameControllerState state) {
    String message = 'Connecting...';
    if (state.isConnected && !state.isAuthenticated) {
      message = 'Authenticating...';
    } else if (state.isAuthenticated) {
      message = 'Loading table...';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: PokerTheme.goldAccent),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildPreviewBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: PokerTheme.chipBlue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PokerTheme.chipBlue.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.chair, color: PokerTheme.chipBlue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Select a seat to join the table',
              style: TextStyle(
                color: PokerTheme.chipBlue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpectatorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: PokerTheme.goldAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PokerTheme.goldAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility, color: PokerTheme.goldAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Select an open seat to join the table',
              style: TextStyle(
                color: PokerTheme.goldAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChatSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: PokerTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ChatSheet(
        messages: _chatMessages,
        onSend: (message) {
          ref.read(gameControllerProvider.notifier).sendChat(message);
        },
      ),
    );
  }

  @override
  void dispose() {
    _handResultSub?.cancel();
    super.dispose();
  }
}

class _ChatSheet extends StatefulWidget {
  final List<ChatMessage> messages;
  final Function(String) onSend;

  const _ChatSheet({required this.messages, required this.onSend});

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: 300,
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Messages
            Expanded(
              child: widget.messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: widget.messages.length,
                      itemBuilder: (context, index) {
                        final msg = widget.messages[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${msg.username}: ',
                                  style: const TextStyle(
                                    color: PokerTheme.goldAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(
                                  text: msg.message,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Input
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        filled: true,
                        fillColor: PokerTheme.surfaceLight,
                      ),
                      onSubmitted: _send,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: PokerTheme.goldAccent),
                    onPressed: () => _send(_controller.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    widget.onSend(text.trim());
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _CashierDialog extends StatefulWidget {
  final List<Player> players;
  final void Function(String playerId, int amount) onGiveChips;

  const _CashierDialog({required this.players, required this.onGiveChips});

  @override
  State<_CashierDialog> createState() => _CashierDialogState();
}

class _CashierDialogState extends State<_CashierDialog> {
  Player? _selectedPlayer;
  final _amountController = TextEditingController(text: '100');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PokerTheme.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.account_balance, color: PokerTheme.goldAccent),
          SizedBox(width: 12),
          Text('Cashier', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select a player:',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            // Player list
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: PokerTheme.surfaceLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.players.length,
                itemBuilder: (context, index) {
                  final player = widget.players[index];
                  final isSelected = _selectedPlayer?.userId == player.userId;
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: PokerTheme.goldAccent.withValues(
                      alpha: 0.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: player.chips > 0
                          ? PokerTheme.primaryGreen
                          : Colors.grey,
                      radius: 16,
                      child: Text(
                        player.username[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    title: Text(
                      player.username,
                      style: TextStyle(
                        color: isSelected
                            ? PokerTheme.goldAccent
                            : Colors.white,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      'Chips: ${player.chips}',
                      style: TextStyle(
                        color: player.chips > 0
                            ? Colors.white54
                            : Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle,
                            color: PokerTheme.goldAccent,
                          )
                        : null,
                    onTap: () => setState(() => _selectedPlayer = player),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // Amount input
            const Text(
              'Amount to give:',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: PokerTheme.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(
                  Icons.monetization_on,
                  color: PokerTheme.goldAccent,
                ),
                hintText: 'Enter amount',
                hintStyle: const TextStyle(color: Colors.white38),
              ),
            ),
            const SizedBox(height: 12),
            // Quick amount buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [50, 100, 200, 500, 1000].map((amount) {
                return ActionChip(
                  label: Text('+$amount'),
                  backgroundColor: PokerTheme.surfaceLight,
                  labelStyle: const TextStyle(color: Colors.white70),
                  onPressed: () {
                    _amountController.text = amount.toString();
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton.icon(
          onPressed: _selectedPlayer == null
              ? null
              : () {
                  final amount = int.tryParse(_amountController.text) ?? 0;
                  if (amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid amount'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  widget.onGiveChips(_selectedPlayer!.userId, amount);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Gave $amount chips to ${_selectedPlayer!.username}',
                      ),
                      backgroundColor: PokerTheme.primaryGreen,
                    ),
                  );
                },
          icon: const Icon(Icons.add),
          label: const Text('Give Chips'),
          style: ElevatedButton.styleFrom(
            backgroundColor: PokerTheme.goldAccent,
            foregroundColor: Colors.black,
            disabledBackgroundColor: Colors.grey,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
}
