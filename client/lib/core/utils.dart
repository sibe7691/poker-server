import 'package:flutter/material.dart';

/// Format chip count with K/M suffixes
String formatChips(int chips) {
  if (chips >= 1000000) {
    return '${(chips / 1000000).toStringAsFixed(1)}M';
  } else if (chips >= 10000) {
    return '${(chips / 1000).toStringAsFixed(1)}K';
  }
  return chips.toString();
}

/// Format currency amount
String formatCurrency(int amount) {
  return '\$${formatChips(amount)}';
}

/// Show a snackbar message
void showMessage(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : null,
      duration: Duration(seconds: isError ? 4 : 2),
    ),
  );
}

/// Parse card string (e.g., "Ah" -> Ace of Hearts)
(String rank, String suit) parseCardString(String card) {
  if (card.length != 2) return ('?', '?');
  return (card[0], card[1]);
}

/// Get position name for seat relative to dealer
String getPositionName(int seat, int dealerSeat, int playerCount) {
  if (playerCount < 2) return '';
  
  final relativePos = (seat - dealerSeat + playerCount) % playerCount;
  
  if (relativePos == 0) return 'BTN';
  if (relativePos == 1) return 'SB';
  if (relativePos == 2) return 'BB';
  if (playerCount >= 4 && relativePos == playerCount - 1) return 'CO';
  if (playerCount >= 5 && relativePos == playerCount - 2) return 'HJ';
  if (playerCount >= 6 && relativePos == playerCount - 3) return 'LJ';
  if (relativePos == 3) return 'UTG';
  return 'MP';
}

/// Debouncer for action buttons
class Debouncer {
  final Duration delay;
  DateTime? _lastCall;

  Debouncer({this.delay = const Duration(milliseconds: 500)});

  bool call() {
    final now = DateTime.now();
    if (_lastCall == null || now.difference(_lastCall!) > delay) {
      _lastCall = now;
      return true;
    }
    return false;
  }
}

/// Extension for nullable strings
extension StringExtension on String? {
  bool get isNullOrEmpty => this == null || this!.isEmpty;
  bool get isNotNullOrEmpty => !isNullOrEmpty;
}
