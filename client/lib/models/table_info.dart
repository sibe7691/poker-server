import 'package:equatable/equatable.dart';

/// Table information for lobby display
class TableInfo extends Equatable {
  final String tableId;
  final String name;
  final int playerCount;
  final int maxPlayers;
  final String state;
  final int smallBlind;
  final int bigBlind;

  const TableInfo({
    required this.tableId,
    required this.name,
    required this.playerCount,
    required this.maxPlayers,
    this.state = 'waiting',
    required this.smallBlind,
    required this.bigBlind,
  });

  factory TableInfo.fromJson(Map<String, dynamic> json) {
    return TableInfo(
      tableId: json['table_id'] as String,
      name: json['name'] as String? ?? json['table_id'] as String? ?? 'Table',
      playerCount: json['players'] as int? ?? json['player_count'] as int? ?? 0,
      maxPlayers: json['max_players'] as int? ?? 10,
      state: json['state'] as String? ?? 'waiting',
      smallBlind: json['small_blind'] as int? ?? 1,
      bigBlind: json['big_blind'] as int? ?? 2,
    );
  }

  /// Display string for blinds
  String get blindsDisplay => '$smallBlind/$bigBlind';

  /// Whether the table has available seats
  bool get hasSeats => playerCount < maxPlayers;

  /// Display for player count
  String get playersDisplay => '$playerCount/$maxPlayers';

  @override
  List<Object?> get props => [
    tableId,
    name,
    playerCount,
    maxPlayers,
    state,
    smallBlind,
    bigBlind,
  ];
}
