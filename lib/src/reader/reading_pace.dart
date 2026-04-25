import 'dart:math' as math;

import 'word_tokenizer.dart';

class ReadingPace {
  const ReadingPace({this.wordsPerMinute = 300}) : assert(wordsPerMinute > 0);

  final int wordsPerMinute;

  Duration get baseWordDuration {
    return Duration(
      microseconds: (Duration.microsecondsPerMinute / wordsPerMinute).round(),
    );
  }

  List<Duration> durationsFor(List<ReadingWord> words) {
    if (words.isEmpty) {
      return const <Duration>[];
    }

    final weights = words.map(weightFor).toList(growable: false);
    final totalWeight = weights.fold<double>(
      0,
      (total, weight) => total + weight,
    );
    final targetMicros =
        (Duration.microsecondsPerMinute * words.length / wordsPerMinute)
            .round();

    var remainingMicros = targetMicros;
    final durations = <Duration>[];
    for (var i = 0; i < words.length; i += 1) {
      final wordsLeft = words.length - i - 1;
      final micros = i == words.length - 1
          ? remainingMicros
          : _boundedMicros(
              (targetMicros * weights[i] / totalWeight).round(),
              remainingMicros: remainingMicros,
              wordsLeft: wordsLeft,
            );
      durations.add(Duration(microseconds: micros));
      remainingMicros -= micros;
    }

    return durations;
  }

  double weightFor(ReadingWord word) {
    final length = WordTokenizer.readableLength(word.text);
    var weight = 1.0;

    if (length > 6) {
      weight += math.min(0.7, (length - 6) * 0.07);
    }

    final text = word.text.trimRight();
    if (text.endsWith('.') || text.endsWith('!') || text.endsWith('?')) {
      weight += 0.65;
    } else if (text.endsWith(',') || text.endsWith(';') || text.endsWith(':')) {
      weight += 0.35;
    }

    if (text.contains('-') || text.contains('(') || text.contains(')')) {
      weight += 0.1;
    }

    return math.min(2.6, weight);
  }

  int _boundedMicros(
    int micros, {
    required int remainingMicros,
    required int wordsLeft,
  }) {
    final minimumForRest = wordsLeft;
    final maximum = remainingMicros - minimumForRest;
    return micros.clamp(1, maximum);
  }
}
