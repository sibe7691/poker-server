import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/game/game_screen.dart';
import 'features/lobby/create_table_screen.dart';
import 'features/lobby/lobby_screen.dart';
import 'providers/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations (skip on web where it's not supported)
  if (!kIsWeb) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Set system UI overlay style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: PokerTheme.darkBackground,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  runApp(const ProviderScope(child: PokerApp()));
}

class PokerApp extends ConsumerStatefulWidget {
  const PokerApp({super.key});

  @override
  ConsumerState<PokerApp> createState() => _PokerAppState();
}

/// Notifier that triggers GoRouter refresh when auth state changes
class AuthChangeNotifier extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool _initialized = false;

  bool get initialized => _initialized;

  void update({required bool isAuthenticated, required bool initialized}) {
    if (_isAuthenticated != isAuthenticated || _initialized != initialized) {
      _isAuthenticated = isAuthenticated;
      _initialized = initialized;
      notifyListeners();
    }
  }
}

class _PokerAppState extends ConsumerState<PokerApp> {
  late final GoRouter _router;
  late final AuthChangeNotifier _authNotifier;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _authNotifier = AuthChangeNotifier();
    _setupRouter();
    // Defer initialization to after the first frame to avoid setState during mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAuth();
    });
  }

  @override
  void dispose() {
    _authNotifier.dispose();
    super.dispose();
  }

  Future<void> _initializeAuth() async {
    if (kIsWeb) debugPrint('Main: Starting auth initialization...');
    await ref.read(authProvider.notifier).initialize();
    if (mounted) {
      final isAuth = ref.read(isAuthenticatedProvider);
      if (kIsWeb) {
        debugPrint('Main: Auth init complete - isAuthenticated: $isAuth');
      }
      setState(() => _initialized = true);
      // Notify the router that auth state has changed
      _authNotifier.update(isAuthenticated: isAuth, initialized: true);
      if (kIsWeb) {
        debugPrint('Main: Router notified, should redirect if authenticated');
      }
    }
  }

  void _setupRouter() {
    _router = GoRouter(
      initialLocation: '/login',
      refreshListenable: _authNotifier,
      redirect: (context, state) {
        if (!_initialized) {
          if (kIsWeb) debugPrint('Router: Not initialized yet, no redirect');
          return null;
        }

        final isAuthenticated = ref.read(isAuthenticatedProvider);
        final location = state.matchedLocation;
        final isLoginRoute = location == '/login';
        final isRootRoute = location == '/';

        if (kIsWeb) {
          debugPrint(
            'Router: Checking redirect - isAuth: $isAuthenticated, route: $location',
          );
        }

        if (!isAuthenticated && !isLoginRoute) {
          if (kIsWeb) {
            debugPrint('Router: Redirecting to /login (not authenticated)');
          }
          return '/login';
        }
        if (isAuthenticated && (isLoginRoute || isRootRoute)) {
          if (kIsWeb) {
            debugPrint(
              'Router: Redirecting to /lobby (authenticated on login/root)',
            );
          }
          return '/lobby';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/lobby',
          builder: (context, state) => const LobbyScreen(),
        ),
        GoRoute(
          path: '/create-table',
          builder: (context, state) => const CreateTableScreen(),
        ),
        GoRoute(
          path: '/game/:tableId',
          builder: (context, state) {
            final tableId = state.pathParameters['tableId'] ?? 'main';
            return GameScreen(tableId: tableId);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch auth state and update notifier to trigger router refresh
    final authState = ref.watch(authProvider);
    _authNotifier.update(
      isAuthenticated: authState.isAuthenticated,
      initialized: _initialized,
    );

    if (!_initialized) {
      return MaterialApp(
        theme: PokerTheme.darkTheme,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: PokerTheme.goldAccent),
          ),
        ),
      );
    }

    return MaterialApp.router(
      title: 'Poker',
      theme: PokerTheme.darkTheme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
