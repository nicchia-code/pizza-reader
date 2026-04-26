import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'pizza_book.dart';

class PizzaBookCodec {
  const PizzaBookCodec();

  static const String format = 'pizza_reader_document';
  static const int version = 1;
  static const String hashPrefix = 'sha256:';

  Uint8List encode(PizzaBook book) {
    return Uint8List.fromList(utf8.encode(encodeToString(book)));
  }

  String encodeToString(PizzaBook book) {
    book.validate();
    return _canonicalJsonEncode(_documentFor(book));
  }

  PizzaBook decodeBytes(List<int> bytes) {
    final source = utf8.decode(bytes, allowMalformed: false);
    return decodeString(source);
  }

  PizzaBook decodeString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException(
        'Reader document must be valid JSON: ${error.message}',
      );
    }

    if (decoded is! Map) {
      throw const FormatException(
        'Reader document root must be a JSON object.',
      );
    }

    final document = <String, Object?>{};
    for (final entry in decoded.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException('Reader document keys must be strings.');
      }
      document[key] = entry.value;
    }

    if (document['format'] != format) {
      throw const FormatException('Unsupported reader document format.');
    }
    if (document['version'] != version) {
      throw const FormatException('Unsupported reader document version.');
    }

    final hash = document['content_hash'];
    if (hash is! String || !hash.startsWith(hashPrefix)) {
      throw const FormatException('Reader document content_hash is required.');
    }

    final book = PizzaBook.fromJson(document['book']);
    book.validate();

    final expectedHash = contentHash(book);
    if (hash != expectedHash) {
      throw FormatException(
        'Reader document content hash mismatch. Expected $expectedHash.',
      );
    }

    return book;
  }

  String contentHash(PizzaBook book) {
    book.validate();
    final canonical = canonicalContent(book);
    return '$hashPrefix${sha256.convert(utf8.encode(canonical))}';
  }

  String canonicalContent(PizzaBook book) {
    book.validate();
    return _canonicalJsonEncode(book.toJson());
  }

  Map<String, Object?> _documentFor(PizzaBook book) => <String, Object?>{
    'format': format,
    'version': version,
    'content_hash': contentHash(book),
    'book': book.toJson(),
  };
}

String _canonicalJsonEncode(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    if (value is double && !value.isFinite) {
      throw const FormatException('JSON numbers must be finite.');
    }
    return jsonEncode(value);
  }

  if (value is List) {
    return '[${value.map(_canonicalJsonEncode).join(',')}]';
  }

  if (value is Map) {
    final entries = <MapEntry<String, Object?>>[];
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException('JSON object keys must be strings.');
      }
      entries.add(MapEntry<String, Object?>(key, entry.value));
    }
    entries.sort((left, right) => left.key.compareTo(right.key));

    final encodedEntries = entries.map((entry) {
      final key = jsonEncode(entry.key);
      final encodedValue = _canonicalJsonEncode(entry.value);
      return '$key:$encodedValue';
    });
    return '{${encodedEntries.join(',')}}';
  }

  throw FormatException('Unsupported JSON value type ${value.runtimeType}.');
}
