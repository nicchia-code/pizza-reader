import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pizza_reader/src/core/pizza_book.dart';
import 'package:pizza_reader/src/core/pizza_book_codec.dart';

void main() {
  group('PizzaBookCodec', () {
    test('encodes and decodes .pb v1 JSON UTF-8 with content hash', () {
      const codec = PizzaBookCodec();
      final book = _sampleBook();

      final encoded = codec.encodeToString(book);
      final document = jsonDecode(encoded) as Map<String, Object?>;

      expect(document['format'], PizzaBookCodec.format);
      expect(document['version'], PizzaBookCodec.version);
      expect(document['content_hash'], codec.contentHash(book));

      final decoded = codec.decodeString(encoded);
      expect(decoded.id, book.id);
      expect(decoded.title, book.title);
      expect(decoded.chapters.single.text, book.chapters.single.text);
    });

    test('hash is deterministic for equivalent JSON content', () {
      const codec = PizzaBookCodec();
      final left = _sampleBook(metadata: <String, Object?>{'b': 2, 'a': 1});
      final right = _sampleBook(metadata: <String, Object?>{'a': 1, 'b': 2});

      expect(codec.contentHash(left), codec.contentHash(right));
      expect(codec.encodeToString(left), codec.encodeToString(right));
    });

    test('rejects tampered content and invalid minimal structure', () {
      const codec = PizzaBookCodec();
      final encoded = codec.encodeToString(_sampleBook());
      final tampered = encoded.replaceFirst(
        'Pizza reader text.',
        'Changed text.',
      );

      expect(() => codec.decodeString(tampered), throwsFormatException);
      expect(
        () => PizzaBook(
          id: 'empty',
          title: 'Empty',
          chapters: const [],
        ).validate(),
        throwsFormatException,
      );
    });
  });
}

PizzaBook _sampleBook({
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return PizzaBook(
    id: 'book-1',
    title: 'Pizza Book',
    author: 'Pizza Reader',
    language: 'en',
    chapters: const <PizzaChapter>[
      PizzaChapter(
        id: 'chapter-1',
        title: 'Chapter 1',
        text: 'Pizza reader text.',
      ),
    ],
    metadata: metadata,
  );
}
