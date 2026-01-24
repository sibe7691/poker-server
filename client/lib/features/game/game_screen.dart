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

    print(
      'GameScreen: _ensureConnection - isAuthenticated: ${state.isAuthenticated}, currentTableId: ${state.currentTableId}',
    );

    if (!state.isAuthenticated) {
      print('GameScreen: Not authenticated, connecting...');
      await controller.connectAndAuth();
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;

    // Join the table as a spectator (no seat) to receive game state updates
    // The user will select a seat to actually join as a player
    final currentState = ref.read(gameControllerProvider);
    print(
      'GameScreen: Checking join - currentTableId: ${currentState.currentTableId}, widget.tableId: ${widget.tableId}',
    );

    if (currentState.currentTableId != widget.tableId) {
      print('GameScreen: Joining table ${widget.tableId} as spectator');
      controller.joinTable(widget.tableId);
    } else {
      print('GameScreen: Already at table ${widget.tableId}');
      // We're already at this table, but _gameState is null (fresh widget).
      // Check if we have a cached game state from the provider.
      final existingGameState = ref.read(gameStateProvider).valueOrNull;
      if (existingGameState != null &&
          existingGameState.tableId == widget.tableId) {
        print('GameScreen: Using cached game state');
        setState(() => _gameState = existingGameState);
      } else {
        // No cached state available, re-join to request current state
        print('GameScreen: Re-joining to request current state');
        controller.joinTable(widget.tableId);
      }
    }
  }

  void _selectSeat(int seatIndex) {
    // Join the table at the selected seat
    final controller = ref.read(gameControllerProvider.notifier);
    controller.joinTable(widget.tableId, seat: seatIndex);
  }

  void _leaveTable() {
    ref.read(gameControllerProvider.notifier).leaveTable();
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

  @override
  Widget build(BuildContext context) {
    // Listen for game state updates
    ref.listen(gameStateProvider, (previous, next) {
      print(
        'GameScreen: gameStateProvider changed - hasData: ${next.hasValue}, hasError: ${next.hasError}',
      );
      next.whenData((state) {
        print(
          'GameScreen: Received game state for table ${state.tableId}, players: ${state.players.length}',
        );
        setState(() => _gameState = state);
      });
      next.whenOrNull(
        error: (e, st) {
          print('GameScreen: gameStateProvider error: $e');
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
        print('GameScreen: WebSocket error: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      });
    });

    final controllerState = ref.watch(gameControllerProvider);

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
              // Spectator banner (if not seated)
              if (_gameState != null && _gameState!.me == null)
                _buildSpectatorBanner(),
              // Main game area
              Expanded(
                child: _gameState == null
                    ? _buildLoadingState(controllerState)
                    : PokerTable(
                        gameState: _gameState!,
                        onAction: _sendAction,
                        onSeatSelected: _gameState!.me == null
                            ? _selectSeat
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
                  widget.tableId,
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
              if (value == 'start') {
                ref.read(gameControllerProvider.notifier).startGame();
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
