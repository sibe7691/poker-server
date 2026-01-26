import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/table_info.dart';
import '../../providers/providers.dart';
import '../../services/websocket_service.dart';
import '../../widgets/widgets.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  List<TableInfo> _tables = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Defer to after the widget tree is built to avoid modifying provider during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectAndLoadTables();
    });
  }

  Future<void> _connectAndLoadTables() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final gameController = ref.read(gameControllerProvider.notifier);
      await gameController.connectAndAuth();

      if (!mounted) return;

      // Give time for authentication
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // Fetch tables list
      final tables = await gameController.fetchTables();
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to connect: $e';
        _isLoading = false;
      });
    }
  }

  void _viewTable(TableInfo table) {
    // Navigate to view the table without joining yet
    // The user will select a seat to join the table
    context.go('/game/${table.tableId}');
  }

  void _deleteTable(TableInfo table) {
    final gameController = ref.read(gameControllerProvider.notifier);
    gameController.deleteTable(table.tableId);

    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Table "${table.name}" deleted'),
        backgroundColor: PokerTheme.tableFelt,
      ),
    );
  }

  void _logout() async {
    final authNotifier = ref.read(authProvider.notifier);
    final gameController = ref.read(gameControllerProvider.notifier);

    await gameController.disconnect();
    await authNotifier.logout();

    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = ref.watch(currentUsernameProvider);

    // Listen for tables updates
    ref.listen(tablesListProvider, (previous, next) {
      next.whenData((tables) {
        setState(() {
          _tables = tables;
          _isLoading = false;
        });
      });
    });

    // Listen for errors
    ref.listen(wsErrorProvider, (previous, next) {
      next.whenData((error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      });
    });

    // Listen for connection status
    ref.listen(connectionStatusProvider, (previous, next) {
      next.whenData((status) {
        if (status == ConnectionStatus.authenticated) {
          setState(() => _isLoading = false);
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seven Deuce Lobby'),
        actions: [
          if (username != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  username,
                  style: const TextStyle(
                    color: PokerTheme.goldAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _connectAndLoadTables,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-table'),
        icon: const Icon(Icons.add),
        label: const Text('Create Table'),
        backgroundColor: PokerTheme.goldAccent,
        foregroundColor: Colors.black,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const FullScreenLoadingIndicator(
        message: 'Connecting to server...',
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: PokerTheme.chipRed,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _connectAndLoadTables,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_tables.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.table_restaurant, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            const Text(
              'No tables available',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Wait for an admin to create a table',
              style: TextStyle(color: Colors.white38),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _connectAndLoadTables,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        final tables = await ref
            .read(gameControllerProvider.notifier)
            .fetchTables();
        if (mounted) {
          setState(() {
            _tables = tables;
          });
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tables.length,
        itemBuilder: (context, index) {
          final table = _tables[index];
          return _TableCard(
            table: table,
            onJoin: () => _viewTable(table),
            onDelete: () => _deleteTable(table),
          );
        },
      ),
    );
  }
}

class _TableCard extends ConsumerWidget {
  final TableInfo table;
  final VoidCallback onJoin;
  final VoidCallback onDelete;

  const _TableCard({
    required this.table,
    required this.onJoin,
    required this.onDelete,
  });

  void _showContextMenu(BuildContext context, Offset position, bool isAdmin) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (isAdmin)
          const PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Text('Delete Table', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == 'delete') {
        _showDeleteConfirmation(context);
      }
    });
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Table'),
        content: Text(
          'Are you sure you want to delete "${table.name}"?\n\n'
          'This will remove all players from the table.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        onDelete();
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isFull = !table.hasSeats;
    final bool isAdmin = ref.watch(isAdminProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onLongPressStart: isAdmin
            ? (details) =>
                _showContextMenu(context, details.globalPosition, isAdmin)
            : null,
        child: InkWell(
          onTap: isFull ? null : onJoin,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Table icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: table.state == 'waiting'
                        ? PokerTheme.tableFelt.withValues(alpha: 0.2)
                        : PokerTheme.goldAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.table_restaurant,
                    color: table.state == 'waiting'
                        ? PokerTheme.tableFelt
                        : PokerTheme.goldAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                // Table info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        table.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _InfoChip(
                            icon: Icons.people,
                            label: table.playersDisplay,
                            color: isFull ? Colors.red : Colors.green,
                          ),
                          const SizedBox(width: 8),
                          _InfoChip(
                            icon: Icons.attach_money,
                            label: table.blindsDisplay,
                            color: PokerTheme.goldAccent,
                          ),
                          const SizedBox(width: 8),
                          _InfoChip(
                            icon: table.state == 'waiting'
                                ? Icons.hourglass_empty
                                : Icons.play_arrow,
                            label: table.state.toUpperCase(),
                            color: table.state == 'waiting'
                                ? Colors.white54
                                : PokerTheme.tableFelt,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
