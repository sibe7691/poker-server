import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/constants.dart';

/// A full-screen loading overlay with animated poker suits.
///
/// When displayed, dims the entire screen and shows an animated
/// loading indicator that cycles through the four poker suits.
class FullScreenLoadingIndicator extends StatelessWidget {
  /// Optional message to display below the loading indicator.
  final String? message;

  /// Background dim opacity (0.0 to 1.0). Defaults to 0.7.
  final double dimOpacity;

  const FullScreenLoadingIndicator({
    super.key,
    this.message,
    this.dimOpacity = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: dimOpacity),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _SuitLoadingAnimation(),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Shows the loading indicator as a modal overlay.
  ///
  /// Returns a function to dismiss the overlay.
  static OverlayEntry show(BuildContext context, {String? message}) {
    final overlay = OverlayEntry(
      builder: (context) => FullScreenLoadingIndicator(message: message),
    );
    Overlay.of(context).insert(overlay);
    return overlay;
  }
}

/// Animated loading indicator that cycles through poker suits
class _SuitLoadingAnimation extends StatefulWidget {
  const _SuitLoadingAnimation();

  @override
  State<_SuitLoadingAnimation> createState() => _SuitLoadingAnimationState();
}

class _SuitLoadingAnimationState extends State<_SuitLoadingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _rotateAnimation;

  int _currentSuitIndex = 0;

  // Order: spades, hearts, diamonds, clubs (alternating black/red)
  static const List<Suit> _suits = [
    Suit.spades,
    Suit.hearts,
    Suit.diamonds,
    Suit.clubs,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Fade out then back in
    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Scale down then back up
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.6), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Rotate during transition
    _rotateAnimation = Tween<double>(begin: 0.0, end: math.pi * 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Change suit at the midpoint of animation
    _controller.addListener(() {
      if (_controller.value >= 0.5 && _controller.value < 0.52) {
        setState(() {
          _currentSuitIndex = (_currentSuitIndex + 1) % _suits.length;
        });
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.reset();
        _controller.forward();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getSuitColor(Suit suit) {
    // Use red for hearts/diamonds, white for spades/clubs (visible on dark bg)
    return suit == Suit.hearts || suit == Suit.diamonds
        ? const Color(0xFFE53935)
        : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final suit = _suits[_currentSuitIndex];
    final color = _getSuitColor(suit);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Transform.rotate(
            angle: _rotateAnimation.value,
            child: Opacity(
              opacity: _fadeAnimation.value,
              child: Text(
                suit.symbol,
                style: TextStyle(
                  fontSize: 56,
                  color: color,
                  shadows: [
                    Shadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
