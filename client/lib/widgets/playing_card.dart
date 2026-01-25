import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';
import '../models/card.dart';

/// A playing card widget
class PlayingCardWidget extends StatelessWidget {
  final PlayingCard? card;
  final bool isFaceDown;
  final double width;
  final double height;
  final bool isHighlighted;
  final VoidCallback? onTap;

  const PlayingCardWidget({
    super.key,
    this.card,
    this.isFaceDown = false,
    this.width = 60,
    this.height = 84,
    this.isHighlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isFaceDown || card == null
              ? PokerTheme.chipBlue
              : PokerTheme.cardWhite,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isHighlighted ? PokerTheme.goldAccent : Colors.grey.shade700,
            width: isHighlighted ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isHighlighted
                  ? PokerTheme.goldAccent.withValues(alpha: 0.5)
                  : Colors.black26,
              blurRadius: isHighlighted ? 8 : 4,
              offset: const Offset(2, 2),
            ),
          ],
        ),
        child: isFaceDown || card == null
            ? _buildCardBack()
            : _buildCardFace(card!),
      ),
    );
  }

  Widget _buildCardBack() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PokerTheme.chipBlue,
            PokerTheme.chipBlue.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: width * 0.7,
          height: height * 0.8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: const Center(
            child: Text(
              '♠♥\n♦♣',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white30,
                fontSize: 14,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardFace(PlayingCard card) {
    final color = Color(card.suit.color);

    return Stack(
      children: [
        // Top-left rank and suit
        Positioned(
          top: 0,
          left: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                card.rank.code,
                style: TextStyle(
                  color: color,
                  fontSize: width * 0.28,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
              Text(
                card.suit.symbol,
                style: TextStyle(
                  color: color,
                  fontSize: width * 0.22,
                  height: 0.9,
                ),
              ),
            ],
          ),
        ),
        // Center suit (larger)
        Center(
          child: Text(
            card.suit.symbol,
            style: TextStyle(color: color, fontSize: width * 0.45),
          ),
        ),
        // Bottom-right rank and suit (inverted)
        Positioned(
          bottom: 0,
          right: 0,
          child: Transform.rotate(
            angle: 3.14159, // 180 degrees
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  card.rank.code,
                  style: TextStyle(
                    color: color,
                    fontSize: width * 0.28,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
                Text(
                  card.suit.symbol,
                  style: TextStyle(
                    color: color,
                    fontSize: width * 0.22,
                    height: 0.9,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A mini card for compact display
class MiniCard extends StatelessWidget {
  final PlayingCard card;
  final double size;

  const MiniCard({super.key, required this.card, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final color = Color(card.suit.color);

    return Container(
      width: size,
      height: size * 1.4,
      decoration: BoxDecoration(
        color: PokerTheme.cardWhite,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade600),
      ),
      child: Center(
        child: Text(
          '${card.rank.code}${card.suit.symbol}',
          style: TextStyle(
            color: color,
            fontSize: size * 0.35,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Community cards display with animations
class CommunityCards extends StatelessWidget {
  final List<PlayingCard> cards;

  const CommunityCards({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: i < cards.length
                ? PlayingCardWidget(card: cards[i], width: 50, height: 70)
                      .animate()
                      .fadeIn(duration: 300.ms, delay: (i * 100).ms)
                      .slideY(begin: -0.3, end: 0)
                : _buildEmptySlot(),
          ),
      ],
    );
  }

  Widget _buildEmptySlot() {
    return Container(
      width: 50,
      height: 70,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
    );
  }
}

/// Hole cards display (player's cards)
class HoleCards extends StatelessWidget {
  final List<PlayingCard> cards;
  final bool isHidden;
  final bool isSmall;

  const HoleCards({
    super.key,
    required this.cards,
    this.isHidden = false,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final cardWidth = isSmall ? 35.0 : 60.0;
    final cardHeight = isSmall ? 49.0 : 84.0;
    final overlap = isSmall ? 15.0 : 25.0;

    return SizedBox(
      width: cardWidth * 2 - overlap,
      height: cardHeight,
      child: Stack(
        children: [
          if (cards.isNotEmpty || isHidden)
            Positioned(
              left: 0,
              child: PlayingCardWidget(
                card: cards.isNotEmpty ? cards[0] : null,
                isFaceDown: isHidden,
                width: cardWidth,
                height: cardHeight,
              ),
            ),
          if (cards.length > 1 || isHidden)
            Positioned(
              left: cardWidth - overlap,
              child: PlayingCardWidget(
                card: cards.length > 1 ? cards[1] : null,
                isFaceDown: isHidden,
                width: cardWidth,
                height: cardHeight,
              ),
            ),
        ],
      ),
    );
  }
}
