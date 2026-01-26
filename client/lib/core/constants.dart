/// API and WebSocket configuration
class ApiConstants {
  static const String baseUrl = 'http://localhost:8765';
  static const String wsUrl = 'ws://localhost:8765/ws';

  // HTTP Endpoints
  static const String registerEndpoint = '/api/register';
  static const String loginEndpoint = '/api/login';
  static const String refreshEndpoint = '/api/refresh';
  static const String tablesEndpoint = '/api/tables';
  static const String standingsEndpoint = '/api/standings';
}

/// Card suits
enum Suit {
  hearts('h', '♥', 0xFFE53935),
  diamonds('d', '♦', 0xFFE53935),
  clubs('c', '♣', 0xFF212121),
  spades('s', '♠', 0xFF212121)
  ;

  const Suit(this.code, this.symbol, this.color);

  final String code;
  final String symbol;
  final int color;

  static Suit fromCode(String code) {
    return Suit.values.firstWhere(
      (s) => s.code == code.toLowerCase(),
      orElse: () => Suit.spades,
    );
  }
}

/// Card ranks
enum Rank {
  two('2', 2),
  three('3', 3),
  four('4', 4),
  five('5', 5),
  six('6', 6),
  seven('7', 7),
  eight('8', 8),
  nine('9', 9),
  ten('T', 10),
  jack('J', 11),
  queen('Q', 12),
  king('K', 13),
  ace('A', 14)
  ;

  const Rank(this.code, this.value);

  final String code;
  final int value;

  static Rank fromCode(String code) {
    // Handle "10" from server as equivalent to "T"
    final normalizedCode = code == '10' ? 'T' : code.toUpperCase();
    return Rank.values.firstWhere(
      (r) => r.code == normalizedCode,
      orElse: () => Rank.two,
    );
  }
}

/// Game states
enum GamePhase { waiting, preflop, flop, turn, river, showdown }

/// Player actions
enum PlayerAction {
  fold,
  check,
  call,
  bet,
  raise,
  allIn('all_in')
  ;

  const PlayerAction([String? v]) : value = v ?? '';

  final String value;

  String get serverValue => value.isNotEmpty ? value : name;

  static PlayerAction fromString(String s) {
    if (s == 'all_in') return PlayerAction.allIn;
    return PlayerAction.values.firstWhere(
      (a) => a.name == s,
      orElse: () => PlayerAction.fold,
    );
  }
}

/// Storage keys
class StorageKeys {
  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String userId = 'user_id';
  static const String username = 'username';
  static const String role = 'role';
}
