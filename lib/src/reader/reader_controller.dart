import '../core/pizza_book.dart';
import 'reading_pace.dart';
import 'word_tokenizer.dart';

enum ReaderMode { auto, manual, hold }

class ReaderPosition {
  const ReaderPosition({required this.chapterIndex, required this.wordIndex});

  final int chapterIndex;
  final int wordIndex;
}

class ReaderController {
  ReaderController(
    this.book, {
    ReadingPace? pace,
    ReaderMode initialMode = ReaderMode.manual,
    WordTokenizer tokenizer = const WordTokenizer(),
  }) : pace = pace ?? const ReadingPace(),
       _mode = initialMode {
    book.validate();
    _wordMaps = book.chapters
        .map((chapter) {
          final wordMap = tokenizer.tokenize(chapter.text);
          if (wordMap.words.isEmpty) {
            throw FormatException(
              'Pizza chapter "${chapter.id}" does not contain readable words.',
            );
          }
          return wordMap;
        })
        .toList(growable: false);
    _durations = _wordMaps
        .map((wordMap) => this.pace.durationsFor(wordMap.words))
        .toList(growable: false);
  }

  final PizzaBook book;
  final ReadingPace pace;

  late final List<WordMap> _wordMaps;
  late final List<List<Duration>> _durations;
  ReaderMode _mode;
  ReaderMode _modeBeforeHold = ReaderMode.manual;
  int _chapterIndex = 0;
  int _wordIndex = 0;
  Duration _elapsedOnWord = Duration.zero;
  bool _completed = false;

  ReaderMode get mode => _mode;

  ReaderPosition get position =>
      ReaderPosition(chapterIndex: _chapterIndex, wordIndex: _wordIndex);

  bool get isCompleted => _completed;

  PizzaChapter get currentChapter => book.chapters[_chapterIndex];

  WordMap get currentWordMap => _wordMaps[_chapterIndex];

  ReadingWord get currentWord => currentWordMap.words[_wordIndex];

  Duration get currentWordDuration => _durations[_chapterIndex][_wordIndex];

  Duration get elapsedOnWord => _elapsedOnWord;

  void setMode(ReaderMode mode) {
    if (mode == ReaderMode.hold && _mode != ReaderMode.hold) {
      _modeBeforeHold = _mode;
    }
    _mode = mode;
    _elapsedOnWord = Duration.zero;
  }

  void hold() {
    setMode(ReaderMode.hold);
  }

  void resumeFromHold() {
    if (_mode == ReaderMode.hold) {
      setMode(_modeBeforeHold);
    }
  }

  void seekChapter(int chapterIndex, {int wordIndex = 0}) {
    _checkChapterIndex(chapterIndex);
    _checkWordIndex(chapterIndex, wordIndex);
    _seek(chapterIndex, wordIndex);
  }

  void seekWord(int wordIndex) {
    _checkWordIndex(_chapterIndex, wordIndex);
    _seek(_chapterIndex, wordIndex);
  }

  void seekTextOffset(int textOffset) {
    final wordIndex = currentWordMap.wordIndexForTextOffset(textOffset) ?? 0;
    seekWord(wordIndex);
  }

  bool next() {
    return _moveNext();
  }

  bool previous() {
    return _movePrevious();
  }

  bool manualNext() {
    if (_mode != ReaderMode.manual) {
      return false;
    }
    return next();
  }

  bool manualPrevious() {
    if (_mode != ReaderMode.manual) {
      return false;
    }
    return previous();
  }

  bool tick(Duration elapsed) {
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'Must not be negative.');
    }
    if ((_mode != ReaderMode.auto && _mode != ReaderMode.hold) || _completed) {
      return false;
    }

    _elapsedOnWord += elapsed;
    var moved = false;
    while (!_completed && _elapsedOnWord >= currentWordDuration) {
      _elapsedOnWord -= currentWordDuration;
      final didMove = _moveNext();
      if (!didMove) {
        _elapsedOnWord = Duration.zero;
      }
      moved = moved || didMove;
    }
    return moved;
  }

  void _seek(int chapterIndex, int wordIndex) {
    _chapterIndex = chapterIndex;
    _wordIndex = wordIndex;
    _elapsedOnWord = Duration.zero;
    _completed = false;
  }

  bool _moveNext() {
    final words = _wordMaps[_chapterIndex].words;
    if (_wordIndex + 1 < words.length) {
      _wordIndex += 1;
      _elapsedOnWord = Duration.zero;
      return true;
    }

    if (_chapterIndex + 1 < _wordMaps.length) {
      _chapterIndex += 1;
      _wordIndex = 0;
      _elapsedOnWord = Duration.zero;
      return true;
    }

    _completed = true;
    return false;
  }

  bool _movePrevious() {
    if (_wordIndex > 0) {
      _wordIndex -= 1;
      _elapsedOnWord = Duration.zero;
      _completed = false;
      return true;
    }

    if (_chapterIndex > 0) {
      _chapterIndex -= 1;
      _wordIndex = _wordMaps[_chapterIndex].words.length - 1;
      _elapsedOnWord = Duration.zero;
      _completed = false;
      return true;
    }

    return false;
  }

  void _checkChapterIndex(int chapterIndex) {
    RangeError.checkValidIndex(chapterIndex, book.chapters, 'chapterIndex');
  }

  void _checkWordIndex(int chapterIndex, int wordIndex) {
    RangeError.checkValidIndex(
      wordIndex,
      _wordMaps[chapterIndex].words,
      'wordIndex',
    );
  }
}
