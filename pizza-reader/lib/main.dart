import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/supabase/supabase.dart';
import 'src/ui/pizza_reader_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PizzaReaderBootstrap());
}

class PizzaReaderBootstrap extends StatefulWidget {
  const PizzaReaderBootstrap({super.key});

  @override
  State<PizzaReaderBootstrap> createState() => _PizzaReaderBootstrapState();
}

class _PizzaReaderBootstrapState extends State<PizzaReaderBootstrap> {
  late final Future<_PizzaReaderRuntime> _runtime = _createRuntime();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PizzaReaderRuntime>(
      future: _runtime,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return PizzaReaderStartupErrorApp(error: snapshot.error);
        }

        final runtime = snapshot.data;
        if (runtime != null) {
          return PizzaReaderApp(
            authRepository: runtime.authRepository,
            libraryRepository: runtime.libraryRepository,
            cloudEnabled: runtime.cloudEnabled,
          );
        }

        return const PizzaReaderLoadingApp();
      },
    );
  }
}

Future<_PizzaReaderRuntime> _createRuntime() async {
  final config = SupabaseConfig.maybeFromDartDefines();
  SupabaseClient? client;
  if (config != null) {
    client = await initializeSupabase(config: config);
  }

  return _PizzaReaderRuntime(
    authRepository: client == null
        ? FakeAuthRepository()
        : SupabaseAuthRepository(client),
    libraryRepository: client == null
        ? FakeLibraryRepository()
        : SupabaseLibraryRepository(client),
    cloudEnabled: client != null,
  );
}

class _PizzaReaderRuntime {
  const _PizzaReaderRuntime({
    required this.authRepository,
    required this.libraryRepository,
    required this.cloudEnabled,
  });

  final AuthRepository authRepository;
  final LibraryRepository libraryRepository;
  final bool cloudEnabled;
}
