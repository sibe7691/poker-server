import 'package:flutter/material.dart';

/// A reusable background widget that displays the app's background image.
///
/// This widget ensures consistent background styling across all screens.
/// The background image is a dark teal gradient with a subtle vignette effect.
class AppBackground extends StatelessWidget {
  const AppBackground({
    required this.child,
    this.showOverlay = false,
    super.key,
  });

  /// The content to display on top of the background.
  final Widget child;

  /// Whether to show a subtle dark overlay for better text contrast.
  final bool showOverlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/bg.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: showOverlay
          ? Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
              ),
              child: child,
            )
          : child,
    );
  }
}
