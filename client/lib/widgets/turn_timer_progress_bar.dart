import 'dart:async';

import 'package:flutter/material.dart';

/// Linear progress bar for turn timer with gradient (green on right, red on left)
/// and seconds counter displayed next to it
class TurnTimerProgressBar extends StatefulWidget {
  const TurnTimerProgressBar({
    required this.timeRemaining,
    required this.totalTime,
    this.usingTimeBank = false,
    this.timeBank = 0,
    super.key,
  });

  final double timeRemaining;
  final int totalTime;
  final bool usingTimeBank;
  final double timeBank;

  @override
  State<TurnTimerProgressBar> createState() => _TurnTimerProgressBarState();
}

class _TurnTimerProgressBarState extends State<TurnTimerProgressBar> {
  late double _currentTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentTime = widget.timeRemaining;
    _startTimer();
  }

  @override
  void didUpdateWidget(TurnTimerProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update time when server sends new value (sync if difference is significant)
    if ((widget.timeRemaining - _currentTime).abs() > 2) {
      _currentTime = widget.timeRemaining;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = (_currentTime - 0.1).clamp(0.0, double.infinity);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate progress (0.0 to 1.0)
    // Progress goes from 1.0 (full time) to 0.0 (no time left)
    final progress = (_currentTime / widget.totalTime).clamp(0.0, 1.0);

    // Calculate seconds remaining
    final secondsRemaining = _currentTime.ceil();

    return Row(
      children: [
        // Padding
        const SizedBox(width: 8),

        // Progress bar
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: Colors.grey.shade800,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  // Background
                  Container(
                    width: double.infinity,
                    color: Colors.grey.shade800,
                  ),
                  // Progress with fixed-position gradient (green on right, red on left)
                  // The gradient is full-width and fixed in position
                  // As progress shrinks, we clip from the right, revealing more red on the left
                  ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.shade600, // Left (red)
                              Colors.orange.shade500, // Middle
                              Colors.green.shade600, // Right (green)
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Seconds counter
        SizedBox(
          width: 20,
          child: Text(
            '$secondsRemaining',
            style: TextStyle(
              color: widget.usingTimeBank ? Colors.orange : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
        // Padding
        const SizedBox(width: 4),
      ],
    );
  }
}
