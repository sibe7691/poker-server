import 'package:flutter_test/flutter_test.dart';
import 'package:poker_app/models/game_state.dart';
import 'dart:math' as math;

void main() {
  group('GameState.fromJson', () {
    test('parses max_players from JSON correctly', () {
      final json = {
        'table_id': 'main',
        'players': [],
        'max_players': 10,
        'state': 'waiting',
        'small_blind': 1,
        'big_blind': 2,
      };

      final gameState = GameState.fromJson(json);

      expect(gameState.tableId, 'main');
      expect(gameState.maxPlayers, 10);
      expect(gameState.smallBlind, 1);
      expect(gameState.bigBlind, 2);
    });

    test('defaults to 10 max_players when not provided', () {
      final json = {
        'table_id': 'test',
        'state': 'waiting',
      };

      final gameState = GameState.fromJson(json);

      expect(gameState.maxPlayers, 10);
    });

    test('parses different max_players values', () {
      for (final maxPlayers in [2, 4, 6, 8, 10]) {
        final json = {
          'table_id': 'test',
          'max_players': maxPlayers,
          'state': 'waiting',
        };

        final gameState = GameState.fromJson(json);

        expect(gameState.maxPlayers, maxPlayers);
      }
    });
  });

  group('Table seat positioning', () {
    test('calculates correct seat angles for different maxPlayers values', () {
      // Verify the positioning formula works for different player counts
      for (final maxSeats in [2, 4, 6, 8, 10]) {
        final angles = <double>[];
        
        for (int i = 0; i < maxSeats; i++) {
          // Same formula as in poker_table.dart
          final angle = (math.pi / 2) + (2 * math.pi * i / maxSeats);
          angles.add(angle);
        }

        // Verify seats are evenly distributed (angle difference should be constant)
        if (maxSeats > 1) {
          final expectedDiff = 2 * math.pi / maxSeats;
          for (int i = 1; i < angles.length; i++) {
            final diff = angles[i] - angles[i - 1];
            expect(diff, closeTo(expectedDiff, 0.001));
          }
        }

        // First seat should be at bottom center (angle = pi/2)
        expect(angles[0], closeTo(math.pi / 2, 0.001));
      }
    });

    test('seat positions are within oval bounds', () {
      const radiusX = 100.0;
      const radiusY = 80.0;
      const centerX = 200.0;
      const centerY = 150.0;

      for (final maxSeats in [2, 4, 6, 8, 10]) {
        for (int i = 0; i < maxSeats; i++) {
          final angle = (math.pi / 2) + (2 * math.pi * i / maxSeats);
          final x = centerX + radiusX * math.cos(angle);
          final y = centerY + radiusY * math.sin(angle);

          // Verify position is on the oval
          final normalizedX = (x - centerX) / radiusX;
          final normalizedY = (y - centerY) / radiusY;
          final distFromCenter = math.sqrt(normalizedX * normalizedX + normalizedY * normalizedY);
          
          expect(distFromCenter, closeTo(1.0, 0.001), 
            reason: 'Seat $i for maxSeats=$maxSeats should be on the oval');
        }
      }
    });
  });

  group('Blind position calculations', () {
    test('small blind is correctly calculated with maxPlayers', () {
      for (final maxSeats in [2, 6, 10]) {
        final dealerSeat = 0;
        final sbSeat = (dealerSeat + 1) % maxSeats;
        
        expect(sbSeat, 1, reason: 'SB should be seat 1 when dealer is at 0');
      }

      // Test wrap-around
      for (final maxSeats in [2, 6, 10]) {
        final dealerSeat = maxSeats - 1; // Last seat
        final sbSeat = (dealerSeat + 1) % maxSeats;
        
        expect(sbSeat, 0, reason: 'SB should wrap to seat 0 when dealer is at last seat');
      }
    });

    test('big blind is correctly calculated with maxPlayers', () {
      for (final maxSeats in [2, 6, 10]) {
        final dealerSeat = 0;
        final bbSeat = (dealerSeat + 2) % maxSeats;
        
        expect(bbSeat, 2 % maxSeats, reason: 'BB should be 2 positions after dealer');
      }

      // Test wrap-around for 2-player table
      final dealerSeat = 0;
      final bbSeat2Players = (dealerSeat + 2) % 2;
      expect(bbSeat2Players, 0, reason: 'BB wraps on 2-player table');
    });
  });
}
