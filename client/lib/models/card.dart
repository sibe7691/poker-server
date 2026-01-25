import 'package:equatable/equatable.dart';
import '../core/constants.dart';

/// Represents a playing card
class PlayingCard extends Equatable {
  final Rank rank;
  final Suit suit;

  const PlayingCard({required this.rank, required this.suit});

  /// Parse card from server format (e.g., "Ah" = Ace of Hearts, "10s" = 10 of Spades)
  factory PlayingCard.fromString(String cardStr) {
    if (cardStr.length < 2 || cardStr.length > 3) {
      throw ArgumentError('Invalid card string: $cardStr');
    }
    // Suit is always the last character, rank is everything before it
    final suitCode = cardStr[cardStr.length - 1];
    final rankCode = cardStr.substring(0, cardStr.length - 1);
    return PlayingCard(
      rank: Rank.fromCode(rankCode),
      suit: Suit.fromCode(suitCode),
    );
  }

  /// Display string (e.g., "A♥")
  String get display => '${rank.code}${suit.symbol}';

  /// Server format (e.g., "Ah")
  String get serverFormat => '${rank.code}${suit.code}';

  /// Whether this is a red card
  bool get isRed => suit == Suit.hearts || suit == Suit.diamonds;

  @override
  List<Object?> get props => [rank, suit];

  @override
  String toString() => display;
}

/// Represents a face-down card
class HiddenCard extends PlayingCard {
  const HiddenCard() : super(rank: Rank.two, suit: Suit.spades);

  @override
  String get display => '??';

  @override
  bool get isRed => false;
}
