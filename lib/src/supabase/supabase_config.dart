import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfigException implements Exception {
  const SupabaseConfigException(this.message);

  final String message;

  @override
  String toString() => 'SupabaseConfigException: $message';
}

class SupabaseConfig {
  const SupabaseConfig._({required this.url, required this.anonKey});

  static const urlDefine = 'SUPABASE_URL';
  static const anonKeyDefine = 'SUPABASE_ANON_KEY';

  final String url;
  final String anonKey;

  factory SupabaseConfig.fromDartDefines() {
    return SupabaseConfig.fromValues(
      url: const String.fromEnvironment(urlDefine),
      anonKey: const String.fromEnvironment(anonKeyDefine),
    );
  }

  factory SupabaseConfig.fromValues({
    required String url,
    required String anonKey,
  }) {
    final normalizedUrl = _normalizeUrl(url);
    final normalizedAnonKey = anonKey.trim();

    if (normalizedAnonKey.isEmpty) {
      throw const SupabaseConfigException(
        'Missing SUPABASE_ANON_KEY. Pass it with --dart-define.',
      );
    }

    return SupabaseConfig._(url: normalizedUrl, anonKey: normalizedAnonKey);
  }

  static SupabaseConfig? maybeFromDartDefines() {
    try {
      return SupabaseConfig.fromDartDefines();
    } on SupabaseConfigException {
      return null;
    }
  }

  static String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const SupabaseConfigException(
        'Missing SUPABASE_URL. Pass it with --dart-define.',
      );
    }

    final uri = Uri.tryParse(trimmed);
    final validScheme =
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.hasAuthority;
    if (!validScheme) {
      throw SupabaseConfigException(
        'Invalid SUPABASE_URL "$trimmed". Expected an http(s) URL.',
      );
    }

    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }
}

Future<SupabaseClient> initializeSupabase({SupabaseConfig? config}) async {
  final effectiveConfig = config ?? SupabaseConfig.fromDartDefines();
  await Supabase.initialize(
    url: effectiveConfig.url,
    anonKey: effectiveConfig.anonKey,
  );
  return Supabase.instance.client;
}
