import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/auth_state.dart';

class AuthService {
  // Use FlutterSecureStorage for mobile (more secure)
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: const AndroidOptions(encryptedSharedPreferences: true),
  );

  final http.Client _client = http.Client();

  /// Write to storage (platform-aware)
  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, value);
        debugPrint('Web Storage: Saved "$key"');
      } catch (e) {
        debugPrint('Web Storage: Error writing "$key": $e');
      }
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  /// Read from storage (platform-aware)
  Future<String?> _read(String key) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final value = prefs.getString(key);
        debugPrint(
          'Web Storage: Read "$key" = ${value != null ? "found" : "null"}',
        );
        return value;
      } catch (e) {
        debugPrint('Web Storage: Error reading "$key": $e');
        return null;
      }
    } else {
      return await _secureStorage.read(key: key);
    }
  }

  /// Delete from storage (platform-aware)
  Future<void> _delete(String key) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } catch (e) {
        debugPrint('Web Storage: Error deleting "$key": $e');
      }
    } else {
      await _secureStorage.delete(key: key);
    }
  }

  /// Register a new user
  Future<AuthState> register(String username, String password) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.registerEndpoint}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return _handleAuthResponse(data);
      } else {
        final error = _parseError(response);
        return AuthState.initial().withError(error);
      }
    } catch (e) {
      return AuthState.initial().withError('Connection error: $e');
    }
  }

  /// Login with existing credentials
  Future<AuthState> login(String username, String password) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.loginEndpoint}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return _handleAuthResponse(data);
      } else {
        final error = _parseError(response);
        return AuthState.initial().withError(error);
      }
    } catch (e) {
      return AuthState.initial().withError('Connection error: $e');
    }
  }

  /// Refresh the access token using stored user info
  Future<AuthState?> refreshTokenWithUserInfo(
    String refreshToken,
    String userId,
    String username, {
    String? role,
  }) async {
    try {
      if (kIsWeb) {
        debugPrint('Web: Calling refresh endpoint...');
      }
      final response = await _client.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.refreshEndpoint}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (kIsWeb) {
        debugPrint('Web: Refresh response status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Refresh endpoint may return different structure - extract what we need
        final newAccessToken = data['access_token'] as String?;
        final newRefreshToken =
            data['refresh_token'] as String? ?? refreshToken;

        if (newAccessToken == null) {
          if (kIsWeb) {
            debugPrint('Web: Refresh response missing access_token');
          }
          return null;
        }

        // Use stored user info with new tokens
        final state = AuthState.authenticated(
          userId: data['user_id'] as String? ?? userId,
          username: data['username'] as String? ?? username,
          accessToken: newAccessToken,
          refreshToken: newRefreshToken,
          role: data['role'] as String? ?? role,
        );

        // Save updated tokens
        await _write(StorageKeys.userId, state.userId!);
        await _write(StorageKeys.username, state.username!);
        await _write(StorageKeys.accessToken, state.accessToken!);
        await _write(StorageKeys.refreshToken, state.refreshToken!);
        if (state.role != null) {
          await _write(StorageKeys.role, state.role!);
        }

        return state;
      }
      if (kIsWeb) {
        debugPrint('Web: Refresh failed with status ${response.statusCode}');
      }
      return null;
    } catch (e) {
      if (kIsWeb) {
        debugPrint('Web: Refresh error: $e');
      }
      return null;
    }
  }

  /// Refresh the access token (legacy - used when user info not available)
  Future<AuthState?> refreshToken(String refreshToken) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.refreshEndpoint}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return _handleAuthResponse(data);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Handle successful auth response and persist tokens
  Future<AuthState> _handleAuthResponse(Map<String, dynamic> data) async {
    final state = AuthState.authenticated(
      userId: data['user_id'] as String,
      username: data['username'] as String,
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      role: data['role'] as String?,
    );

    // Persist to storage (uses SharedPreferences on web, SecureStorage on mobile)
    await _write(StorageKeys.userId, state.userId!);
    await _write(StorageKeys.username, state.username!);
    await _write(StorageKeys.accessToken, state.accessToken!);
    await _write(StorageKeys.refreshToken, state.refreshToken!);
    if (state.role != null) {
      await _write(StorageKeys.role, state.role!);
    }

    if (kIsWeb) {
      debugPrint('Web: Auth tokens saved to localStorage');
    }

    return state;
  }

  /// Load saved auth state from storage
  Future<AuthState> loadSavedAuth() async {
    try {
      if (kIsWeb) {
        debugPrint('=== Web Auth Load Start ===');
      }

      final userId = await _read(StorageKeys.userId);
      final username = await _read(StorageKeys.username);
      final accessToken = await _read(StorageKeys.accessToken);
      final refreshToken = await _read(StorageKeys.refreshToken);
      final role = await _read(StorageKeys.role);

      if (kIsWeb) {
        debugPrint(
          'Web: userId=${userId != null}, username=${username != null}, accessToken=${accessToken != null}, refreshToken=${refreshToken != null}, role=$role',
        );
      }

      if (userId != null &&
          username != null &&
          accessToken != null &&
          refreshToken != null) {
        if (kIsWeb) {
          debugPrint('Web: All tokens present, attempting refresh...');
        }
        // Try to refresh the token to ensure it's still valid
        final refreshed = await refreshTokenWithUserInfo(
          refreshToken,
          userId,
          username,
          role: role,
        );
        if (refreshed != null) {
          if (kIsWeb) {
            debugPrint('Web: Token refresh SUCCESS - user restored');
          }
          return refreshed;
        }
        // If refresh failed but we have tokens, try using existing token
        // (server might still accept it if not expired)
        if (kIsWeb) {
          debugPrint('Web: Token refresh failed, using cached auth state');
        }
        return AuthState.authenticated(
          userId: userId,
          username: username,
          accessToken: accessToken,
          refreshToken: refreshToken,
          role: role,
        );
      } else {
        if (kIsWeb) {
          debugPrint('Web: No saved tokens found - user needs to log in');
        }
      }
      return AuthState.initial();
    } catch (e, stack) {
      if (kIsWeb) {
        debugPrint('Web: ERROR loading saved auth: $e');
        debugPrint('Web: Stack: $stack');
      }
      return AuthState.initial();
    }
  }

  /// Clear all saved auth data
  Future<void> logout() async {
    await _delete(StorageKeys.userId);
    await _delete(StorageKeys.username);
    await _delete(StorageKeys.accessToken);
    await _delete(StorageKeys.refreshToken);
    await _delete(StorageKeys.role);
    if (kIsWeb) {
      debugPrint('Web: Auth tokens cleared from localStorage');
    }
  }

  String _parseError(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      return data['detail'] ?? data['message'] ?? 'Unknown error';
    } catch (_) {
      return 'Error: ${response.statusCode}';
    }
  }

  void dispose() {
    _client.close();
  }
}
