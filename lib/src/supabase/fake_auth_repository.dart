import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({String? signedInUserId, String? signedInEmail})
    : _authStateController = StreamController<AuthState>.broadcast() {
    if (signedInUserId != null) {
      _currentUser = fakeUser(
        id: signedInUserId,
        email: signedInEmail ?? 'fake@example.test',
      );
    }
  }

  final StreamController<AuthState> _authStateController;
  final List<String> sentMagicCodeEmails = [];
  User? _currentUser;

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<AuthState> get authStateChanges => _authStateController.stream;

  @override
  Future<void> sendMagicCode(String email) async {
    sentMagicCodeEmails.add(normalizeEmail(email));
  }

  @override
  Future<AuthResponse> verifyEmailOtp(String email, String token) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      throw const AuthRepositoryException('OTP token cannot be empty.');
    }

    final user = fakeUser(
      id: 'fake-${normalizeEmail(email).hashCode.abs()}',
      email: normalizeEmail(email),
    );
    final session = Session(
      accessToken: 'fake-access-token-$normalizedToken',
      expiresIn: 3600,
      refreshToken: 'fake-refresh-token',
      tokenType: 'bearer',
      user: user,
    );
    _currentUser = user;
    _authStateController.add(AuthState(AuthChangeEvent.signedIn, session));
    return AuthResponse(session: session);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _authStateController.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  Future<void> dispose() => _authStateController.close();
}

User fakeUser({required String id, required String email}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    email: email,
    createdAt: now,
    emailConfirmedAt: now,
    role: 'authenticated',
  );
}
