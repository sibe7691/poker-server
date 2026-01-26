import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poker_app/models/auth_state.dart';
import 'package:poker_app/services/auth_service.dart';

/// Auth service provider
final authServiceProvider = Provider<AuthService>((ref) {
  final service = AuthService();
  ref.onDispose(service.dispose);
  return service;
});

/// Auth state notifier
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._authService) : super(AuthState.initial());
  final AuthService _authService;

  /// Initialize by loading saved auth
  Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint('AuthNotifier: Starting initialization...');
    }
    state = state.loading();
    final loadedState = await _authService.loadSavedAuth();
    state = loadedState;
    if (kIsWeb) {
      debugPrint(
        'AuthNotifier: Initialization complete - '
        'isAuthenticated: ${state.isAuthenticated}',
      );
    }
  }

  /// Register a new user
  Future<bool> register(String username, String password) async {
    state = state.loading();
    final result = await _authService.register(username, password);
    state = result;
    return result.isAuthenticated;
  }

  /// Login with credentials
  Future<bool> login(String username, String password) async {
    state = state.loading();
    final result = await _authService.login(username, password);
    state = result;
    return result.isAuthenticated;
  }

  /// Logout and clear tokens
  Future<void> logout() async {
    await _authService.logout();
    state = AuthState.initial();
  }

  /// Clear any error
  void clearError() {
    if (state.error != null) {
      state = state.copyWith();
    }
  }

  /// Refresh the access token
  /// Returns the new access token if successful, null otherwise
  Future<String?> refreshAccessToken() async {
    if (!state.isAuthenticated || state.refreshToken == null) {
      if (kIsWeb) {
        debugPrint(
          'AuthNotifier: Cannot refresh - '
          'not authenticated or no refresh token',
        );
      }
      return null;
    }

    if (kIsWeb) {
      debugPrint('AuthNotifier: Attempting to refresh access token...');
    }

    final refreshedState = await _authService.refreshTokenWithUserInfo(
      state.refreshToken!,
      state.userId!,
      state.username!,
      role: state.role,
    );

    if (refreshedState != null) {
      state = refreshedState;
      if (kIsWeb) {
        debugPrint('AuthNotifier: Token refresh successful');
      }
      return refreshedState.accessToken;
    }

    if (kIsWeb) {
      debugPrint('AuthNotifier: Token refresh failed');
    }
    return null;
  }

  /// Force update the state (used after token refresh)
  // ignore: use_setters_to_change_properties
  void updateState(AuthState newState) => state = newState;
}

/// Auth state provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});

/// Convenience provider to check if authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

/// Current user ID provider
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).userId;
});

/// Current username provider
final currentUsernameProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).username;
});

/// Is admin provider
final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAdmin;
});
