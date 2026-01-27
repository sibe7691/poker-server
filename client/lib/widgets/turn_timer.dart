import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:poker_app/core/theme.dart';

/// Circular countdown timer for turn time
class TurnTimer extends StatefulWidget {
  const TurnTimer({
    super.key,
    required this.timeRemaining,
    required this.totalTime,
    this.usingTimeBank = false,
    this.timeBank = 0,
    this.size = 48,
    this.showText = true,
  });

  /// Seconds remaining (from server)
  final double timeRemaining;

  /// Total turn time in seconds
  final int totalTime;

  /// Whether currently using time bank
  final bool usingTimeBank;

  /// Remaining time bank seconds
  final double timeBank;

  /// Size of the timer circle
  final double size;

  /// Whether to show the time text
  final bool showText;

  @override
  State<TurnTimer> createState() => _TurnTimerState();
}

class _TurnTimerState extends State<TurnTimer>
    with SingleTickerProviderStateMixin {
  late double _currentTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentTime = widget.timeRemaining;
    _startTimer();
  }

  @override
  void didUpdateWidget(TurnTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update time when server sends new value
    if ((widget.timeRemaining - _currentTime).abs() > 2) {
      _currentTime = widget.timeRemaining;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = math.max(0, _currentTime - 0.1);
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
    final progress = widget.usingTimeBank
        ? _currentTime / widget.timeBank.clamp(1, double.infinity)
        : _currentTime / widget.totalTime;

    final color = _getColor(progress);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _TimerPainter(
              progress: progress.clamp(0, 1),
              color: color,
              backgroundColor: Colors.white24,
              strokeWidth: 4,
            ),
          ),
          // Time text
          if (widget.showText)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentTime.ceil().toString(),
                  style: TextStyle(
                    color: color,
                    fontSize: widget.size * 0.35,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.usingTimeBank)
                  Text(
                    'BANK',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: widget.size * 0.15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Color _getColor(double progress) {
    if (widget.usingTimeBank) {
      return Colors.orange;
    }
    if (progress > 0.5) {
      return PokerTheme.tableFelt;
    } else if (progress > 0.25) {
      return Colors.yellow;
    } else {
      return Colors.red;
    }
  }
}

class _TimerPainter extends CustomPainter {
  _TimerPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background circle
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start from top
      2 * math.pi * progress, // Sweep angle
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_TimerPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
