import 'package:equatable/equatable.dart';
import 'package:poker_app/core/constants.dart';
import 'package:poker_app/models/card.dart';
import 'package:poker_app/models/player.dart';

/// Full game state from server
class GameState extends Equatable {
  const GameState({
    required this.tableId,
    required this.phase,
    this.handNumber = 0,
    this.dealerSeat = 0,
    this.smallBlind = 1,
    this.bigBlind = 2,
    this.pot = 0,
    this.maxPlayers = 10,
    this.communityCards = const [],
    this.players = const [],
    this.currentPlayerId,
    this.validActions = const [],
    this.callAmount = 0,
    this.minRaise = 0,
  });

  factory GameState.fromJson(Map<String, dynamic> json) {
    final communityCards =
        (json['community_cards'] as List<dynamic>?)
            ?.map((c) => PlayingCard.fromString(c as String))
            .toList() ??
        [];

    final players =
        (json['players'] as List<dynamic>?)
            ?.map((p) => Player.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [];

    final validActions =
        (json['valid_actions'] as List<dynamic>?)
            ?.map((a) => PlayerAction.fromString(a as String))
            .toList() ??
        [];

    return GameState(
      tableId: json['table_id'] as String,
      phase: _parsePhase(json['state'] as String?),
      handNumber: json['hand_number'] as int? ?? 0,
      dealerSeat: json['dealer_seat'] as int? ?? 0,
      smallBlind: json['small_blind'] as int? ?? 1,
      bigBlind: json['big_blind'] as int? ?? 2,
      pot: json['pot'] as int? ?? 0,
      maxPlayers: json['max_players'] as int? ?? 10,
      communityCards: communityCards,
      players: players,
      currentPlayerId: json['current_player'] as String?,
      validActions: validActions,
      callAmount: json['call_amount'] as int? ?? 0,
      minRaise: json['min_raise'] as int? ?? 0,
    );
  }
  final String tableId;
  final GamePhase phase;
  final int handNumber;
  final int dealerSeat;
  final int smallBlind;
  final int bigBlind;
  final int pot;
  final int maxPlayers;
  final List<PlayingCard> communityCards;
  final List<Player> players;
  final String? currentPlayerId;
  final List<PlayerAction> validActions;
  final int callAmount;
  final int minRaise;

  static GamePhase _parsePhase(String? state) {
    return switch (state) {
      'waiting' => GamePhase.waiting,
      'preflop' => GamePhase.preflop,
      'flop' => GamePhase.flop,
      'turn' => GamePhase.turn,
      'river' => GamePhase.river,
      'showdown' => GamePhase.showdown,
      _ => GamePhase.waiting,
    };
  }

  /// Get the current player object
  Player? get currentPlayer {
    if (currentPlayerId == null) return null;
    try {
      return players.firstWhere((p) => p.userId == currentPlayerId);
    } on Exception catch (_) {
      return null;
    }
  }

  /// Get the player marked as "you"
  Player? get me {
    for (final p in players) {
      if (p.isYou) return p;
    }
    return null;
  }

  /// Whether it's the user's turn
  bool get isMyTurn => me != null && currentPlayerId == me!.userId;

  /// Whether the game is in progress
  bool get isInProgress => phase != GamePhase.waiting;

  /// Number of active players (not folded)
  int get activePlayers => players.where((p) => !p.isFolded).length;

  GameState copyWith({
    String? tableId,
    GamePhase? phase,
    int? handNumber,
    int? dealerSeat,
    int? smallBlind,
    int? bigBlind,
    int? pot,
    int? maxPlayers,
    List<PlayingCard>? communityCards,
    List<Player>? players,
    String? currentPlayerId,
    List<PlayerAction>? validActions,
    int? callAmount,
    int? minRaise,
  }) {
    return GameState(
      tableId: tableId ?? this.tableId,
      phase: phase ?? this.phase,
      handNumber: handNumber ?? this.handNumber,
      dealerSeat: dealerSeat ?? this.dealerSeat,
      smallBlind: smallBlind ?? this.smallBlind,
      bigBlind: bigBlind ?? this.bigBlind,
      pot: pot ?? this.pot,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      communityCards: communityCards ?? this.communityCards,
      players: players ?? this.players,
      currentPlayerId: currentPlayerId ?? this.currentPlayerId,
      validActions: validActions ?? this.validActions,
      callAmount: callAmount ?? this.callAmount,
      minRaise: minRaise ?? this.minRaise,
    );
  }

  @override
  List<Object?> get props => [
    tableId,
    phase,
    handNumber,
    dealerSeat,
    smallBlind,
    bigBlind,
    pot,
    maxPlayers,
    communityCards,
    players,
    currentPlayerId,
    validActions,
    callAmount,
    minRaise,
  ];
}

/// Hand result when a hand finishes
class HandResult extends Equatable {
  const HandResult({
    required this.winners,
    required this.pot,
    this.playerCards = const {},
  });

  factory HandResult.fromJson(Map<String, dynamic> json) {
    final winners =
        (json['winners'] as List<dynamic>?)
            ?.map((w) => Winner.fromJson(w as Map<String, dynamic>))
            .toList() ??
        [];

    final playerCards = <String, List<PlayingCard>>{};
    final cardsData = json['player_cards'] as Map<String, dynamic>?;
    if (cardsData != null) {
      for (final entry in cardsData.entries) {
        final cards = (entry.value as List<dynamic>)
            .map((c) => PlayingCard.fromString(c as String))
            .toList();
        playerCards[entry.key] = cards;
      }
    }

    return HandResult(
      winners: winners,
      pot: json['pot'] as int? ?? 0,
      playerCards: playerCards,
    );
  }
  final List<Winner> winners;
  final int pot;
  final Map<String, List<PlayingCard>> playerCards;

  @override
  List<Object?> get props => [winners, pot, playerCards];
}

class Winner extends Equatable {
  const Winner({
    required this.odId,
    required this.username,
    required this.amount,
    this.handName,
  });

  factory Winner.fromJson(Map<String, dynamic> json) {
    return Winner(
      odId: json['user_id'] as String? ?? json['player_id'] as String,
      username: json['username'] as String? ?? 'Unknown',
      amount: json['amount'] as int,
      handName: json['hand_name'] as String?,
    );
  }
  final String odId;
  final String username;
  final int amount;
  final String? handName;

  @override
  List<Object?> get props => [odId, username, amount, handName];
}
