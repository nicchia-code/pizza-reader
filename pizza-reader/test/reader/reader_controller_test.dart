import 'package:flutter_test/flutter_test.dart';
import 'package:pizza_reader/src/core/pizza_book.dart';
import 'package:pizza_reader/src/reader/reader_controller.dart';
import 'package:pizza_reader/src/reader/reading_pace.dart';

void main() {
  group('ReaderController', () {
    test('auto and hold modes advance by weighted word durations', () {
      final controller = ReaderController(
        _book(),
        initialMode: ReaderMode.auto,
        pace: const ReadingPace(wordsPerMinute: 60),
      );

      final firstDuration = controller.currentWordDuration;
      expect(controller.currentWord.text, 'one');
      expect(
        controller.tick(firstDuration - const Duration(microseconds: 1)),
        isFalse,
      );
      expect(controller.currentWord.text, 'one');

      expect(controller.tick(const Duration(microseconds: 1)), isTrue);
      expect(controller.currentWord.text, 'two.');

      controller.hold();
      expect(controller.tick(controller.currentWordDuration), isTrue);
      expect(controller.currentChapter.id, 'chapter-2');
      expect(controller.currentWord.text, 'three');

      controller.resumeFromHold();
      expect(controller.mode, ReaderMode.auto);
      controller.tick(controller.currentWordDuration);
      expect(controller.currentWord.text, 'four');
    });

    test('manual mode and seeks move through chapter and word positions', () {
      final controller = ReaderController(
        _book(),
        pace: const ReadingPace(wordsPerMinute: 240),
      );

      expect(controller.mode, ReaderMode.manual);
      expect(controller.manualNext(), isTrue);
      expect(controller.currentWord.text, 'two.');
      expect(controller.manualPrevious(), isTrue);
      expect(controller.currentWord.text, 'one');

      controller.seekChapter(1, wordIndex: 1);
      expect(controller.currentWord.text, 'four');

      controller.seekTextOffset(0);
      expect(controller.currentWord.text, 'three');

      controller.setMode(ReaderMode.auto);
      expect(controller.manualNext(), isFalse);
    });
  });
}

PizzaBook _book() {
  return PizzaBook(
    id: 'reader-book',
    title: 'Reader Book',
    chapters: const <PizzaChapter>[
      PizzaChapter(id: 'chapter-1', title: 'One', text: 'one two.'),
      PizzaChapter(id: 'chapter-2', title: 'Two', text: 'three four'),
    ],
  );
}
