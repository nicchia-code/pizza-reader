import 'dart:typed_data';

import 'library_repository.dart';

class FakeLibraryRepository implements LibraryRepository {
  FakeLibraryRepository({
    this.userId = 'fake-user',
    this.bucketId = pizzaBooksBucketId,
  });

  final String userId;
  final String bucketId;
  final Map<String, LibraryBook> _books = {};
  final Map<String, ReadingProgress> _progress = {};
  final Map<String, Uint8List> _objects = {};

  Map<String, Uint8List> get uploadedObjects {
    return Map.unmodifiable(
      _objects.map((path, bytes) => MapEntry(path, Uint8List.fromList(bytes))),
    );
  }

  @override
  Future<LibraryBook> uploadBook({
    required Uint8List bytes,
    required String title,
    String? author,
    String? sourceFileName,
    String? bookId,
  }) async {
    final digest = pizzaBookDigest(bytes);
    final id = sanitizeBookId(bookId ?? digest);
    final storagePath = pizzaBookStoragePath(userId: userId, bookId: id);
    _objects[storagePath] = Uint8List.fromList(bytes);

    return upsertBookMetadata(
      LibraryBook(
        id: id,
        userId: userId,
        title: title,
        author: author,
        sourceFileName: baseFileName(sourceFileName),
        storageBucket: bucketId,
        storagePath: storagePath,
        byteLength: bytes.length,
        sha256: digest,
      ),
    );
  }

  @override
  Future<Uint8List> downloadBookBytes(LibraryBook book) async {
    final storagePath = requireText('storagePath', book.storagePath);
    final bytes = _objects[storagePath];
    if (bytes == null) {
      throw const LibraryRepositoryException('Book bytes are not available.');
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<LibraryBook> upsertBookMetadata(LibraryBook book) async {
    final now = DateTime.now().toUtc();
    final normalized = LibraryBook.fromJson({
      ...book.copyWith(userId: userId).toUpsertJson(),
      'created_at': book.createdAt?.toIso8601String() ?? now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    _books[normalized.id] = normalized;
    return normalized;
  }

  @override
  Future<ReadingProgress> upsertReadingProgress(
    ReadingProgress progress,
  ) async {
    final now = DateTime.now().toUtc();
    final normalized = ReadingProgress.fromJson({
      ...progress.copyWith(userId: userId).toUpsertJson(),
      'updated_at': now.toIso8601String(),
    });
    _progress[normalized.bookId] = normalized;
    return normalized;
  }

  @override
  Future<List<LibraryBook>> listBooks() async {
    final books = _books.values.toList(growable: false);
    books.sort((left, right) {
      final leftUpdatedAt =
          left.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightUpdatedAt =
          right.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return rightUpdatedAt.compareTo(leftUpdatedAt);
    });
    return books;
  }

  @override
  Future<ReadingProgress?> getReadingProgress(String bookId) async {
    return _progress[sanitizeBookId(bookId)];
  }

  @override
  Future<void> deleteBook(String bookId) async {
    final id = sanitizeBookId(bookId);
    final book = _books.remove(id);
    _progress.remove(id);
    if (book != null) {
      _objects.remove(book.storagePath);
    }
  }
}
