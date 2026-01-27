import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:poker_app/core/theme.dart';
import 'package:poker_app/models/card.dart';

/// A playing card widget
class PlayingCardWidget extends StatelessWidget {
  const PlayingCardWidget({
    super.key,
    this.card,
    this.isFaceDown = false,
    this.width = 60,
    this.height = 84,
    this.isHighlighted = false,
    this.onTap,
  });
  final PlayingCard? card;
  final bool isFaceDown;
  final double width;
  final double height;
  final bool isHighlighted;
  final VoidCallback? onTap;

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
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isHighlighted 
                ? PokerTheme.goldAccent 
                : (isFaceDown || card == null) 
                    ? Colors.grey.shade600 
                    : Colors.grey.shade400,
            width: isHighlighted ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isHighlighted
                  ? PokerTheme.goldAccent.withValues(alpha: 0.6)
                  : Colors.black54,
              blurRadius: isHighlighted ? 12 : 6,
              offset: const Offset(2, 3),
            ),
            if (isHighlighted)
              BoxShadow(
                color: PokerTheme.goldAccent.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: isFaceDown || card == null
              ? _buildCardBack()
              : _buildCardFace(card!),
        ),
      ),
    );
  }

  Widget _buildCardBack() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2196F3),
            Color(0xFF1565C0),
            Color(0xFF0D47A1),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Diamond pattern overlay
          Positioned.fill(
            child: CustomPaint(
              painter: _DiamondPatternPainter(),
            ),
          ),
          // Center emblem
          Center(
            child: Container(
              width: width * 0.6,
              height: height * 0.5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.15),
                    Colors.white.withValues(alpha: 0.05),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  '♠',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: width * 0.35,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          // Shine effect
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: height * 0.25,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.25),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardFace(PlayingCard card) {
    final color = Color(card.suit.color);
    final isRed = card.suit.symbol == '♥' || card.suit.symbol == '♦';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            PokerTheme.cardWhite,
            Colors.grey.shade100,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Subtle shine effect
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: height * 0.3,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.6),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Top-left rank and suit - larger and bolder
          Positioned(
            top: height * 0.04,
            left: width * 0.08,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  card.rank.code,
                  style: TextStyle(
                    color: color,
                    fontSize: width * 0.38,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    shadows: [
                      Shadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 2,
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                ),
                Text(
                  card.suit.symbol,
                  style: TextStyle(
                    color: color,
                    fontSize: width * 0.32,
                    height: 0.85,
                    shadows: [
                      Shadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 2,
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Large center suit with glow effect - positioned in bottom-right area
          Positioned(
            right: width * 0.08,
            bottom: height * 0.08,
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isRed
                    ? [
                        const Color(0xFFFF4444),
                        color,
                        const Color(0xFFCC0000),
                      ]
                    : [
                        const Color(0xFF333333),
                        color,
                        const Color(0xFF000000),
                      ],
              ).createShader(bounds),
              child: Text(
                card.suit.symbol,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: width * 0.55,
                  shadows: [
                    Shadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(2, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A mini card for compact display
class MiniCard extends StatelessWidget {
  const MiniCard({required this.card, super.key, this.size = 32});
  final PlayingCard card;
  final double size;

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
  const CommunityCards({required this.cards, super.key});
  final List<PlayingCard> cards;

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

/// Custom painter for diamond pattern on card back
class _DiamondPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const spacing = 12.0;
    for (double y = 0; y < size.height + spacing; y += spacing) {
      for (double x = 0; x < size.width + spacing; x += spacing) {
        final path = Path()
          ..moveTo(x, y - 4)
          ..lineTo(x + 4, y)
          ..lineTo(x, y + 4)
          ..lineTo(x - 4, y)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Hole cards display (player's cards)
class HoleCards extends StatelessWidget {
  const HoleCards({
    required this.cards,
    super.key,
    this.isHidden = false,
    this.isSmall = false,
  });
  final List<PlayingCard> cards;
  final bool isHidden;
  final bool isSmall;

  // Tilt angle in radians (~8 degrees)
  static const double _tiltAngle = 0.14;

  @override
  Widget build(BuildContext context) {
    final cardWidth = isSmall ? 35.0 : 60.0;
    final cardHeight = isSmall ? 49.0 : 84.0;
    final overlap = isSmall ? 25.0 : 42.0;
    // Extra height for tilted cards
    final extraHeight = cardHeight * 0.15;

    return SizedBox(
      width: cardWidth * 2 - overlap,
      height: cardHeight + extraHeight,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Left card - tilts left
          if (cards.isNotEmpty || isHidden)
            Positioned(
              left: 0,
              bottom: 0,
              child: Transform.rotate(
                angle: -_tiltAngle,
                alignment: Alignment.bottomCenter,
                child: PlayingCardWidget(
                  card: cards.isNotEmpty ? cards[0] : null,
                  isFaceDown: isHidden,
                  width: cardWidth,
                  height: cardHeight,
                ),
              ),
            ),
          // Right card - tilts right
          if (cards.length > 1 || isHidden)
            Positioned(
              right: 0,
              bottom: 0,
              child: Transform.rotate(
                angle: _tiltAngle,
                alignment: Alignment.bottomCenter,
                child: PlayingCardWidget(
                  card: cards.length > 1 ? cards[1] : null,
                  isFaceDown: isHidden,
                  width: cardWidth,
                  height: cardHeight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
