import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthRepository {
  User? get currentUser;

  Stream<AuthState> get authStateChanges;

  Future<void> sendMagicCode(String email);

  Future<AuthResponse> verifyEmailOtp(String email, String token);

  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  User? get currentUser => _client.auth.currentUser;

  @override
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  @override
  Future<void> sendMagicCode(String email) {
    return _client.auth.signInWithOtp(email: normalizeEmail(email));
  }

  @override
  Future<AuthResponse> verifyEmailOtp(String email, String token) {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      throw const AuthRepositoryException('OTP token cannot be empty.');
    }

    return _client.auth.verifyOTP(
      email: normalizeEmail(email),
      token: normalizedToken,
      type: OtpType.email,
    );
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

class AuthRepositoryException implements Exception {
  const AuthRepositoryException(this.message);

  final String message;

  @override
  String toString() => 'AuthRepositoryException: $message';
}

String normalizeEmail(String email) {
  final normalized = email.trim().toLowerCase();
  if (normalized.isEmpty || !normalized.contains('@')) {
    throw const AuthRepositoryException('A valid email is required.');
  }
  return normalized;
}
