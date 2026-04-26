import 'dart:ui' show Size;

import 'package:flutter/material.dart' show Icons, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Image, ValueKey;
import 'package:pizza_reader/src/core/pizza_book.dart';
import 'package:pizza_reader/src/core/pizza_book_codec.dart';
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
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, 'Code')).enabled,
      isTrue,
    );
    expect(find.text('Nessun libro importato'), findsOneWidget);
    expect(find.text('Testo locale'), findsWidgets);
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
    expect(find.text('Testo locale'), findsOneWidget);
    expect(find.text('Roadside Notes'), findsOneWidget);
    expect(find.text('Attivo'), findsWidgets);
    expect(find.text('15 KB'), findsOneWidget);
    expect(find.text('4 KB - EPUB'), findsOneWidget);
    expect(find.text('EPUB'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('delete-book-starter-pizza-book')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rename-book-starter-pizza-book')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('delete-book-roadside-notes')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rename-book-roadside-notes')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirms before deleting imported books', (tester) async {
    _setViewport(tester, const Size(1400, 900));

    final libraryRepository = await _seedLibrary();
    await tester.pumpWidget(
      PizzaReaderApp(
        authRepository: FakeAuthRepository(
          signedInUserId: 'fake-user',
          signedInEmail: 'reader@example.test',
        ),
        libraryRepository: libraryRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('delete-book-roadside-notes')));
    await tester.pumpAndSettle();

    expect(find.text('Elimina libro'), findsOneWidget);
    expect(
      find.textContaining('Vuoi eliminare "Roadside Notes"'),
      findsOneWidget,
    );

    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();

    expect(find.text('Roadside Notes'), findsNothing);
    expect(
      find.byKey(const ValueKey('delete-book-roadside-notes')),
      findsNothing,
    );
    expect((await libraryRepository.listBooks()).map((book) => book.id), [
      'starter-pizza-book',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens an imported book when its library card is tapped', (
    tester,
  ) async {
    _setViewport(tester, const Size(1400, 900));

    final libraryRepository = await _seedSelectableLibrary();
    await tester.pumpWidget(
      PizzaReaderApp(
        authRepository: FakeAuthRepository(
          signedInUserId: 'fake-user',
          signedInEmail: 'reader@example.test',
        ),
        libraryRepository: libraryRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Roadside Notes'));
    await tester.pumpAndSettle();

    expect(find.text('Roadside Chapter'), findsWidgets);
    expect(find.textContaining('Aperto Roadside Notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selects chapters inside the book overlay', (tester) async {
    _setViewport(tester, const Size(1400, 900));

    await tester.pumpWidget(PizzaReaderApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Apri libro'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('book-chapter-selector')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-text-lines')), findsNothing);
    expect(find.text('Capitoli'), findsOneWidget);
    expect(find.text('Testo'), findsNothing);

    await tester.tap(find.text('Cottura').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('book-chapter-selector')), findsNothing);
    expect(find.textContaining('Cottura selezionato'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renames imported books from the library profile', (
    tester,
  ) async {
    _setViewport(tester, const Size(1400, 900));

    final libraryRepository = await _seedSelectableLibrary();
    await tester.pumpWidget(
      PizzaReaderApp(
        authRepository: FakeAuthRepository(
          signedInUserId: 'fake-user',
          signedInEmail: 'reader@example.test',
        ),
        libraryRepository: libraryRepository,
      ),
    );
    await tester.pumpAndSettle();

    final renameButton = find.byKey(
      const ValueKey('rename-book-roadside-notes'),
    );
    await tester.ensureVisible(renameButton);
    await tester.pumpAndSettle();
    await tester.tap(renameButton);
    await tester.pumpAndSettle();

    expect(find.text('Rinomina libro'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Titolo'),
      'Roadside Renamed',
    );
    await tester.tap(find.text('Rinomina').last);
    await tester.pumpAndSettle();

    expect(find.text('Roadside Renamed'), findsOneWidget);
    expect(find.text('Roadside Notes'), findsNothing);

    final renamed = (await libraryRepository.listBooks()).single;
    expect(renamed.title, 'Roadside Renamed');
    expect(
      const PizzaBookCodec()
          .decodeBytes(await libraryRepository.downloadBookBytes(renamed))
          .title,
      'Roadside Renamed',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renames books in the open mobile profile immediately', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 760));

    final libraryRepository = await _seedSelectableLibrary();
    await tester.pumpWidget(
      PizzaReaderApp(
        authRepository: FakeAuthRepository(
          signedInUserId: 'fake-user',
          signedInEmail: 'reader@example.test',
        ),
        libraryRepository: libraryRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Account e libreria'));
    await tester.pumpAndSettle();

    expect(find.text('Libreria'), findsOneWidget);

    final mobileRenameButton = find.byKey(
      const ValueKey('rename-book-roadside-notes'),
    );
    await tester.ensureVisible(mobileRenameButton);
    await tester.pumpAndSettle();
    await tester.tap(mobileRenameButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Titolo'),
      'Roadside Mobile',
    );
    await tester.tap(find.text('Rinomina').last);
    await tester.pumpAndSettle();

    expect(find.text('Libreria'), findsOneWidget);
    expect(find.text('Roadside Mobile'), findsOneWidget);
    expect(find.text('Roadside Notes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the mobile viewport compact', (tester) async {
    _setViewport(tester, const Size(390, 760));

    await tester.pumpWidget(PizzaReaderApp());
    await tester.pumpAndSettle();

    expect(find.text('Testo locale'), findsWidgets);
    expect(find.byTooltip('Account e libreria'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byTooltip('Account e libreria'),
        matching: find.byIcon(Icons.account_circle_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text('Importa ebook'), findsNothing);
    expect(
      find.descendant(
        of: find.byTooltip('Apri libro'),
        matching: find.byIcon(Icons.menu_book_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text('200'), findsOneWidget);
    expect(find.text('WPM'), findsOneWidget);
    expect(find.text('Modalita'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('speed-readout-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('tempo'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('speed-readout-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('WPM'), findsOneWidget);

    await tester.tap(find.byTooltip('Account e libreria'));
    await tester.pumpAndSettle();

    expect(find.text('Accesso'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, 'Code')).enabled,
      isTrue,
    );
    expect(find.text('Libreria'), findsOneWidget);
    expect(find.text('Nessun libro importato'), findsOneWidget);
    expect(find.text('Importa ebook'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Code'), '123456');
    await tester.pump();

    expect(find.text('Verifica'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates mobile auth feedback without reopening the sheet', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 760));

    final authRepository = FakeAuthRepository();
    await tester.pumpWidget(PizzaReaderApp(authRepository: authRepository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Account e libreria'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'reader@example.test',
    );
    await tester.tap(find.text('Invia'));
    await tester.pumpAndSettle();

    expect(authRepository.sentMagicCodeEmails, ['reader@example.test']);
    expect(find.text('Verifica'), findsOneWidget);
    expect(find.text('Codice inviato. Inseriscilo qui.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Code'), '123456');
    await tester.tap(find.text('Verifica'));
    await tester.pumpAndSettle();

    expect(find.text('Connesso'), findsOneWidget);
    expect(find.text('reader@example.test'), findsOneWidget);
    expect(find.text('Esci dall\'account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses pizza imagery for loading and the desktop brand', (
    tester,
  ) async {
    await tester.pumpWidget(const PizzaReaderLoadingApp());
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);

    _setViewport(tester, const Size(1400, 900));
    await tester.pumpWidget(PizzaReaderApp());
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
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
      id: 'starter-pizza-book',
      userId: 'fake-user',
      title: 'Testo locale',
      author: 'Pizza Reader',
      sourceFileName: 'testo-locale.epub',
      storagePath: 'fake-user/starter-pizza-book.json',
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
      storagePath: 'fake-user/roadside-notes.json',
      byteLength: 15360,
    ),
  );
  return repository;
}

Future<FakeLibraryRepository> _seedSelectableLibrary() async {
  final repository = FakeLibraryRepository();
  const codec = PizzaBookCodec();
  final book = PizzaBook(
    id: 'roadside-notes',
    title: 'Roadside Notes',
    author: 'Luca',
    language: 'it',
    chapters: const [
      PizzaChapter(
        id: 'roadside-chapter',
        title: 'Roadside Chapter',
        text: 'Questa lettura importata verifica il tap sulla libreria.',
      ),
    ],
  );

  await repository.uploadBook(
    bytes: codec.encode(book),
    title: book.title,
    author: book.author,
    sourceFileName: 'roadside.epub',
    bookId: book.id,
  );
  return repository;
}
