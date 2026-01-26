import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../models/models.dart';
import '../services/websocket_service.dart';
import 'auth_provider.dart';

/// WebSocket service provider
final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Connection status provider
final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.statusStream;
});

/// Game state provider
final gameStateProvider = StreamProvider<GameState>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.gameStateStream;
});

/// Hand result provider
final handResultProvider = StreamProvider<HandResult>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.handResultStream;
});

/// Chat messages provider
final chatMessagesProvider = StreamProvider<ChatMessage>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.chatStream;
});

/// Tables list provider
final tablesListProvider = StreamProvider<List<TableInfo>>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.tablesStream;
});

/// Error messages provider
final wsErrorProvider = StreamProvider<String>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.errorStream;
});

/// Player events provider
final playerEventProvider = StreamProvider<PlayerEvent>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.playerEventStream;
});

/// Player action events provider
final playerActionProvider = StreamProvider<PlayerActionEvent>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.playerActionStream;
});

/// Chips updated events provider
final chipsUpdatedProvider = StreamProvider<ChipsUpdatedEvent>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.chipsUpdatedStream;
});

/// Hand started events provider
final handStartedProvider = StreamProvider<HandStartedEvent>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.handStartedStream;
});

/// State changed events provider
final stateChangedProvider = StreamProvider<StateChangedEvent>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.stateChangedStream;
});

/// Ledger entries provider
final ledgerProvider = StreamProvider<List<LedgerEntry>>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.ledgerStream;
});

/// Standings entries provider
final standingsProvider = StreamProvider<List<StandingEntry>>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.standingsStream;
});

/// Game controller for managing game actions
class GameController extends StateNotifier<GameControllerState> {
  final WebSocketService _ws;
  final Ref _ref;
  StreamSubscription? _statusSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _authFailedSub;
  
  /// Track pending table join for reconnection after token refresh
  String? _pendingTableJoin;
  int? _pendingTableSeat;

  GameController(this._ws, this._ref) : super(GameControllerState.initial()) {
    _statusSub = _ws.statusStream.listen(_onStatusChange);
    _errorSub = _ws.errorStream.listen(_onError);
    _authFailedSub = _ws.authFailedStream.listen(_onAuthFailed);
  }

  void _onStatusChange(ConnectionStatus status) {
    state = state.copyWith(
      isConnecting: status == ConnectionStatus.connecting,
      isConnected:
          status == ConnectionStatus.connected ||
          status == ConnectionStatus.authenticated,
      isAuthenticated: status == ConnectionStatus.authenticated,
    );
    
    // If we just authenticated and have a pending table join, rejoin it
    if (status == ConnectionStatus.authenticated && _pendingTableJoin != null) {
      final tableId = _pendingTableJoin!;
      final seat = _pendingTableSeat;
      _pendingTableJoin = null;
      _pendingTableSeat = null;
      joinTable(tableId, seat: seat);
    }
  }

  void _onError(String error) {
    state = state.copyWith(error: error);
  }

  /// Handle authentication failure (e.g., token expired)
  Future<void> _onAuthFailed(AuthFailedEvent event) async {
    if (!event.isTokenExpired) {
      // Non-token error, just report it
      state = state.copyWith(error: event.message);
      return;
    }

    WebSocketLogger.info('AUTH', 'Handling token expiration, attempting refresh...');
    _ws.setRefreshingToken(true);
    
    try {
      // Store current table for reconnection
      if (state.currentTableId != null) {
        _pendingTableJoin = state.currentTableId;
        // Note: we don't have seat info here, will rejoin without specific seat
      }

      // Try to refresh the token
      final authNotifier = _ref.read(authProvider.notifier);
      final newToken = await authNotifier.refreshAccessToken();

      if (newToken != null) {
        WebSocketLogger.info('AUTH', 'Token refreshed successfully, re-authenticating...');
        // Re-authenticate with the new token
        _ws.authenticate(newToken);
      } else {
        WebSocketLogger.error('AUTH', 'Token refresh failed, forcing logout');
        // Refresh failed - force logout
        state = state.copyWith(error: 'Session expired. Please log in again.');
        await authNotifier.logout();
        await disconnect();
      }
    } finally {
      _ws.setRefreshingToken(false);
    }
  }

  /// Connect and authenticate
  Future<bool> connectAndAuth() async {
    state = state.copyWith(isConnecting: true, error: null);

    final connected = await _ws.connect();
    
    if (!connected) {
      WebSocketLogger.error('AUTH', 'Cannot authenticate - connection failed');
      state = state.copyWith(
        isConnecting: false, 
        error: 'Failed to connect to server',
      );
      return false;
    }

    final authState = _ref.read(authProvider);
    if (authState.accessToken != null) {
      _ws.authenticate(authState.accessToken!);
      return true;
    } else {
      WebSocketLogger.warning('AUTH', 'No access token available for authentication');
      state = state.copyWith(isConnecting: false);
      return false;
    }
  }

  /// Join a table
  void joinTable(String tableId, {int? seat}) {
    state = state.copyWith(currentTableId: tableId);
    _ws.joinTable(tableId, seat: seat);
  }

  /// Leave current table
  void leaveTable() {
    _ws.leaveTable();
    state = state.copyWith(currentTableId: null);
  }

  /// Stand up from seat (become spectator)
  void standUp() {
    _ws.standUp();
  }

  /// Send a game action
  void sendAction(PlayerAction action, {int? amount}) {
    _ws.sendAction(action, amount: amount);
  }

  /// Send chat message
  void sendChat(String message) {
    _ws.sendChat(message);
  }

  /// Fetch tables list
  Future<List<TableInfo>> fetchTables() async {
    return await _ws.fetchTablesList();
  }

  /// Start game (admin)
  void startGame() {
    _ws.startGame();
  }

  /// Create a new table (admin)
  void createTable({
    required String tableId,
    int? smallBlind,
    int? bigBlind,
    int? maxPlayers,
  }) {
    _ws.createTable(
      tableId: tableId,
      smallBlind: smallBlind,
      bigBlind: bigBlind,
      maxPlayers: maxPlayers,
    );
  }

  /// Delete a table (admin)
  void deleteTable(String tableId) {
    _ws.deleteTable(tableId);
  }

  /// Give chips to a player (admin buy-in)
  void giveChips({required String playerId, required int amount}) {
    _ws.giveChips(playerId: playerId, amount: amount);
  }

  /// Take chips from a player (admin cash-out)
  void takeChips({required String playerId, required int amount}) {
    _ws.takeChips(playerId: playerId, amount: amount);
  }

  /// Get transaction ledger (admin)
  void getLedger() {
    _ws.getLedger();
  }

  /// Get player standings (admin)
  void getStandings() {
    _ws.getStandings();
  }

  /// Disconnect
  Future<void> disconnect() async {
    await _ws.disconnect();
    state = GameControllerState.initial();
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _errorSub?.cancel();
    _authFailedSub?.cancel();
    super.dispose();
  }
}

/// Game controller state
class GameControllerState {
  final bool isConnecting;
  final bool isConnected;
  final bool isAuthenticated;
  final String? currentTableId;
  final String? error;

  const GameControllerState({
    this.isConnecting = false,
    this.isConnected = false,
    this.isAuthenticated = false,
    this.currentTableId,
    this.error,
  });

  factory GameControllerState.initial() => const GameControllerState();

  GameControllerState copyWith({
    bool? isConnecting,
    bool? isConnected,
    bool? isAuthenticated,
    String? currentTableId,
    String? error,
  }) {
    return GameControllerState(
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      currentTableId: currentTableId ?? this.currentTableId,
      error: error,
    );
  }
}

/// Game controller provider
final gameControllerProvider =
    StateNotifierProvider<GameController, GameControllerState>((ref) {
      final ws = ref.watch(webSocketServiceProvider);
      return GameController(ws, ref);
    });

/// Current table ID provider
final currentTableIdProvider = Provider<String?>((ref) {
  return ref.watch(gameControllerProvider).currentTableId;
});

/// Is my turn provider
final isMyTurnProvider = Provider<bool>((ref) {
  final gameState = ref.watch(gameStateProvider).valueOrNull;
  return gameState?.isMyTurn ?? false;
});

/// Valid actions provider
final validActionsProvider = Provider<List<PlayerAction>>((ref) {
  final gameState = ref.watch(gameStateProvider).valueOrNull;
  return gameState?.validActions ?? [];
});

/// My player provider
final myPlayerProvider = Provider<Player?>((ref) {
  final gameState = ref.watch(gameStateProvider).valueOrNull;
  return gameState?.me;
});
