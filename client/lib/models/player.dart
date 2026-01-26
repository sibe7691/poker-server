import 'package:equatable/equatable.dart';
import 'package:poker_app/models/card.dart';

/// Represents a player at the table
class Player extends Equatable {
  const Player({
    required this.userId,
    required this.username,
    required this.seat,
    required this.chips,
    this.currentBet = 0,
    this.holeCards = const [],
    this.hasCards = false,
    this.isFolded = false,
    this.isAllIn = false,
    this.isYou = false,
    this.isConnected = true,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    final cardsList =
        (json['hole_cards'] as List<dynamic>?)
            ?.map((c) => PlayingCard.fromString(c as String))
            .toList() ??
        [];

    return Player(
      userId: json['user_id'] as String,
      username: json['username'] as String,
      seat: json['seat'] as int,
      chips: json['chips'] as int,
      currentBet: json['current_bet'] as int? ?? 0,
      holeCards: cardsList,
      hasCards: json['has_cards'] as bool? ?? cardsList.isNotEmpty,
      isFolded: json['is_folded'] as bool? ?? false,
      isAllIn: json['is_all_in'] as bool? ?? false,
      isYou: json['is_you'] as bool? ?? false,
      isConnected: json['is_connected'] as bool? ?? true,
    );
  }
  final String userId;
  final String username;
  final int seat;
  final int chips;
  final int currentBet;
  final List<PlayingCard> holeCards;
  final bool hasCards;
  final bool isFolded;
  final bool isAllIn;
  final bool isYou;
  final bool isConnected;

  Player copyWith({
    String? userId,
    String? username,
    int? seat,
    int? chips,
    int? currentBet,
    List<PlayingCard>? holeCards,
    bool? hasCards,
    bool? isFolded,
    bool? isAllIn,
    bool? isYou,
    bool? isConnected,
  }) {
    return Player(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      seat: seat ?? this.seat,
      chips: chips ?? this.chips,
      currentBet: currentBet ?? this.currentBet,
      holeCards: holeCards ?? this.holeCards,
      hasCards: hasCards ?? this.hasCards,
      isFolded: isFolded ?? this.isFolded,
      isAllIn: isAllIn ?? this.isAllIn,
      isYou: isYou ?? this.isYou,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  /// Total stack (chips + current bet)
  int get totalStack => chips + currentBet;

  /// Whether this player can act
  bool get canAct => !isFolded && !isAllIn && chips > 0;

  @override
  List<Object?> get props => [
    userId,
    username,
    seat,
    chips,
    currentBet,
    holeCards,
    hasCards,
    isFolded,
    isAllIn,
    isYou,
    isConnected,
  ];
}
