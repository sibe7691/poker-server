import 'package:equatable/equatable.dart';

/// Authentication state
class AuthState extends Equatable {
  final String? userId;
  final String? username;
  final String? accessToken;
  final String? refreshToken;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.userId,
    this.username,
    this.accessToken,
    this.refreshToken,
    this.isLoading = false,
    this.error,
  });

  /// Whether the user is authenticated
  bool get isAuthenticated => accessToken != null && userId != null;

  AuthState copyWith({
    String? userId,
    String? username,
    String? accessToken,
    String? refreshToken,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  /// Create initial/logged out state
  factory AuthState.initial() => const AuthState();

  /// Create loading state
  AuthState loading() => copyWith(isLoading: true, error: null);

  /// Create error state
  AuthState withError(String message) => copyWith(
    isLoading: false,
    error: message,
  );

  /// Create authenticated state
  factory AuthState.authenticated({
    required String userId,
    required String username,
    required String accessToken,
    required String refreshToken,
  }) {
    return AuthState(
      userId: userId,
      username: username,
      accessToken: accessToken,
      refreshToken: refreshToken,
      isLoading: false,
    );
  }

  @override
  List<Object?> get props => [
    userId, username, accessToken, refreshToken, isLoading, error
  ];
}
