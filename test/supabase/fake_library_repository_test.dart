import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pizza_reader/src/supabase/supabase.dart';

void main() {
  group('FakeLibraryRepository', () {
    test('uploads pb bytes and upserts metadata in memory', () async {
      final repository = FakeLibraryRepository(userId: 'user-1');
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      final book = await repository.uploadBook(
        bytes: bytes,
        title: ' My Book ',
        author: ' Author ',
        sourceFileName: '/tmp/source.pb',
        bookId: ' weird id ! ',
      );

      expect(book.id, 'weird-id');
      expect(book.userId, 'user-1');
      expect(book.title, 'My Book');
      expect(book.author, 'Author');
      expect(book.sourceFileName, 'source.pb');
      expect(book.storageBucket, pizzaBooksBucketId);
      expect(book.storagePath, 'user-1/weird-id.pb');
      expect(book.byteLength, bytes.length);
      expect(book.sha256, pizzaBookDigest(bytes));
      expect(
        repository.uploadedObjects[book.storagePath]?.toList(),
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
          storagePath: 'user-1/book-1.pb',
          byteLength: 42,
        ),
      );
      final progress = await repository.upsertReadingProgress(
        const ReadingProgress(
          userId: 'ignored-user',
          bookId: 'book-1',
          paragraphIndex: 7,
          wordIndex: 3,
          progressFraction: 0.5,
        ),
      );

      expect(progress.userId, 'user-1');
      expect(progress.paragraphIndex, 7);
      expect(progress.wordIndex, 3);
      expect(progress.progressFraction, 0.5);
      expect((await repository.getReadingProgress('book-1'))?.wordIndex, 3);
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
    });
  });
}
