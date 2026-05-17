import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pizza_reader/src/supabase/supabase.dart';

void main() {
  group('FakeLibraryRepository', () {
    test('uploads reader bytes and upserts metadata in memory', () async {
      final repository = FakeLibraryRepository(userId: 'user-1');
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      final book = await repository.uploadBook(
        bytes: bytes,
        title: ' My Book ',
        author: ' Author ',
        sourceFileName: '/tmp/source.epub',
        bookId: ' weird id ! ',
      );

      expect(book.id, 'weird-id');
      expect(book.userId, 'user-1');
      expect(book.title, 'My Book');
      expect(book.author, 'Author');
      expect(book.sourceFileName, 'source.epub');
      expect(book.storageBucket, pizzaBooksBucketId);
      expect(book.storagePath, 'user-1/weird-id.json');
      expect(book.byteLength, bytes.length);
      expect(book.sha256, pizzaBookDigest(bytes));
      expect(
        repository.uploadedObjects[book.storagePath]?.toList(),
        bytes.toList(),
      );
      expect(
        (await repository.downloadBookBytes(book)).toList(),
        bytes.toList(),
      );
    });

    test('upserts and fetches reading progress', () async {
      final repository = FakeLibraryRepository(userId: 'user-1');

      await repository.upsertBookMetadata(
        const LibraryBook(
          id: 'book-1',
          userId: 'user-1',
          title: 'Book',
          storagePath: 'user-1/book-1.json',
          byteLength: 42,
        ),
      );
      final progress = await repository.upsertReadingProgress(
        const ReadingProgress(
          userId: 'ignored-user',
          bookId: 'book-1',
          chapterIndex: 7,
          wordIndex: 3,
          wpm: 240,
          mode: ' paced ',
          progressFraction: 0.5,
        ),
      );

      expect(progress.userId, 'user-1');
      expect(progress.chapterIndex, 7);
      expect(progress.wordIndex, 3);
      expect(progress.wpm, 240);
      expect(progress.mode, 'paced');
      expect(progress.progressFraction, 0.5);
      expect((await repository.getReadingProgress('book-1'))?.wordIndex, 3);
    });

    test('reads legacy paragraph progress as chapter progress', () {
      final progress = ReadingProgress.fromJson({
        'user_id': 'user-1',
        'book_id': 'book-1',
        'paragraph_index': 9,
        'word_index': 4,
        'progress_fraction': 0.75,
      });

      expect(progress.chapterIndex, 9);
      expect(progress.wordIndex, 4);
      expect(progress.progressFraction, 0.75);
    });

    test('deletes metadata, progress, and object bytes', () async {
      final repository = FakeLibraryRepository(userId: 'user-1');
      final book = await repository.uploadBook(
        bytes: Uint8List.fromList([1, 2, 3]),
        title: 'Book',
        bookId: 'book-1',
      );
      await repository.upsertReadingProgress(
        const ReadingProgress(
          userId: 'ignored-user',
          bookId: 'book-1',
          chapterIndex: 1,
          wordIndex: 2,
        ),
      );

      await repository.deleteBook('book-1');

      expect(await repository.listBooks(), isEmpty);
      expect(await repository.getReadingProgress('book-1'), isNull);
      expect(repository.uploadedObjects, isNot(contains(book.storagePath)));
      await expectLater(repository.deleteBook('book-1'), completes);
    });

    test('validates metadata and progress values', () {
      expect(
        () => sanitizeBookId('!!!'),
        throwsA(isA<LibraryRepositoryException>()),
      );
      expect(
        () => const ReadingProgress(
          userId: 'user-1',
          bookId: 'book-1',
          progressFraction: 1.5,
        ).toUpsertJson(),
        throwsA(isA<LibraryRepositoryException>()),
      );
      expect(
        () => const ReadingProgress(
          userId: 'user-1',
          bookId: 'book-1',
          wpm: 0,
        ).toUpsertJson(),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });
  });
}
