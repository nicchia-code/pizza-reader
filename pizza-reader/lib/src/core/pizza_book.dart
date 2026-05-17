class PizzaChapter {
  const PizzaChapter({
    required this.id,
    required this.title,
    required this.text,
  });

  factory PizzaChapter.fromJson(Object? value) {
    final map = _expectMap(value, 'chapter');
    return PizzaChapter(
      id: _expectString(map, 'id'),
      title: _expectString(map, 'title'),
      text: _expectString(map, 'text'),
    );
  }

  final String id;
  final String title;
  final String text;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'text': text,
  };

  PizzaChapter copyWith({String? id, String? title, String? text}) {
    return PizzaChapter(
      id: id ?? this.id,
      title: title ?? this.title,
      text: text ?? this.text,
    );
  }

  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('Pizza chapter id is required.');
    }
    if (title.trim().isEmpty) {
      throw FormatException('Pizza chapter "$id" title is required.');
    }
    if (text.trim().isEmpty) {
      throw FormatException('Pizza chapter "$id" text is empty.');
    }
  }
}

class PizzaBook {
  PizzaBook({
    required this.id,
    required this.title,
    required List<PizzaChapter> chapters,
    this.author,
    this.language,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : chapters = List<PizzaChapter>.unmodifiable(chapters),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  factory PizzaBook.fromJson(Object? value) {
    final map = _expectMap(value, 'book');
    final chaptersValue = map['chapters'];
    if (chaptersValue is! List) {
      throw const FormatException('Pizza book chapters must be a list.');
    }

    final metadataValue = map['metadata'];
    final metadata = metadataValue == null
        ? const <String, Object?>{}
        : _expectMap(metadataValue, 'metadata');

    return PizzaBook(
      id: _expectString(map, 'id'),
      title: _expectString(map, 'title'),
      author: _expectOptionalString(map, 'author'),
      language: _expectOptionalString(map, 'language'),
      chapters: chaptersValue.map(PizzaChapter.fromJson).toList(),
      metadata: metadata,
    );
  }

  final String id;
  final String title;
  final String? author;
  final String? language;
  final List<PizzaChapter> chapters;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    if (author != null) 'author': author,
    if (language != null) 'language': language,
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  PizzaBook copyWith({
    String? id,
    String? title,
    String? author,
    String? language,
    List<PizzaChapter>? chapters,
    Map<String, Object?>? metadata,
  }) {
    return PizzaBook(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      language: language ?? this.language,
      chapters: chapters ?? this.chapters,
      metadata: metadata ?? this.metadata,
    );
  }

  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('Pizza book id is required.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException('Pizza book title is required.');
    }
    if (chapters.isEmpty) {
      throw const FormatException(
        'Pizza book must contain at least one chapter.',
      );
    }

    final ids = <String>{};
    for (final chapter in chapters) {
      chapter.validate();
      if (!ids.add(chapter.id)) {
        throw FormatException('Duplicate Pizza chapter id "${chapter.id}".');
      }
    }

    if (!_isJsonValue(metadata)) {
      throw const FormatException(
        'Pizza book metadata must be JSON-compatible.',
      );
    }
  }
}

Map<String, Object?> _expectMap(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('Pizza $label must be an object.');
  }

  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('Pizza $label object keys must be strings.');
    }
    result[key] = entry.value;
  }
  return result;
}

String _expectString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) {
    throw FormatException('Pizza "$key" must be a string.');
  }
  return value;
}

String? _expectOptionalString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Pizza "$key" must be a string when present.');
  }
  return value;
}

bool _isJsonValue(Object? value) {
  if (value == null ||
      value is String ||
      value is bool ||
      value is int ||
      value is double) {
    return true;
  }
  if (value is List) {
    return value.every(_isJsonValue);
  }
  if (value is Map) {
    return value.entries.every(
      (entry) => entry.key is String && _isJsonValue(entry.value),
    );
  }
  return false;
}
