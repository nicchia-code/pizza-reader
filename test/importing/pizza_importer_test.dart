import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pizza_reader/src/core/pizza_book.dart';
import 'package:pizza_reader/src/core/pizza_book_codec.dart';
import 'package:pizza_reader/src/importing/pizza_importer.dart';

void main() {
  group('PizzaImporter', () {
    test('imports txt, markdown, html, and .pb bytes', () {
      const importer = PizzaImporter();

      final txt = importer.importBytes(
        utf8.encode('Plain pizza text.'),
        fileName: 'plain_text.txt',
      );
      expect(txt.title, 'plain text');
      expect(txt.chapters.single.text, 'Plain pizza text.');

      final markdown = importer.importBytes(
        utf8.encode(
          '# Heading\n\nThis is [pizza](https://example.com).\n- Fast',
        ),
        fileName: 'notes.md',
      );
      expect(markdown.chapters.single.text, contains('Heading'));
      expect(markdown.chapters.single.text, contains('This is pizza.'));
      expect(markdown.chapters.single.text, contains('Fast'));

      final html = importer.importBytes(
        utf8.encode(
          '<html><head><title>HTML Book</title><script>bad()</script></head>'
          '<body><h1>Chapter</h1><p>Hello <strong>pizza</strong>.</p></body></html>',
        ),
        fileName: 'book.html',
      );
      expect(html.title, 'HTML Book');
      expect(html.chapters.single.text, contains('Hello pizza .'));
      expect(html.chapters.single.text, isNot(contains('bad()')));

      const codec = PizzaBookCodec();
      final original = PizzaBook(
        id: 'pb-import',
        title: 'PB Import',
        chapters: const <PizzaChapter>[
          PizzaChapter(id: 'chapter-1', title: 'Only', text: 'PB text.'),
        ],
      );
      final pb = importer.importBytes(
        codec.encode(original),
        fileName: 'book.pb',
      );
      expect(pb.title, original.title);
      expect(pb.chapters.single.text, original.chapters.single.text);
    });

    test('imports a minimal EPUB spine in reading order', () {
      const importer = PizzaImporter();
      final book = importer.importBytes(
        _minimalEpub(),
        fileName: 'sample.epub',
      );

      expect(book.title, 'Sample EPUB');
      expect(book.author, 'Pat Pizzaiolo');
      expect(book.language, 'en');
      expect(book.chapters, hasLength(2));
      expect(book.chapters[0].title, 'Start');
      expect(book.chapters[0].text, contains('First pizza chapter.'));
      expect(book.chapters[1].title, 'End');
      expect(book.chapters[1].text, contains('Second pizza chapter.'));
    });

    test('imports FB2 metadata and readable sections', () {
      const importer = PizzaImporter();
      final book = importer.importBytes(_sampleFb2(), fileName: 'sample.fb2');

      expect(book.title, 'Sample FB2');
      expect(book.author, 'Ada Byron Lovelace');
      expect(book.language, 'en');
      expect(book.chapters, hasLength(2));
      expect(book.chapters[0].title, 'Dough');
      expect(book.chapters[0].text, contains('First FB2 paragraph.'));
      expect(book.chapters[0].text, contains('Second FB2 paragraph.'));
      expect(book.chapters[0].text, isNot(contains('Part One')));
      expect(book.chapters[1].title, 'Bake');
      expect(book.chapters[1].text, contains('Second FB2 chapter.'));
      expect(book.metadata['source_kind'], 'fb2');
    });

    test('returns clear UnsupportedError for MOBI and AZW', () {
      const importer = PizzaImporter();

      expect(
        () => importer.importBytes(Uint8List(0), fileName: 'book.mobi'),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('MOBI/AZW import is not supported yet'),
          ),
        ),
      );
      expect(
        () => importer.importBytes(Uint8List(0), fileName: 'book.azw3'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

Uint8List _minimalEpub() {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string('META-INF/container.xml', '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
    )
    ..addFile(
      ArchiveFile.string('OPS/package.opf', '''
<?xml version="1.0" encoding="utf-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Sample EPUB</dc:title>
    <dc:creator>Pat Pizzaiolo</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="chap-1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="chap-2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chap-1"/>
    <itemref idref="chap-2"/>
  </spine>
</package>
'''),
    )
    ..addFile(
      ArchiveFile.string('OPS/chapter1.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Start</title></head>
  <body><h1>Start</h1><p>First pizza chapter.</p></body>
</html>
'''),
    )
    ..addFile(
      ArchiveFile.string('OPS/chapter2.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>End</title></head>
  <body><h1>End</h1><p>Second pizza chapter.</p></body>
</html>
'''),
    );

  return ZipEncoder().encodeBytes(archive);
}

List<int> _sampleFb2() {
  return utf8.encode('''
<?xml version="1.0" encoding="utf-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
  <description>
    <title-info>
      <author>
        <first-name>Ada</first-name>
        <middle-name>Byron</middle-name>
        <last-name>Lovelace</last-name>
      </author>
      <book-title>Sample FB2</book-title>
      <lang>en</lang>
    </title-info>
  </description>
  <body>
    <section>
      <title><p>Part One</p></title>
      <section>
        <title><p>Dough</p></title>
        <p>First FB2 paragraph.</p>
        <p>Second FB2 paragraph.</p>
      </section>
      <section>
        <title><p>Bake</p></title>
        <p>Second FB2 chapter.</p>
      </section>
    </section>
  </body>
</FictionBook>
''');
}
