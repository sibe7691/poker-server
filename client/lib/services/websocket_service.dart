import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:poker_app/core/constants.dart';
import 'package:poker_app/models/models.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Fire-and-forget futures are intentional in dispose and message handlers
// ignore_for_file: discarded_futures
// Generic catch clauses are needed for WebSocket error handling
// ignore_for_file: avoid_catches_without_on_clauses

/// Log levels for WebSocket logging
enum LogLevel { debug, info, warning, error }

/// WebSocket logger for structured logging
class WebSocketLogger {
  static bool enabled = true;
  static LogLevel minLevel = LogLevel.debug;

  static final List<String> _sensitiveKeys = ['token', 'password'];

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
  }

  static String _levelPrefix(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '🔍 DEBUG';
      case LogLevel.info:
        return 'ℹ️  INFO';
      case LogLevel.warning:
        return '⚠️  WARN';
      case LogLevel.error:
        return '❌ ERROR';
    }
  }

  static String _sanitizePayload(Map<String, dynamic> payload) {
    final sanitized = Map<String, dynamic>.from(payload);
    for (final key in _sensitiveKeys) {
      if (sanitized.containsKey(key)) {
        sanitized[key] = '***REDACTED***';
      }
    }
    return const JsonEncoder.withIndent('  ').convert(sanitized);
  }

  static void _log(
    LogLevel level,
    String category,
    String message, [
    Map<String, dynamic>? payload,
  ]) {
    if (!enabled || level.index < minLevel.index) return;

    final timestamp = _timestamp();
    final prefix = _levelPrefix(level);
    final buffer = StringBuffer()
      ..writeln('[$timestamp] $prefix [WS:$category] $message');

    if (payload != null && payload.isNotEmpty) {
      buffer.writeln('  Payload: ${_sanitizePayload(payload)}');
    }

    debugPrint(buffer.toString().trimRight());
  }

  static void debug(
    String category,
    String message, [
    Map<String, dynamic>? payload,
  ]) {
    _log(LogLevel.debug, category, message, payload);
  }

  static void info(
    String category,
    String message, [
    Map<String, dynamic>? payload,
  ]) {
    _log(LogLevel.info, category, message, payload);
  }

  static void warning(
    String category,
    String message, [
    Map<String, dynamic>? payload,
  ]) {
    _log(LogLevel.warning, category, message, payload);
  }

  static void error(
    String category,
    String message, [
    Map<String, dynamic>? payload,
  ]) {
    _log(LogLevel.error, category, message, payload);
  }

  static void outgoing(String messageType, Map<String, dynamic> payload) {
    _log(LogLevel.info, 'OUT', '→ Sending: $messageType', payload);
  }

  static void incoming(String messageType, Map<String, dynamic> payload) {
    _log(LogLevel.info, 'IN', '← Received: $messageType', payload);
  }

  static void connectionStateChange(
    ConnectionStatus from,
    ConnectionStatus to,
  ) {
    _log(LogLevel.info, 'CONN', 'State changed: ${from.name} → ${to.name}');
  }

  static void httpRequest(String method, String url) {
    _log(LogLevel.debug, 'HTTP', '→ $method $url');
  }

  static void httpResponse(
    String method,
    String url,
    int statusCode, [
    int? durationMs,
  ]) {
    final duration = durationMs != null ? ' (${durationMs}ms)' : '';
    final level = statusCode >= 400 ? LogLevel.error : LogLevel.info;
    _log(level, 'HTTP', '← $method $url - $statusCode$duration');
  }
}

/// Connection status enum
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  authenticated,
  error,
}

/// WebSocket message types from server
class ServerMessageType {
  static const String authenticated = 'authenticated';
  static const String authSuccess = 'auth_success';
  static const String error = 'error';
  static const String gameState = 'game_state';
  static const String playerAction = 'player_action';
  static const String playerJoined = 'player_joined';
  static const String playerLeft = 'player_left';
  static const String playerDisconnected = 'player_disconnected';
  static const String playerReconnected = 'player_reconnected';
  static const String handResult = 'hand_result';
  static const String chipsUpdated = 'chips_updated';
  static const String handStarted = 'hand_started';
  static const String stateChanged = 'state_changed';
  static const String chatBroadcast = 'chat_broadcast';
  static const String chatSent = 'chat_sent';
  static const String ledger = 'ledger';
  static const String standings = 'standings';
  static const String tablesList = 'tables_list';
  static const String tableCreated = 'table_created';
  static const String tableDeleted = 'table_deleted';
}

/// WebSocket service for real-time game communication
class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  final http.Client _httpClient = http.Client();

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _gameStateController = StreamController<GameState>.broadcast();
  final _handResultController = StreamController<HandResult>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _chatController = StreamController<ChatMessage>.broadcast();
  final _tablesController = StreamController<List<TableInfo>>.broadcast();
  final _playerEventController = StreamController<PlayerEvent>.broadcast();
  final _chipsUpdatedController =
      StreamController<ChipsUpdatedEvent>.broadcast();
  final _handStartedController = StreamController<HandStartedEvent>.broadcast();
  final _stateChangedController =
      StreamController<StateChangedEvent>.broadcast();
  final _ledgerController = StreamController<List<LedgerEntry>>.broadcast();
  final _standingsController =
      StreamController<List<StandingEntry>>.broadcast();
  final _playerActionController =
      StreamController<PlayerActionEvent>.broadcast();
  final _authFailedController = StreamController<AuthFailedEvent>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _currentTableId;
  bool _isRefreshingToken = false;

  /// Streams for UI to listen to
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<GameState> get gameStateStream => _gameStateController.stream;
  Stream<HandResult> get handResultStream => _handResultController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<ChatMessage> get chatStream => _chatController.stream;
  Stream<List<TableInfo>> get tablesStream => _tablesController.stream;
  Stream<PlayerEvent> get playerEventStream => _playerEventController.stream;
  Stream<ChipsUpdatedEvent> get chipsUpdatedStream =>
      _chipsUpdatedController.stream;
  Stream<HandStartedEvent> get handStartedStream =>
      _handStartedController.stream;
  Stream<StateChangedEvent> get stateChangedStream =>
      _stateChangedController.stream;
  Stream<List<LedgerEntry>> get ledgerStream => _ledgerController.stream;
  Stream<List<StandingEntry>> get standingsStream =>
      _standingsController.stream;
  Stream<PlayerActionEvent> get playerActionStream =>
      _playerActionController.stream;
  Stream<AuthFailedEvent> get authFailedStream => _authFailedController.stream;

  ConnectionStatus get status => _status;
  String? get currentTableId => _currentTableId;
  bool get isRefreshingToken => _isRefreshingToken;

  /// Set refreshing token state (called by GameController during token refresh)
  // ignore: use_setters_to_change_properties, avoid_positional_boolean_parameters
  void setRefreshingToken(bool value) => _isRefreshingToken = value;

  /// Connect to WebSocket server
  Future<bool> connect() async {
    if (_status == ConnectionStatus.connecting ||
        _status == ConnectionStatus.connected ||
        _status == ConnectionStatus.authenticated) {
      WebSocketLogger.debug(
        'CONN',
        'Connect called but already ${_status.name}',
      );
      return _status == ConnectionStatus.connected ||
          _status == ConnectionStatus.authenticated;
    }

    WebSocketLogger.info('CONN', 'Connecting to ${ApiConstants.wsUrl}');
    _setStatus(ConnectionStatus.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(ApiConstants.wsUrl));

      // Wait for the WebSocket connection to actually be established
      // The .ready future completes when the connection is open
      await _channel!.ready;

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      _setStatus(ConnectionStatus.connected);
      _startPingTimer();
      WebSocketLogger.info(
        'CONN',
        'Successfully connected, ping timer started',
      );
      return true;
    } catch (e) {
      WebSocketLogger.error('CONN', 'Connection failed: $e');
      _setStatus(ConnectionStatus.error);
      _errorController.add('Failed to connect: $e');
      _channel = null;
      return false;
    }
  }

  /// Authenticate with JWT token
  void authenticate(String token) {
    WebSocketLogger.info('AUTH', 'Authenticating with JWT token');
    _send({'type': 'auth', 'token': token});
  }

  /// Join a table
  void joinTable(String tableId, {int? seat}) {
    final message = <String, dynamic>{
      'type': 'join_table',
      'table_id': tableId,
    };
    if (seat != null) {
      message['seat'] = seat;
    }
    _currentTableId = tableId;
    WebSocketLogger.info(
      'TABLE',
      'Joining table: $tableId${seat != null ? ' at seat $seat' : ''}',
    );
    _send(message);
  }

  /// Leave current table
  void leaveTable() {
    WebSocketLogger.info('TABLE', 'Leaving table: $_currentTableId');
    _send({'type': 'leave_table'});
    _currentTableId = null;
  }

  /// Stand up from seat (become spectator)
  void standUp() {
    WebSocketLogger.info('TABLE', 'Standing up from table: $_currentTableId');
    _send({'type': 'stand_up'});
  }

  /// Send a game action
  void sendAction(PlayerAction action, {int? amount}) {
    final message = <String, dynamic>{
      'type': 'action',
      'action': action.serverValue,
    };
    if (amount != null && amount > 0) {
      message['amount'] = amount;
    }
    final amountStr = amount != null ? ' ($amount)' : '';
    WebSocketLogger.info(
      'ACTION',
      'Player action: ${action.serverValue}$amountStr',
    );
    _send(message);
  }

  /// Send a chat message
  void sendChat(String message) {
    WebSocketLogger.debug(
      'CHAT',
      'Sending chat message (${message.length} chars)',
    );
    _send({'type': 'chat', 'message': message});
  }

  /// Fetch tables list via HTTP
  Future<List<TableInfo>> fetchTablesList() async {
    const url = '${ApiConstants.baseUrl}${ApiConstants.tablesEndpoint}';
    final stopwatch = Stopwatch()..start();
    WebSocketLogger.httpRequest('GET', url);

    try {
      final response = await _httpClient.get(Uri.parse(url));
      stopwatch.stop();
      WebSocketLogger.httpResponse(
        'GET',
        url,
        response.statusCode,
        stopwatch.elapsedMilliseconds,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tables =
            (data['tables'] as List<dynamic>?)
                ?.map((t) => TableInfo.fromJson(t as Map<String, dynamic>))
                .toList() ??
            [];
        WebSocketLogger.debug('HTTP', 'Fetched ${tables.length} tables');
        _tablesController.add(tables);
        return tables;
      } else {
        WebSocketLogger.error(
          'HTTP',
          'Failed to fetch tables: ${response.statusCode}',
        );
        _errorController.add('Failed to fetch tables: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      stopwatch.stop();
      WebSocketLogger.error('HTTP', 'Failed to fetch tables: $e');
      _errorController.add('Failed to fetch tables: $e');
      return [];
    }
  }

  /// Start a new game (admin only)
  void startGame() {
    WebSocketLogger.info('ADMIN', 'Starting game');
    _send({'type': 'start_game'});
  }

  /// Create a new table (admin)
  void createTable({
    required String tableId,
    int? smallBlind,
    int? bigBlind,
    int? maxPlayers,
  }) {
    final message = <String, dynamic>{
      'type': 'create_table',
      'table_id': tableId,
    };
    if (smallBlind != null) message['small_blind'] = smallBlind;
    if (bigBlind != null) message['big_blind'] = bigBlind;
    if (maxPlayers != null) message['max_players'] = maxPlayers;
    WebSocketLogger.info(
      'ADMIN',
      'Creating table: $tableId (blinds: $smallBlind/$bigBlind, max: $maxPlayers)',
    );
    _send(message);
  }

  /// Delete a table (admin)
  void deleteTable(String tableId) {
    WebSocketLogger.info('ADMIN', 'Deleting table: $tableId');
    _send({'type': 'delete_table', 'table_id': tableId});
  }

  /// Give chips to a player (admin buy-in)
  void giveChips({required String playerId, required int amount}) {
    WebSocketLogger.info('ADMIN', 'Giving $amount chips to player: $playerId');
    _send({
      'type': 'give_chips',
      'player': playerId,
      'amount': amount,
    });
  }

  /// Take chips from a player (admin cash-out)
  void takeChips({required String playerId, required int amount}) {
    WebSocketLogger.info(
      'ADMIN',
      'Taking $amount chips from player: $playerId',
    );
    _send({
      'type': 'take_chips',
      'player': playerId,
      'amount': amount,
    });
  }

  /// Get transaction ledger (admin)
  void getLedger() {
    WebSocketLogger.debug('ADMIN', 'Requesting ledger');
    _send({'type': 'get_ledger'});
  }

  /// Get player standings (admin)
  void getStandings() {
    WebSocketLogger.debug('ADMIN', 'Requesting standings');
    _send({'type': 'get_standings'});
  }

  /// Register via WebSocket
  void register({required String username, required String password}) {
    WebSocketLogger.info('AUTH', 'Registering user: $username');
    _send({
      'type': 'register',
      'username': username,
      'password': password,
    });
  }

  /// Login via WebSocket
  void login({required String username, required String password}) {
    WebSocketLogger.info('AUTH', 'Logging in user: $username');
    _send({
      'type': 'login',
      'username': username,
      'password': password,
    });
  }

  void _send(Map<String, dynamic> message) {
    if (_channel == null) {
      WebSocketLogger.warning('OUT', 'Cannot send - channel is null', message);
      return;
    }

    final messageType = message['type'] as String? ?? 'unknown';
    WebSocketLogger.outgoing(messageType, message);
    _channel!.sink.add(jsonEncode(message));
  }

  void _handleMessage(dynamic rawMessage) {
    try {
      final data = jsonDecode(rawMessage as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      WebSocketLogger.incoming(type ?? 'unknown', data);

      switch (type) {
        case ServerMessageType.authenticated:
          WebSocketLogger.info(
            'AUTH',
            'Authentication successful (authenticated)',
          );
          _setStatus(ConnectionStatus.authenticated);

        case ServerMessageType.authSuccess:
          WebSocketLogger.info(
            'AUTH',
            'Authentication successful (auth_success)',
          );
          _setStatus(ConnectionStatus.authenticated);

        case ServerMessageType.error:
          final errorMsg = data['message'] as String? ?? 'Unknown error';
          final errorCode = data['code'] as String?;
          WebSocketLogger.error('SERVER', 'Server error: $errorMsg', data);

          // Check for token expiration error
          if (errorCode == 'AUTH_FAILED' &&
              (errorMsg.toLowerCase().contains('expired') ||
                  errorMsg.toLowerCase().contains('token'))) {
            // Only emit auth failed if we're not already refreshing
            if (!_isRefreshingToken) {
              WebSocketLogger.info(
                'AUTH',
                'Token expired, triggering refresh flow',
              );
              _authFailedController.add(
                AuthFailedEvent(
                  message: errorMsg,
                  code: errorCode,
                  isTokenExpired: true,
                ),
              );
            }
          } else {
            _errorController.add(errorMsg);
          }

        case ServerMessageType.gameState:
          final gameState = GameState.fromJson(data);
          WebSocketLogger.debug(
            'GAME',
            'Game state update - phase: ${gameState.phase.name}, '
            'pot: ${gameState.pot}, players: ${gameState.players.length}',
          );
          _gameStateController.add(gameState);

        case ServerMessageType.handResult:
          final result = HandResult.fromJson(data);
          WebSocketLogger.info('GAME', 'Hand result received');
          _handResultController.add(result);

        case ServerMessageType.chatBroadcast:
          final username = data['username'] as String? ?? 'Unknown';
          WebSocketLogger.debug('CHAT', 'Chat from $username');
          final chat = ChatMessage(
            userId: data['user_id'] as String? ?? '',
            username: username,
            message: data['message'] as String? ?? '',
            timestamp: DateTime.tryParse(data['timestamp'] as String? ?? '') ??
                DateTime.now(),
          );
          _chatController.add(chat);

        case ServerMessageType.chatSent:
          // Acknowledgment that chat was sent - no action needed
          WebSocketLogger.debug('CHAT', 'Chat message sent successfully');

        case ServerMessageType.tablesList:
          final tables =
              (data['tables'] as List<dynamic>?)
                  ?.map((t) => TableInfo.fromJson(t as Map<String, dynamic>))
                  .toList() ??
              [];
          WebSocketLogger.debug(
            'TABLE',
            'Received tables list (${tables.length} tables)',
          );
          _tablesController.add(tables);

        case ServerMessageType.playerJoined:
          final username = data['username'] as String? ?? 'Unknown';
          final seat = data['seat'] as int?;
          WebSocketLogger.info(
            'PLAYER',
            'Player joined: $username${seat != null ? ' at seat $seat' : ''}',
          );
          _playerEventController.add(
            PlayerEvent(
              type: PlayerEventType.joined,
              username: username,
              seat: seat,
            ),
          );

        case ServerMessageType.playerLeft:
          final username = data['username'] as String? ?? 'Unknown';
          WebSocketLogger.info('PLAYER', 'Player left: $username');
          _playerEventController.add(
            PlayerEvent(
              type: PlayerEventType.left,
              username: username,
            ),
          );

        case ServerMessageType.playerDisconnected:
          final username = data['username'] as String? ?? 'Unknown';
          final graceSeconds = data['grace_seconds'] as int? ?? 60;
          WebSocketLogger.info(
            'PLAYER',
            'Player disconnected: $username (grace: ${graceSeconds}s)',
          );
          _playerEventController.add(
            PlayerEvent(
              type: PlayerEventType.disconnected,
              username: username,
            ),
          );

        case ServerMessageType.playerReconnected:
          final username = data['username'] as String? ?? 'Unknown';
          WebSocketLogger.info('PLAYER', 'Player reconnected: $username');
          _playerEventController.add(
            PlayerEvent(
              type: PlayerEventType.reconnected,
              username: username,
            ),
          );

        case ServerMessageType.playerAction:
          final username = data['username'] as String? ?? 'Unknown';
          final action = data['action'] as String? ?? '';
          final amount = data['amount'] as int?;
          final amtStr = amount != null ? ' ($amount)' : '';
          WebSocketLogger.info(
            'ACTION',
            'Player action: $username $action$amtStr',
          );
          _playerActionController.add(
            PlayerActionEvent(
              userId: data['user_id'] as String? ?? '',
              username: username,
              action: action,
              amount: amount,
            ),
          );

        case ServerMessageType.chipsUpdated:
          final username = data['username'] as String? ?? 'Unknown';
          final chips = data['chips'] as int? ?? 0;
          final change = data['change'] as int? ?? data['amount'] as int? ?? 0;
          final sign = change >= 0 ? '+' : '';
          WebSocketLogger.info(
            'CHIPS',
            'Chips updated: $username now has $chips (change: $sign$change)',
          );
          _chipsUpdatedController.add(
            ChipsUpdatedEvent(
              userId:
                  data['user_id'] as String? ?? data['player'] as String? ?? '',
              username: username,
              chips: chips,
              change: change,
            ),
          );

        case ServerMessageType.handStarted:
          final handNumber = data['hand_number'] as int? ?? 0;
          final dealerSeat = data['dealer_seat'] as int? ?? 0;
          WebSocketLogger.info(
            'GAME',
            'Hand #$handNumber started, dealer at seat $dealerSeat',
          );
          _handStartedController.add(
            HandStartedEvent(
              handNumber: handNumber,
              dealerSeat: dealerSeat,
            ),
          );

        case ServerMessageType.stateChanged:
          final prevState = data['previous_state'] as String? ?? '';
          final newState =
              data['new_state'] as String? ?? data['state'] as String? ?? '';
          WebSocketLogger.info(
            'GAME',
            'Game state changed: $prevState → $newState',
          );
          _stateChangedController.add(
            StateChangedEvent(
              previousState: prevState,
              newState: newState,
            ),
          );

        case ServerMessageType.ledger:
          final entries =
              (data['entries'] as List<dynamic>?)
                  ?.map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              [];
          WebSocketLogger.debug(
            'ADMIN',
            'Received ledger (${entries.length} entries)',
          );
          _ledgerController.add(entries);

        case ServerMessageType.standings:
          final standings =
              (data['standings'] as List<dynamic>?)
                  ?.map(
                    (s) => StandingEntry.fromJson(s as Map<String, dynamic>),
                  )
                  .toList() ??
              [];
          WebSocketLogger.debug(
            'ADMIN',
            'Received standings (${standings.length} players)',
          );
          _standingsController.add(standings);

        case ServerMessageType.tableCreated:
          WebSocketLogger.info('TABLE', 'Table created, refreshing list');
          fetchTablesList();

        case ServerMessageType.tableDeleted:
          WebSocketLogger.info('TABLE', 'Table deleted, refreshing list');
          fetchTablesList();

        default:
          WebSocketLogger.warning('IN', 'Unknown message type: $type', data);
      }
    } catch (e, stackTrace) {
      WebSocketLogger.error(
        'PARSE',
        'Failed to parse message: $e\nStack: $stackTrace',
      );
      _errorController.add('Failed to parse message: $e');
    }
  }

  void _handleError(Object error) {
    WebSocketLogger.error('CONN', 'WebSocket error: $error');
    _setStatus(ConnectionStatus.error);
    _errorController.add('WebSocket error: $error');
  }

  void _handleDone() {
    WebSocketLogger.info('CONN', 'WebSocket connection closed');
    _setStatus(ConnectionStatus.disconnected);
    _currentTableId = null;
  }

  void _setStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      WebSocketLogger.connectionStateChange(_status, newStatus);
      _status = newStatus;
      _statusController.add(newStatus);
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    WebSocketLogger.debug('PING', 'Starting ping timer (30s interval)');
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_status == ConnectionStatus.authenticated) {
        WebSocketLogger.debug('PING', 'Sending ping');
        _send({'type': 'ping'});
      }
    });
  }

  /// Disconnect from WebSocket
  Future<void> disconnect() async {
    WebSocketLogger.info('CONN', 'Disconnecting...');
    _pingTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _currentTableId = null;
    _setStatus(ConnectionStatus.disconnected);
    WebSocketLogger.info('CONN', 'Disconnected');
  }

  /// Dispose all resources
  void dispose() {
    WebSocketLogger.info('CONN', 'Disposing WebSocket service');
    disconnect();
    _httpClient.close();
    _statusController.close();
    _gameStateController.close();
    _handResultController.close();
    _errorController.close();
    _chatController.close();
    _tablesController.close();
    _playerEventController.close();
    _chipsUpdatedController.close();
    _handStartedController.close();
    _stateChangedController.close();
    _ledgerController.close();
    _standingsController.close();
    _playerActionController.close();
    _authFailedController.close();
    WebSocketLogger.debug('CONN', 'All resources disposed');
  }
}

/// Auth failed event for token refresh handling
class AuthFailedEvent {
  AuthFailedEvent({
    required this.message,
    this.code,
    this.isTokenExpired = false,
  });
  final String message;
  final String? code;
  final bool isTokenExpired;
}

/// Chat message model
class ChatMessage {
  ChatMessage({
    required this.userId,
    required this.username,
    required this.message,
    required this.timestamp,
  });
  final String userId;
  final String username;
  final String message;
  final DateTime timestamp;
}

/// Player event (join/leave)
class PlayerEvent {
  PlayerEvent({required this.type, required this.username, this.seat});
  final PlayerEventType type;
  final String username;
  final int? seat;
}

enum PlayerEventType { joined, left, disconnected, reconnected }

/// Player action event
class PlayerActionEvent {
  PlayerActionEvent({
    required this.userId,
    required this.username,
    required this.action,
    this.amount,
  });
  final String userId;
  final String username;
  final String action;
  final int? amount;
}

/// Chips updated event (admin action)
class ChipsUpdatedEvent {
  ChipsUpdatedEvent({
    required this.userId,
    required this.username,
    required this.chips,
    required this.change,
  });
  final String userId;
  final String username;
  final int chips;
  final int change;
}

/// Hand started event
class HandStartedEvent {
  HandStartedEvent({
    required this.handNumber,
    required this.dealerSeat,
  });
  final int handNumber;
  final int dealerSeat;
}

/// State changed event (preflop -> flop, etc.)
class StateChangedEvent {
  StateChangedEvent({
    required this.previousState,
    required this.newState,
  });
  final String previousState;
  final String newState;
}

/// Ledger entry for transaction history
class LedgerEntry {
  LedgerEntry({
    required this.userId,
    required this.username,
    required this.transactionType,
    required this.amount,
    required this.timestamp,
    this.note,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
      transactionType:
          json['transaction_type'] as String? ?? json['type'] as String? ?? '',
      amount: json['amount'] as int? ?? 0,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      note: json['note'] as String?,
    );
  }
  final String userId;
  final String username;
  final String transactionType;
  final int amount;
  final DateTime timestamp;
  final String? note;
}

/// Standing entry for player standings
class StandingEntry {
  StandingEntry({
    required this.userId,
    required this.username,
    required this.buyIn,
    required this.cashOut,
    required this.netResult,
  });

  factory StandingEntry.fromJson(Map<String, dynamic> json) {
    return StandingEntry(
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
      buyIn: json['buy_in'] as int? ?? 0,
      cashOut: json['cash_out'] as int? ?? 0,
      netResult: json['net_result'] as int? ?? json['net'] as int? ?? 0,
    );
  }
  final String userId;
  final String username;
  final int buyIn;
  final int cashOut;
  final int netResult;
}
