import 'package:flutter_test/flutter_test.dart';
import 'package:pizza_reader/src/reader/reading_pace.dart';
import 'package:pizza_reader/src/reader/word_tokenizer.dart';

void main() {
  group('ReadingPace', () {
    test(
      'keeps target average WPM while weighting long words and punctuation',
      () {
        const tokenizer = WordTokenizer();
        const pace = ReadingPace(wordsPerMinute: 120);
        final words = tokenizer.tokenize('cat internationalization end.').words;

        final durations = pace.durationsFor(words);
        final totalMicros = durations.fold<int>(
          0,
          (total, duration) => total + duration.inMicroseconds,
        );

        expect(durations, hasLength(3));
        expect(durations[1], greaterThan(durations[0]));
        expect(durations[2], greaterThan(durations[0]));
        expect(totalMicros, Duration.microsecondsPerSecond * 3 ~/ 2);
      },
    );
  });
}
