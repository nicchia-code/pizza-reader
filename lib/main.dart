import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/supabase/supabase.dart';
import 'src/ui/pizza_reader_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SupabaseClient? client;
  final config = SupabaseConfig.maybeFromDartDefines();
  if (config != null) {
    client = await initializeSupabase(config: config);
  }

  runApp(
    PizzaReaderApp(
      authRepository: client == null
          ? FakeAuthRepository()
          : SupabaseAuthRepository(client),
      libraryRepository: client == null
          ? FakeLibraryRepository()
          : SupabaseLibraryRepository(client),
      cloudEnabled: client != null,
    ),
  );
}
