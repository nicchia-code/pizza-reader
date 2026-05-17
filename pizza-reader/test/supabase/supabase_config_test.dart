import 'package:flutter_test/flutter_test.dart';
import 'package:pizza_reader/src/supabase/supabase_config.dart';

void main() {
  group('SupabaseConfig', () {
    test('normalizes valid values from strings', () {
      final config = SupabaseConfig.fromValues(
        url: ' https://example.supabase.co/ ',
        anonKey: ' anon-key ',
      );

      expect(config.url, 'https://example.supabase.co');
      expect(config.anonKey, 'anon-key');
    });

    test('rejects missing values', () {
      expect(
        () => SupabaseConfig.fromValues(url: '', anonKey: 'anon-key'),
        throwsA(isA<SupabaseConfigException>()),
      );
      expect(
        () => SupabaseConfig.fromValues(
          url: 'https://example.supabase.co',
          anonKey: ' ',
        ),
        throwsA(isA<SupabaseConfigException>()),
      );
    });

    test('rejects non-http urls', () {
      expect(
        () => SupabaseConfig.fromValues(
          url: 'ftp://example.supabase.co',
          anonKey: 'anon-key',
        ),
        throwsA(isA<SupabaseConfigException>()),
      );
    });

    test('documents publishable key dart define alias', () {
      expect(SupabaseConfig.publishableKeyDefine, 'SUPABASE_PUBLISHABLE_KEY');
      expect(SupabaseConfig.anonKeyDefine, 'SUPABASE_ANON_KEY');
    });
  });
}
