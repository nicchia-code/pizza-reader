class ReadingWord {
  const ReadingWord({
    required this.index,
    required this.text,
    required this.startOffset,
    required this.endOffset,
    required this.pivotIndex,
  });

  final int index;
  final String text;
  final int startOffset;
  final int endOffset;
  final int pivotIndex;

  int get pivotTextOffset => startOffset + pivotIndex;

  String get pivotLetter {
    if (text.isEmpty) {
      return '';
    }
    return text[pivotIndex];
  }
}

class WordMap {
  const WordMap({required this.sourceText, required this.words});

  final String sourceText;
  final List<ReadingWord> words;

  ReadingWord? wordAt(int index) {
    if (index < 0 || index >= words.length) {
      return null;
    }
    return words[index];
  }

  int? wordIndexForTextOffset(int offset) {
    if (words.isEmpty) {
      return null;
    }

    final clamped = offset.clamp(0, sourceText.length);
    var low = 0;
    var high = words.length - 1;

    while (low <= high) {
      final mid = low + ((high - low) >> 1);
      final word = words[mid];
      if (clamped < word.startOffset) {
        high = mid - 1;
      } else if (clamped >= word.endOffset) {
        low = mid + 1;
      } else {
        return mid;
      }
    }

    if (low >= words.length) {
      return words.length - 1;
    }
    return low;
  }
}

class WordTokenizer {
  const WordTokenizer();

  static final RegExp _tokenPattern = RegExp(r'\S+');
  static final RegExp _readableCharacterPattern = RegExp(
    r'[A-Za-z0-9À-ÖØ-öø-ÿ]',
  );

  WordMap tokenize(String text) {
    final words = <ReadingWord>[];

    for (final match in _tokenPattern.allMatches(text)) {
      final token = match.group(0)!;
      words.add(
        ReadingWord(
          index: words.length,
          text: token,
          startOffset: match.start,
          endOffset: match.end,
          pivotIndex: pivotIndexFor(token),
        ),
      );
    }

    return WordMap(
      sourceText: text,
      words: List<ReadingWord>.unmodifiable(words),
    );
  }

  static int readableLength(String token) {
    var length = 0;
    for (var i = 0; i < token.length; i += 1) {
      if (_isReadableCharacter(token[i])) {
        length += 1;
      }
    }
    return length;
  }

  static int pivotIndexFor(String token) {
    final readableIndexes = <int>[];
    for (var i = 0; i < token.length; i += 1) {
      if (_isReadableCharacter(token[i])) {
        readableIndexes.add(i);
      }
    }

    if (readableIndexes.isEmpty) {
      return 0;
    }

    final pivot = _pivotReadablePosition(readableIndexes.length);
    return readableIndexes[pivot];
  }

  static int _pivotReadablePosition(int length) {
    if (length <= 1) {
      return 0;
    }
    if (length <= 5) {
      return 1;
    }
    if (length <= 9) {
      return 2;
    }
    if (length <= 13) {
      return 3;
    }
    return 4;
  }

  static bool _isReadableCharacter(String character) {
    return _readableCharacterPattern.hasMatch(character);
  }
}
