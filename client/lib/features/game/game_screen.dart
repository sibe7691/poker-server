import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poker_app/core/constants.dart';
import 'package:poker_app/core/theme.dart';
import 'package:poker_app/features/game/cashier_dialog.dart';
import 'package:poker_app/features/game/poker_table.dart';
import 'package:poker_app/models/models.dart';
import 'package:poker_app/providers/providers.dart';
import 'package:poker_app/services/websocket_service.dart';
import 'package:poker_app/widgets/widgets.dart';

// Fire-and-forget futures are intentional in callbacks and event handlers
// ignore_for_file: discarded_futures
// Cascades don't work well with Riverpod's ref.listen due to type inference
// ignore_for_file: cascade_invocations

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({required this.tableId, super.key});
  final String tableId;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  GameState? _gameState;
  final List<ChatMessage> _chatMessages = [];
  StreamSubscription<HandResult>? _handResultSub;

  /// Current hand result to display on player seats
  HandResult? _currentHandResult;

  /// Whether auto-action (check/fold or fold) is enabled
  bool _autoActionEnabled = false;

  /// Track the last hand number to reset auto-action when a new hand starts
  int _lastHandNumber = 0;

  /// Track unread chat message count for badge display
  int _unreadChatCount = 0;

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
      'GameScreen: _ensureConnection - isAuthenticated: '
      '${state.isAuthenticated}, currentTableId: ${state.currentTableId}',
    );

    if (!state.isAuthenticated) {
      debugPrint('GameScreen: Not authenticated, connecting...');
      await controller.connectAndAuth();
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;

    // Join the table as a spectator (no seat) to receive game state updates
    // The user will select a seat to actually join as a player
    final currentState = ref.read(gameControllerProvider);
    debugPrint(
      'GameScreen: Checking join - currentTableId: '
      '${currentState.currentTableId}, widget.tableId: ${widget.tableId}',
    );

    if (currentState.currentTableId != widget.tableId) {
      debugPrint('GameScreen: Joining table ${widget.tableId} as spectator');
      controller.joinTable(widget.tableId);
    } else {
      debugPrint('GameScreen: Already at table ${widget.tableId}');
      // We're already at this table, but _gameState is null (fresh widget).
      // Check if we have a cached game state from the provider.
      final existingGameState = ref.read(gameStateProvider).valueOrNull;
      if (existingGameState != null &&
          existingGameState.tableId == widget.tableId) {
        debugPrint('GameScreen: Using cached game state');
        setState(() => _gameState = existingGameState);
      } else {
        // No cached state available, re-join to request current state
        debugPrint('GameScreen: Re-joining to request current state');
        controller.joinTable(widget.tableId);
      }
    }
  }

  void _selectSeat(int seatIndex) {
    // Join the table at the selected seat
    ref
        .read(gameControllerProvider.notifier)
        .joinTable(
          widget.tableId,
          seat: seatIndex,
        );
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
          'Are you sure you want to leave your seat? '
          'You will continue watching as a spectator.',
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

    if ((shouldStandUp ?? false) && mounted) {
      ref.read(gameControllerProvider.notifier).standUp();
    }
  }

  void _sendAction(PlayerAction action, {int? amount}) {
    // Reset auto-action when a manual action is taken
    if (_autoActionEnabled) {
      setState(() => _autoActionEnabled = false);
    }
    ref
        .read(gameControllerProvider.notifier)
        .sendAction(action, amount: amount);
  }

  /// Execute auto-action if enabled (check if possible, otherwise fold)
  void _executeAutoAction() {
    if (_gameState == null || !_autoActionEnabled) return;

    final validActions = _gameState!.validActions;

    // Try to check if possible, otherwise fold
    if (validActions.contains(PlayerAction.check)) {
      debugPrint('Auto-action: checking');
      ref.read(gameControllerProvider.notifier).sendAction(PlayerAction.check);
    } else if (validActions.contains(PlayerAction.fold)) {
      debugPrint('Auto-action: folding');
      ref.read(gameControllerProvider.notifier).sendAction(PlayerAction.fold);
    }

    // Reset auto-action after execution
    setState(() => _autoActionEnabled = false);
  }

  /// Get the label for the auto-action checkbox based on current game state
  String _getAutoActionLabel() {
    if (_gameState == null) return 'Check / Fold';

    // If there's a raise (call amount > 0), only fold is possible
    if (_gameState!.callAmount > 0) {
      return 'Fold';
    }

    return 'Check / Fold';
  }

  /// Whether to show the auto-action checkbox
  bool _shouldShowAutoAction() {
    if (_gameState == null) return false;

    final me = _gameState!.me;
    if (me == null) return false;

    // Only show if player is in the hand (has cards and not folded)
    return me.hasCards && !me.isFolded && !me.isAllIn;
  }

  void _showHandResult(HandResult result) {
    // Display winner on player seats instead of modal dialog
    setState(() {
      _currentHandResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen for game state updates
    ref.listen<AsyncValue<GameState>>(gameStateProvider, (previous, next) {
      debugPrint(
        'GameScreen: gameStateProvider changed - hasData: ${next.hasValue}, '
        'hasError: ${next.hasError}',
      );
      next.whenData((state) {
        debugPrint(
          'GameScreen: Received game state for table ${state.tableId}, '
          'players: ${state.players.length}',
        );

        final previousState = _gameState;
        setState(() => _gameState = state);

        // Reset auto-action and hand result when a new hand starts
        if (state.handNumber != _lastHandNumber) {
          _lastHandNumber = state.handNumber;
          if (_autoActionEnabled) {
            setState(() => _autoActionEnabled = false);
          }
          // Clear hand result when new hand starts
          if (_currentHandResult != null) {
            setState(() => _currentHandResult = null);
          }
        }

        // Execute auto-action if it's now our turn and auto-action is enabled
        final wasMyTurn = previousState?.isMyTurn ?? false;
        final isMyTurn = state.isMyTurn;

        if (!wasMyTurn && isMyTurn && _autoActionEnabled) {
          // Delay slightly to ensure state is fully updated
          Future.microtask(() {
            if (mounted) _executeAutoAction();
          });
        }
      });
      next.whenOrNull(
        error: (e, st) => debugPrint('GameScreen: gameStateProvider error: $e'),
      );
    });

    // Listen for hand results
    ref.listen<AsyncValue<HandResult>>(
      handResultProvider,
      (previous, next) => next.whenData(_showHandResult),
    );

    // Listen for chat messages
    ref.listen<AsyncValue<ChatMessage>>(
      chatMessagesProvider,
      (previous, next) {
        next.whenData((ChatMessage message) {
          setState(() {
            _chatMessages.add(message);
            _unreadChatCount++;
          });
        });
      },
    );

    // Listen for errors
    ref.listen<AsyncValue<String>>(
      wsErrorProvider,
      (previous, next) {
        next.whenData((String error) {
          debugPrint('GameScreen: WebSocket error: $error');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.red),
          );
        });
      },
    );

    final controllerState = ref.watch(gameControllerProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
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
                        handResult: _currentHandResult,
                        chatMessages: _chatMessages,
                      ),
              ),
              // Action buttons (if it's your turn)
              if (_gameState != null && _gameState!.isMyTurn)
                ActionButtonsPanel(
                  validActions: _gameState!.validActions,
                  callAmount: _gameState!.callAmount,
                  minRaise: _gameState!.minRaise,
                  maxBet: _gameState!.me?.chips ?? 0,
                  pot: _gameState!.pot,
                  onAction: _sendAction,
                )
              else if (_gameState != null && _gameState!.isInProgress)
                WaitingIndicator(
                  currentPlayerName: _gameState!.currentPlayer?.username,
                  showAutoAction: _shouldShowAutoAction(),
                  autoActionEnabled: _autoActionEnabled,
                  autoActionLabel: _getAutoActionLabel(),
                  onAutoActionChanged: (enabled) {
                    setState(() => _autoActionEnabled = enabled);
                  },
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
                label: _unreadChatCount > 0
                    ? Text(
                        _unreadChatCount > 9 ? '9+' : '$_unreadChatCount',
                        style: const TextStyle(fontSize: 10),
                      )
                    : null,
                isLabelVisible: _unreadChatCount > 0,
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
                'Back to Lobby',
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
          _buildMenu(),
        ],
      ),
    );
  }

  Widget _buildMenu() {
    // TODO(pontus): use isAdmin to conditionally show admin menu items
    // final isAdmin = ref.watch(isAdminProvider);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white),
      color: PokerTheme.surfaceDark,
      onSelected: (value) {
        if (value == 'start') {
          ref.read(gameControllerProvider.notifier).startGame();
        } else if (value == 'cashier') {
          _showCashierDialog();
        }
      },
      itemBuilder: (context) => [
        // TODO(pontus): I don't think we need the start menu item
        // const PopupMenuItem(
        //   value: 'start',
        //   child: Row(
        //     children: [
        //       Icon(Icons.play_arrow, size: 20, color: Colors.white70),
        //       SizedBox(width: 8),
        //       Text('Start Game', style: TextStyle(color: Colors.white)),
        //     ],
        //   ),
        // ),
        // TODO(pontus): add cashier menu item only for admin
        // if (isAdmin)
        const PopupMenuItem(
          value: 'cashier',
          child: Row(
            children: [
              Icon(
                Icons.account_balance,
                size: 20,
                color: PokerTheme.goldAccent,
              ),
              SizedBox(width: 8),
              Text('Cashier', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }

  void _showCashierDialog() {
    if (_gameState == null) return;

    showDialog<void>(
      context: context,
      builder: (context) => CashierDialog(gameState: _gameState!),
    );
  }

  Widget _buildLoadingState(GameControllerState state) {
    var message = 'Connecting...';
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
      child: const Row(
        children: [
          Icon(Icons.visibility, color: PokerTheme.goldAccent, size: 20),
          SizedBox(width: 12),
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
    // Clear unread count when opening chat
    setState(() => _unreadChatCount = 0);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PokerTheme.surfaceDark,
      isScrollControlled: true,
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
  const _ChatSheet({required this.messages, required this.onSend});
  final List<ChatMessage> messages;
  final void Function(String) onSend;

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: 350,
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
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.chat, color: PokerTheme.goldAccent, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Table Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.messages.length} messages',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            // Messages
            Expanded(
              child: widget.messages.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              color: Colors.white24, size: 48),
                          SizedBox(height: 12),
                          Text(
                            'No messages yet',
                            style: TextStyle(color: Colors.white38),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Be the first to say something!',
                            style: TextStyle(color: Colors.white24, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: widget.messages.length,
                      itemBuilder: (context, index) {
                        final msg = widget.messages[index];
                        final isFirst = index == 0;
                        final prevMsg = isFirst ? null : widget.messages[index - 1];
                        final showTimeSeparator = isFirst ||
                            msg.timestamp.difference(prevMsg!.timestamp).inMinutes > 5;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showTimeSeparator)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: PokerTheme.surfaceLight,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _formatTimestamp(msg.timestamp),
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            _ChatMessageTile(message: msg),
                          ],
                        );
                      },
                    ),
            ),
            const Divider(color: Colors.white12, height: 1),
            // Input
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: PokerTheme.surfaceLight,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: _send,
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: PokerTheme.goldAccent,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.black),
                      onPressed: () => _send(_controller.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
    );

    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';

    if (messageDate == today) {
      return 'Today $timeStr';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday $timeStr';
    } else {
      return '${timestamp.day}/${timestamp.month} $timeStr';
    }
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    widget.onSend(text.trim());
    _controller.clear();
    // Keep focus on the text field to keep keyboard open
    _focusNode.requestFocus();
    // Scroll to bottom after sending
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

/// Individual chat message tile
class _ChatMessageTile extends StatelessWidget {
  const _ChatMessageTile({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  _getUserColor(message.username),
                  _getUserColor(message.username).withValues(alpha: 0.7),
                ],
              ),
            ),
            child: Center(
              child: Text(
                message.username.isNotEmpty
                    ? message.username[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Message content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      message.username,
                      style: TextStyle(
                        color: _getUserColor(message.username),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(message.timestamp),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  message.message,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getUserColor(String username) {
    // Generate a consistent color based on username
    final colors = [
      PokerTheme.goldAccent,
      PokerTheme.chipBlue,
      PokerTheme.chipRed,
      const Color(0xFF4CAF50),
      const Color(0xFF9C27B0),
      const Color(0xFFFF9800),
      const Color(0xFF00BCD4),
      const Color(0xFFE91E63),
    ];
    final index = username.hashCode.abs() % colors.length;
    return colors[index];
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
