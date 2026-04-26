import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Image;
import 'package:pizza_reader/src/supabase/supabase.dart';
import 'package:pizza_reader/src/ui/pizza_reader_app.dart';

void main() {
  testWidgets('shows desktop auth and empty library state', (tester) async {
    _setViewport(tester, const Size(1400, 900));

    await tester.pumpWidget(PizzaReaderApp());
    await tester.pumpAndSettle();

    expect(find.text('Pizza\nReader'), findsOneWidget);
    expect(find.text('Local/Fake'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);
    expect(find.text('Nessun libro importato'), findsOneWidget);
    expect(find.text('Demo Pizza Book'), findsWidgets);
    expect(find.text('Velocita'), findsOneWidget);
    expect(find.text('Modalita'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows imported book cards on desktop', (tester) async {
    _setViewport(tester, const Size(1400, 900));

    final libraryRepository = await _seedLibrary();
    final authRepository = FakeAuthRepository(
      signedInUserId: 'fake-user',
      signedInEmail: 'reader@example.test',
    );

    await tester.pumpWidget(
      PizzaReaderApp(
        authRepository: authRepository,
        libraryRepository: libraryRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('reader@example.test'), findsOneWidget);
    expect(find.text('Esci dall\'account'), findsOneWidget);
    expect(find.text('Libri importati'), findsOneWidget);
    expect(find.text('Roadside Notes'), findsOneWidget);
    expect(find.text('Attivo'), findsWidgets);
    expect(find.text('15 KB'), findsOneWidget);
    expect(find.text('EPUB/PB'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the mobile viewport compact', (tester) async {
    _setViewport(tester, const Size(390, 760));

    await tester.pumpWidget(PizzaReaderApp());
    await tester.pumpAndSettle();

    expect(find.text('Demo Pizza Book'), findsWidgets);
    expect(find.byTooltip('Account e libreria'), findsOneWidget);
    expect(find.byTooltip('Importa ebook'), findsOneWidget);
    expect(find.text('360'), findsOneWidget);
    expect(find.text('WPM'), findsOneWidget);
    expect(find.text('Modalita'), findsNothing);

    await tester.tap(find.byTooltip('Account e libreria'));
    await tester.pumpAndSettle();

    expect(find.text('Accesso'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);
    expect(find.text('Libreria'), findsOneWidget);
    expect(find.text('Nessun libro importato'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the pizza logo only on the loading screen', (
    tester,
  ) async {
    await tester.pumpWidget(const PizzaReaderLoadingApp());
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(PizzaReaderApp());
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<FakeLibraryRepository> _seedLibrary() async {
  final repository = FakeLibraryRepository();
  await repository.upsertBookMetadata(
    const LibraryBook(
      id: 'demo-pizza-book',
      userId: 'fake-user',
      title: 'Demo Pizza Book',
      author: 'Pizza Reader',
      sourceFileName: 'demo.epub',
      storagePath: 'fake-user/demo-pizza-book.pb',
      byteLength: 4096,
    ),
  );
  await repository.upsertBookMetadata(
    const LibraryBook(
      id: 'roadside-notes',
      userId: 'fake-user',
      title: 'Roadside Notes',
      author: 'Luca',
      sourceFileName: 'roadside.epub',
      storagePath: 'fake-user/roadside-notes.pb',
      byteLength: 15360,
    ),
  );
  return repository;
}
