import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poker_app/core/theme.dart';
import 'package:poker_app/models/table_info.dart';
import 'package:poker_app/providers/providers.dart';
import 'package:poker_app/widgets/widgets.dart';

// Fire-and-forget futures are intentional in callbacks and event handlers
// ignore_for_file: discarded_futures

const _loadingMessages = [
  'Shuffling the deck...',
  'Dealing the cards...',
  'Setting the table...',
  'Stacking the chips...',
  'Cutting the deck...',
  'Warming up the felt...',
  'Counting the chips...',
  'Breaking the seal...',
  'Riffling the cards...',
];

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen>
    with SingleTickerProviderStateMixin {
  List<TableInfo> _tables = [];
  bool _isLoading = true;
  String? _error;
  final String _loadingMessage =
      _loadingMessages[Random().nextInt(_loadingMessages.length)];
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Defer to after the widget tree is built to avoid modifying provider
    // during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectAndLoadTables();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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
      await Future<void>.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // Fetch tables list
      final tables = await gameController.fetchTables();
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _isLoading = false;
      });
    } on Exception catch (e) {
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
    ref.read(gameControllerProvider.notifier).deleteTable(table.tableId);

    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Table "${table.name}" deleted'),
        backgroundColor: PokerTheme.tableFelt,
      ),
    );
  }

  Future<void> _logout() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PokerTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final authNotifier = ref.read(authProvider.notifier);
    final gameController = ref.read(gameControllerProvider.notifier);

    await gameController.disconnect();
    await authNotifier.logout();

    if (mounted) {
      context.go('/login');
    }
  }

  void _openProfile() {
    context.go('/profile');
  }

  @override
  Widget build(BuildContext context) {
    final username = ref.watch(currentUsernameProvider);
    final isAdmin = ref.watch(isAdminProvider);

    // Listen for tables updates
    ref
      ..listen(tablesListProvider, (previous, next) {
        next.whenData((tables) {
          setState(() {
            _tables = tables;
            _isLoading = false;
          });
        });
      })
      // Listen for errors
      ..listen(wsErrorProvider, (previous, next) {
        next.whenData((error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.red),
          );
        });
      })
      // Listen for connection status changes (for potential
      // reconnection handling)
      ..listen(connectionStatusProvider, (previous, next) {
        // Don't set _isLoading = false here - wait for tables to be fetched
        // This prevents showing the empty state before the
        // initial load completes
      });

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1B4D3E), // Deep poker green
              Color(0xFF0D2818), // Darker forest green
              Color(0xFF071510), // Near black green
            ],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _LobbyHeader(
                username: username,
                isAdmin: isAdmin,
                onLogout: _logout,
                onProfile: _openProfile,
                onCreateTable: () => context.push('/create-table'),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _connectAndLoadTables,
        backgroundColor: PokerTheme.tableFelt,
        child: const Icon(Icons.refresh_rounded, color: Colors.white),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return FullScreenLoadingIndicator(
        message: _loadingMessage,
      );
    }

    if (_error != null) {
      return _ErrorState(
        error: _error!,
        onRetry: _connectAndLoadTables,
      );
    }

    if (_tables.isEmpty) {
      return _EmptyState(
        onRefresh: _connectAndLoadTables,
        pulseController: _pulseController,
      );
    }

    final activeTables = _tables.where((t) => t.state != 'waiting').toList();
    final waitingTables = _tables.where((t) => t.state == 'waiting').toList();

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
      color: PokerTheme.goldAccent,
      backgroundColor: PokerTheme.surfaceDark,
      child: CustomScrollView(
        slivers: [
          // Create table CTA for admins
          if (ref.watch(isAdminProvider))
            SliverToBoxAdapter(
              child: _CreateTableCTA(
                onPressed: () => context.push('/create-table'),
              ),
            ),

          // Active games section
          if (activeTables.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Live Games',
                icon: Icons.play_circle_filled,
                iconColor: Colors.greenAccent,
                count: activeTables.length,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final table = activeTables[index];
                    return _ModernTableCard(
                      table: table,
                      onJoin: () => _viewTable(table),
                      onDelete: () => _deleteTable(table),
                      isLive: true,
                    );
                  },
                  childCount: activeTables.length,
                ),
              ),
            ),
          ],

          // Waiting tables section
          if (waitingTables.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Open Tables',
                icon: Icons.hourglass_empty,
                iconColor: Colors.white54,
                count: waitingTables.length,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final table = waitingTables[index];
                    return _ModernTableCard(
                      table: table,
                      onJoin: () => _viewTable(table),
                      onDelete: () => _deleteTable(table),
                      isLive: false,
                    );
                  },
                  childCount: waitingTables.length,
                ),
              ),
            ),
          ],

          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 100),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// LOBBY HEADER
// ============================================================================

class _LobbyHeader extends StatelessWidget {
  const _LobbyHeader({
    required this.username,
    required this.isAdmin,
    required this.onLogout,
    required this.onProfile,
    required this.onCreateTable,
  });

  final String? username;
  final bool isAdmin;
  final VoidCallback onLogout;
  final VoidCallback onProfile;
  final VoidCallback onCreateTable;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A3D2E).withValues(alpha: 0.95),
            const Color(0xFF0F2A1D),
          ],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/images/seven-deuce-logo.png',
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 14),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Seven Deuce',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'POKER CLUB',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: PokerTheme.goldAccent.withValues(alpha: 0.9),
                    letterSpacing: 3,
                  ),
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 8),
                  _CreateTableButton(onPressed: onCreateTable),
                ],
              ],
            ),
          ),
          // User info and menu on the right
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // User info
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isAdmin) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: PokerTheme.goldAccent.withValues(
                              alpha: 0.2,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: PokerTheme.goldAccent.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          child: const Text(
                            'ADMIN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: PokerTheme.goldAccent,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        username ?? 'Guest',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Welcome back!',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      PokerTheme.goldAccent,
                      PokerTheme.goldAccent.withValues(alpha: 0.7),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: PokerTheme.goldAccent.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    (username ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _HeaderMenuButton(
                onProfile: onProfile,
                onLogout: onLogout,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderMenuButton extends StatelessWidget {
  const _HeaderMenuButton({
    required this.onProfile,
    required this.onLogout,
  });

  final VoidCallback onProfile;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'profile':
              onProfile();
            case 'logout':
              onLogout();
          }
        },
        offset: const Offset(0, 48),
        color: PokerTheme.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        itemBuilder: (context) => [
          const PopupMenuItem<String>(
            value: 'profile',
            child: Row(
              children: [
                Icon(
                  Icons.person_outline,
                  color: Colors.white70,
                  size: 20,
                ),
                SizedBox(width: 12),
                Text(
                  'Profile',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                Icon(
                  Icons.logout_rounded,
                  color: Colors.redAccent,
                  size: 20,
                ),
                SizedBox(width: 12),
                Text(
                  'Log Out',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ],
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.all(10),
          child: const Icon(
            Icons.menu_rounded,
            color: Colors.white70,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _CreateTableButton extends StatelessWidget {
  const _CreateTableButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                PokerTheme.goldAccent,
                Color(0xFFE5C100),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: PokerTheme.goldAccent.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: Colors.black87, size: 20),
              SizedBox(width: 6),
              Text(
                'New Table',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CREATE TABLE CTA
// ============================================================================

class _CreateTableCTA extends StatelessWidget {
  const _CreateTableCTA({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2E8B57), // Sea green
                  Color(0xFF228B22), // Forest green
                  Color(0xFF1B6B3E), // Darker green
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2E8B57).withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Background pattern
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CustomPaint(
                      painter: _TablePatternPainter(),
                    ),
                  ),
                ),
                // Content
                Row(
                  children: [
                    // Poker table illustration
                    SizedBox(
                      width: 130,
                      child: _PokerTableIllustration(),
                    ),
                    // Text
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CREATE NEW TABLE',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2,
                                shadows: [
                                  Shadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(1, 2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Start a new poker game',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Arrow icon
                    Container(
                      margin: const EdgeInsets.only(right: 16),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PokerTableIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Table surface
        Positioned(
          bottom: 15,
          child: Container(
            width: 85,
            height: 55,
            decoration: BoxDecoration(
              color: const Color(0xFF1B5E20),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: const Color(0xFF8B4513),
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
        ),
        // Chairs around the table
        ..._buildChairs(),
        // Chips stack
        Positioned(
          bottom: 30,
          left: 55,
          child: _ChipStack(),
        ),
      ],
    );
  }

  List<Widget> _buildChairs() {
    return [
      // Top chair
      Positioned(
        top: 8,
        child: _Chair(),
      ),
      // Bottom left chair
      Positioned(
        bottom: 8,
        left: 20,
        child: _Chair(),
      ),
      // Bottom right chair
      Positioned(
        bottom: 8,
        right: 20,
        child: _Chair(),
      ),
      // Left chair
      Positioned(
        left: 8,
        top: 35,
        child: _Chair(),
      ),
      // Right chair
      Positioned(
        right: 8,
        top: 35,
        child: _Chair(),
      ),
    ];
  }
}

class _Chair extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: const Color(0xFFDEB887),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF8B7355),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

class _ChipStack extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 40,
      child: Stack(
        children: [
          // Bottom chip (blue)
          Positioned(
            bottom: 0,
            left: 0,
            child: _Chip(color: Colors.blue.shade700),
          ),
          // Middle chip (red)
          Positioned(
            bottom: 6,
            left: 3,
            child: _Chip(color: Colors.red.shade700),
          ),
          // Top chip (gold)
          const Positioned(
            bottom: 12,
            left: 1,
            child: _Chip(color: Color(0xFFFFD700)),
          ),
          // Extra top chip (green)
          Positioned(
            bottom: 18,
            left: 4,
            child: _Chip(color: Colors.green.shade600),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

class _TablePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;

    // Draw subtle diagonal lines
    for (var i = -size.height; i < size.width + size.height; i += 30) {
      final path = Path()
        ..moveTo(i, 0)
        ..lineTo(i + size.height, size.height)
        ..lineTo(i + size.height + 10, size.height)
        ..lineTo(i + 10, 0)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// SECTION HEADER
// ============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.count,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: iconColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MODERN TABLE CARD
// ============================================================================

class _ModernTableCard extends ConsumerWidget {
  const _ModernTableCard({
    required this.table,
    required this.onJoin,
    required this.onDelete,
    required this.isLive,
  });

  final TableInfo table;
  final VoidCallback onJoin;
  final VoidCallback onDelete;
  final bool isLive;

  void _showContextMenu(BuildContext context, Offset position, bool isAdmin) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: PokerTheme.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        if (isAdmin)
          const PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                SizedBox(width: 10),
                Text('Delete Table', style: TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == 'delete' && context.mounted) {
        _showDeleteConfirmation(context);
      }
    });
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PokerTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) {
      if ((confirmed ?? false) && context.mounted) {
        onDelete();
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFull = !table.hasSeats;
    final isAdmin = ref.watch(isAdminProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onLongPressStart: isAdmin
            ? (details) =>
                  _showContextMenu(context, details.globalPosition, isAdmin)
            : null,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: isFull ? null : onJoin,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isLive
                      ? [
                          const Color(0xFF1E3A2F),
                          const Color(0xFF152A22),
                        ]
                      : [
                          const Color(0xFF1A2E25),
                          const Color(0xFF12211A),
                        ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isLive
                      ? PokerTheme.tableFelt.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.08),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isLive
                        ? PokerTheme.tableFelt.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Table visual
                    _TableVisual(
                      isLive: isLive,
                      playerCount: table.playerCount,
                    ),
                    const SizedBox(width: 16),

                    // Table info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  table.name,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isLive)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: Colors.greenAccent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'LIVE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.greenAccent,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Info chips row
                          Row(
                            children: [
                              _TableInfoChip(
                                icon: Icons.people_alt_outlined,
                                label: table.playersDisplay,
                                color: isFull
                                    ? Colors.redAccent
                                    : Colors.white70,
                                isFull: isFull,
                              ),
                              const SizedBox(width: 12),
                              _TableInfoChip(
                                icon: Icons.monetization_on_outlined,
                                label: table.blindsDisplay,
                                color: PokerTheme.goldAccent,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Join arrow
                    if (!isFull) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: PokerTheme.goldAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.arrow_forward_ios,
                          color: PokerTheme.goldAccent,
                          size: 16,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'FULL',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TableVisual extends StatelessWidget {
  const _TableVisual({
    required this.isLive,
    required this.playerCount,
  });

  final bool isLive;
  final int playerCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: isLive
              ? [
                  const Color(0xFF3D8B40),
                  const Color(0xFF2E7D32),
                  const Color(0xFF1B5E20),
                ]
              : [
                  const Color(0xFF4A4A4A),
                  const Color(0xFF3A3A3A),
                  const Color(0xFF2A2A2A),
                ],
          stops: const [0.0, 0.6, 1.0],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLive
              ? const Color(0xFF6B4423)
              : Colors.white.withValues(alpha: 0.1),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: isLive
                ? PokerTheme.tableFelt.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Player count indicator
          Text(
            playerCount.toString(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isLive ? Colors.white : Colors.white60,
              shadows: const [
                Shadow(
                  color: Colors.black38,
                  blurRadius: 4,
                  offset: Offset(1, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableInfoChip extends StatelessWidget {
  const _TableInfoChip({
    required this.icon,
    required this.label,
    required this.color,
    this.isFull = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isFull;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EMPTY STATE
// ============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onRefresh,
    required this.pulseController,
  });

  final VoidCallback onRefresh;
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated poker table illustration
            AnimatedBuilder(
              animation: pulseController,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (pulseController.value * 0.05),
                  child: child,
                );
              },
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      PokerTheme.tableFelt.withValues(alpha: 0.3),
                      PokerTheme.tableFelt.withValues(alpha: 0.1),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: PokerTheme.surfaceLight,
                      border: Border.all(
                        color: PokerTheme.tableFelt.withValues(alpha: 0.5),
                        width: 3,
                      ),
                    ),
                    child: const Icon(
                      Icons.casino_outlined,
                      size: 36,
                      color: Colors.white38,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'No Tables Yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Wait for an admin to create a table,\n'
              'or refresh to check for new games.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                foregroundColor: PokerTheme.goldAccent,
                side: BorderSide(
                  color: PokerTheme.goldAccent.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ERROR STATE
// ============================================================================

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.error,
    required this.onRetry,
  });

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Error icon with glow
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.redAccent.withValues(alpha: 0.3),
                    Colors.redAccent.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PokerTheme.surfaceLight,
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 28,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Connection Failed',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: PokerTheme.tableFelt,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
