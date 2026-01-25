import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_state.dart';
import '../services/auth_service.dart';

/// Auth service provider
final authServiceProvider = Provider<AuthService>((ref) {
  final service = AuthService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Auth state notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(AuthState.initial());

  /// Initialize by loading saved auth
  Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint('AuthNotifier: Starting initialization...');
    }
    state = state.loading();
    final loadedState = await _authService.loadSavedAuth();
    state = loadedState;
    if (kIsWeb) {
      debugPrint('AuthNotifier: Initialization complete - isAuthenticated: ${state.isAuthenticated}');
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
      state = state.copyWith(error: null);
    }
  }
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
