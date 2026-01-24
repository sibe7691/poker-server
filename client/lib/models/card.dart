import 'package:equatable/equatable.dart';
import '../core/constants.dart';

/// Represents a playing card
class PlayingCard extends Equatable {
  final Rank rank;
  final Suit suit;

  const PlayingCard({required this.rank, required this.suit});

  /// Parse card from server format (e.g., "Ah" = Ace of Hearts)
  factory PlayingCard.fromString(String cardStr) {
    if (cardStr.length != 2) {
      throw ArgumentError('Invalid card string: $cardStr');
    }
    return PlayingCard(
      rank: Rank.fromCode(cardStr[0]),
      suit: Suit.fromCode(cardStr[1]),
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
