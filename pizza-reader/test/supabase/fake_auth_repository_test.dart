import 'package:flutter_test/flutter_test.dart';
import 'package:pizza_reader/src/supabase/supabase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('FakeAuthRepository', () {
    test('records magic-code email and emits signed-in/out states', () async {
      final repository = FakeAuthRepository();
      addTearDown(repository.dispose);

      await repository.sendMagicCode(' Reader@Example.COM ');
      expect(repository.sentMagicCodeEmails, ['reader@example.com']);

      final signedIn = repository.authStateChanges.first;
      final response = await repository.verifyEmailOtp(
        'Reader@Example.COM',
        '123456',
      );

      expect(repository.currentUser?.email, 'reader@example.com');
      expect(response.user?.email, 'reader@example.com');
      expect((await signedIn).event, AuthChangeEvent.signedIn);

      final signedOut = repository.authStateChanges.first;
      await repository.signOut();

      expect(repository.currentUser, isNull);
      expect((await signedOut).event, AuthChangeEvent.signedOut);
    });

    test('rejects invalid email and empty token', () async {
      final repository = FakeAuthRepository();
      addTearDown(repository.dispose);

      expect(
        () => repository.sendMagicCode('not-an-email'),
        throwsA(isA<AuthRepositoryException>()),
      );
      await expectLater(
        repository.verifyEmailOtp('reader@example.com', ' '),
        throwsA(isA<AuthRepositoryException>()),
      );
    });
  });
}
