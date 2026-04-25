import 'package:flutter_test/flutter_test.dart';
import 'package:pizza_reader/src/reader/word_tokenizer.dart';

void main() {
  group('WordTokenizer', () {
    test('creates word offsets and pivot letters for fast reading', () {
      const tokenizer = WordTokenizer();
      final map = tokenizer.tokenize('"Hello," world\nsupercalifragilistic!');

      expect(map.words, hasLength(3));
      expect(map.words[0].text, '"Hello,"');
      expect(map.words[0].startOffset, 0);
      expect(map.words[0].endOffset, 8);
      expect(map.words[0].pivotLetter, 'e');
      expect(map.words[0].pivotTextOffset, 2);
      expect(map.words[2].pivotLetter, 'r');
    });

    test('maps text offsets to word indexes for jumps', () {
      const tokenizer = WordTokenizer();
      final map = tokenizer.tokenize('alpha  beta\ngamma');

      expect(map.wordIndexForTextOffset(0), 0);
      expect(map.wordIndexForTextOffset(5), 1);
      expect(map.wordIndexForTextOffset(7), 1);
      expect(map.wordIndexForTextOffset(13), 2);
      expect(map.wordIndexForTextOffset(999), 2);
      expect(map.wordIndexForTextOffset(-20), 0);
    });
  });
}
