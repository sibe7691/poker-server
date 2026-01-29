import 'package:equatable/equatable.dart';

/// Authentication state
class AuthState extends Equatable {
  const AuthState({
    this.userId,
    this.username,
    this.email,
    this.role,
    this.accessToken,
    this.refreshToken,
    this.isLoading = false,
    this.error,
  });

  /// Create initial/logged out state
  factory AuthState.initial() => const AuthState();

  /// Create authenticated state
  factory AuthState.authenticated({
    required String userId,
    required String username,
    required String accessToken,
    required String refreshToken,
    String? email,
    String? role,
  }) {
    return AuthState(
      userId: userId,
      username: username,
      email: email,
      role: role,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }
  final String? userId;
  final String? username;
  final String? email;
  final String? role;
  final String? accessToken;
  final String? refreshToken;
  final bool isLoading;
  final String? error;

  /// Whether the user is authenticated
  bool get isAuthenticated => accessToken != null && userId != null;

  /// Whether the user is an admin
  bool get isAdmin => role == 'admin';

  AuthState copyWith({
    String? userId,
    String? username,
    String? email,
    String? role,
    String? accessToken,
    String? refreshToken,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      email: email ?? this.email,
      role: role ?? this.role,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  /// Create loading state
  AuthState loading() => copyWith(isLoading: true);

  /// Create error state
  AuthState withError(String message) => copyWith(
    isLoading: false,
    error: message,
  );

  @override
  List<Object?> get props => [
    userId,
    username,
    email,
    role,
    accessToken,
    refreshToken,
    isLoading,
    error,
  ];
}
