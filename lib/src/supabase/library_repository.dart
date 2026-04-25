import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const pizzaBooksBucketId = 'pizza-books';
const booksTableName = 'books';
const readingProgressTableName = 'reading_progress';
const pizzaBookContentType = 'application/vnd.pizza-book+json';

abstract interface class LibraryRepository {
  Future<LibraryBook> uploadBook({
    required Uint8List bytes,
    required String title,
    String? author,
    String? sourceFileName,
    String? bookId,
  });

  Future<LibraryBook> upsertBookMetadata(LibraryBook book);

  Future<ReadingProgress> upsertReadingProgress(ReadingProgress progress);

  Future<List<LibraryBook>> listBooks();

  Future<ReadingProgress?> getReadingProgress(String bookId);
}

class SupabaseLibraryRepository implements LibraryRepository {
  const SupabaseLibraryRepository(
    this._client, {
    this.bucketId = pizzaBooksBucketId,
  });

  final SupabaseClient _client;
  final String bucketId;

  @override
  Future<LibraryBook> uploadBook({
    required Uint8List bytes,
    required String title,
    String? author,
    String? sourceFileName,
    String? bookId,
  }) async {
    final userId = _requireUserId();
    final digest = pizzaBookDigest(bytes);
    final id = sanitizeBookId(bookId ?? digest);
    final storagePath = pizzaBookStoragePath(userId: userId, bookId: id);

    await _client.storage
        .from(bucketId)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: pizzaBookContentType,
          ),
        );

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
  Future<LibraryBook> upsertBookMetadata(LibraryBook book) async {
    final userId = _requireUserId();
    final response = await _client
        .from(booksTableName)
        .upsert(
          book.copyWith(userId: userId).toUpsertJson(),
          onConflict: 'user_id,id',
        )
        .select()
        .single();

    return LibraryBook.fromJson(response);
  }

  @override
  Future<ReadingProgress> upsertReadingProgress(
    ReadingProgress progress,
  ) async {
    final userId = _requireUserId();
    final response = await _client
        .from(readingProgressTableName)
        .upsert(
          progress.copyWith(userId: userId).toUpsertJson(),
          onConflict: 'user_id,book_id',
        )
        .select()
        .single();

    return ReadingProgress.fromJson(response);
  }

  @override
  Future<List<LibraryBook>> listBooks() async {
    final response = await _client
        .from(booksTableName)
        .select()
        .order('updated_at', ascending: false);

    return response.map(LibraryBook.fromJson).toList(growable: false);
  }

  @override
  Future<ReadingProgress?> getReadingProgress(String bookId) async {
    final id = sanitizeBookId(bookId);
    final response = await _client
        .from(readingProgressTableName)
        .select()
        .eq('book_id', id)
        .maybeSingle();

    return response == null ? null : ReadingProgress.fromJson(response);
  }

  String _requireUserId() {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const LibraryRepositoryException(
        'A signed-in Supabase user is required.',
      );
    }
    return user.id;
  }
}

class LibraryBook {
  const LibraryBook({
    required this.id,
    required this.userId,
    required this.title,
    this.author,
    this.sourceFileName,
    this.storageBucket = pizzaBooksBucketId,
    required this.storagePath,
    required this.byteLength,
    this.sha256,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String title;
  final String? author;
  final String? sourceFileName;
  final String storageBucket;
  final String storagePath;
  final int byteLength;
  final String? sha256;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory LibraryBook.fromJson(Map<String, dynamic> json) {
    return LibraryBook(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      sourceFileName: json['source_file_name'] as String?,
      storageBucket: json['storage_bucket'] as String? ?? pizzaBooksBucketId,
      storagePath: json['storage_path'] as String,
      byteLength: (json['byte_length'] as num).toInt(),
      sha256: json['sha256'] as String?,
      createdAt: dateTimeFromJson(json['created_at']),
      updatedAt: dateTimeFromJson(json['updated_at']),
    );
  }

  LibraryBook copyWith({
    String? id,
    String? userId,
    String? title,
    String? author,
    String? sourceFileName,
    String? storageBucket,
    String? storagePath,
    int? byteLength,
    String? sha256,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LibraryBook(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      author: author ?? this.author,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      storageBucket: storageBucket ?? this.storageBucket,
      storagePath: storagePath ?? this.storagePath,
      byteLength: byteLength ?? this.byteLength,
      sha256: sha256 ?? this.sha256,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toUpsertJson() {
    final normalizedId = sanitizeBookId(id);
    final normalizedTitle = requireText('title', title);
    final normalizedUserId = requireText('userId', userId);
    final normalizedStoragePath = requireText('storagePath', storagePath);
    if (byteLength < 0) {
      throw const LibraryRepositoryException('byteLength cannot be negative.');
    }
    if (!normalizedStoragePath.startsWith('$normalizedUserId/')) {
      throw const LibraryRepositoryException(
        'storagePath must be scoped under userId.',
      );
    }
    if (!normalizedStoragePath.endsWith('.pb')) {
      throw const LibraryRepositoryException('storagePath must end with .pb.');
    }

    return {
      'id': normalizedId,
      'user_id': normalizedUserId,
      'title': normalizedTitle,
      'author': nullableTrim(author),
      'source_file_name': baseFileName(sourceFileName),
      'storage_bucket': requireText('storageBucket', storageBucket),
      'storage_path': normalizedStoragePath,
      'byte_length': byteLength,
      'sha256': nullableTrim(sha256),
    };
  }
}

class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.userId,
    this.paragraphIndex = 0,
    this.wordIndex = 0,
    this.progressFraction = 0,
    this.updatedAt,
  });

  final String bookId;
  final String userId;
  final int paragraphIndex;
  final int wordIndex;
  final double progressFraction;
  final DateTime? updatedAt;

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      bookId: json['book_id'] as String,
      userId: json['user_id'] as String,
      paragraphIndex: (json['paragraph_index'] as num).toInt(),
      wordIndex: (json['word_index'] as num).toInt(),
      progressFraction: (json['progress_fraction'] as num).toDouble(),
      updatedAt: dateTimeFromJson(json['updated_at']),
    );
  }

  ReadingProgress copyWith({
    String? bookId,
    String? userId,
    int? paragraphIndex,
    int? wordIndex,
    double? progressFraction,
    DateTime? updatedAt,
  }) {
    return ReadingProgress(
      bookId: bookId ?? this.bookId,
      userId: userId ?? this.userId,
      paragraphIndex: paragraphIndex ?? this.paragraphIndex,
      wordIndex: wordIndex ?? this.wordIndex,
      progressFraction: progressFraction ?? this.progressFraction,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toUpsertJson() {
    final id = sanitizeBookId(bookId);
    final normalizedUserId = requireText('userId', userId);
    if (paragraphIndex < 0 || wordIndex < 0) {
      throw const LibraryRepositoryException(
        'Progress indices cannot be negative.',
      );
    }
    if (progressFraction < 0 || progressFraction > 1) {
      throw const LibraryRepositoryException(
        'progressFraction must be between 0 and 1.',
      );
    }

    return {
      'book_id': id,
      'user_id': normalizedUserId,
      'paragraph_index': paragraphIndex,
      'word_index': wordIndex,
      'progress_fraction': progressFraction,
    };
  }
}

class LibraryRepositoryException implements Exception {
  const LibraryRepositoryException(this.message);

  final String message;

  @override
  String toString() => 'LibraryRepositoryException: $message';
}

String pizzaBookDigest(Uint8List bytes) => sha256.convert(bytes).toString();

String pizzaBookStoragePath({required String userId, required String bookId}) {
  return '${requireText('userId', userId)}/${sanitizeBookId(bookId)}.pb';
}

String sanitizeBookId(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw const LibraryRepositoryException('bookId cannot be empty.');
  }

  final sanitized = trimmed
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (sanitized.isEmpty) {
    throw const LibraryRepositoryException('bookId cannot be empty.');
  }
  return sanitized;
}

String requireText(String field, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw LibraryRepositoryException('$field cannot be empty.');
  }
  return trimmed;
}

String? nullableTrim(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? baseFileName(String? value) {
  final trimmed = nullableTrim(value);
  if (trimmed == null) {
    return null;
  }
  return trimmed.split(RegExp(r'[\\/]')).last;
}

DateTime? dateTimeFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.parse(value);
  }
  return null;
}
