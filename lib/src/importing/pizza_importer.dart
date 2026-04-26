import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;

import '../core/pizza_book.dart';
import '../core/pizza_book_codec.dart';

const pizzaImportPickerExtensions = <String>[
  'pizzabook',
  'epub',
  'txt',
  'md',
  'markdown',
  'html',
  'htm',
  'fb2',
  'mobi',
  'azw',
  'azw3',
];

enum PizzaImportKind { pizzaBook, text, markdown, html, epub, fb2, mobi, azw }

class PizzaImporter {
  const PizzaImporter();

  PizzaBook importBytes(
    List<int> bytes, {
    required String fileName,
    PizzaImportKind? kind,
    String? title,
  }) {
    final resolvedKind = kind ?? _kindFromFileName(fileName);
    switch (resolvedKind) {
      case PizzaImportKind.pizzaBook:
        return const PizzaBookCodec().decodeBytes(bytes);
      case PizzaImportKind.text:
        return _bookFromSingleText(
          utf8.decode(bytes, allowMalformed: false),
          fileName: fileName,
          title: title,
          sourceKind: 'txt',
        );
      case PizzaImportKind.markdown:
        return _bookFromSingleText(
          _markdownToPlainText(utf8.decode(bytes, allowMalformed: false)),
          fileName: fileName,
          title: title,
          sourceKind: 'md',
        );
      case PizzaImportKind.html:
        return _importHtml(bytes, fileName: fileName, title: title);
      case PizzaImportKind.epub:
        return _importEpub(bytes, fileName: fileName, title: title);
      case PizzaImportKind.fb2:
        return _importFb2(bytes, fileName: fileName, title: title);
      case PizzaImportKind.mobi:
      case PizzaImportKind.azw:
        throw UnsupportedError(
          'MOBI/AZW import is not supported yet. Convert the book to EPUB, '
          'FB2, TXT, Markdown, or HTML before importing.',
        );
    }
  }

  PizzaBook _importHtml(
    List<int> bytes, {
    required String fileName,
    String? title,
  }) {
    final source = utf8.decode(bytes, allowMalformed: false);
    final htmlTitle = _htmlTitle(source);
    return _bookFromSingleText(
      _htmlToText(source),
      fileName: fileName,
      title: title ?? htmlTitle,
      sourceKind: 'html',
    );
  }

  PizzaBook _importEpub(
    List<int> bytes, {
    required String fileName,
    String? title,
  }) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final containerXml = _readArchiveText(archive, 'META-INF/container.xml');
    if (containerXml == null) {
      throw const FormatException('EPUB is missing META-INF/container.xml.');
    }

    final container = xml.XmlDocument.parse(containerXml);
    final rootFile = _firstElement(
      container,
      (element) =>
          element.name.local == 'rootfile' &&
          element.getAttribute('full-path') != null,
    );
    final opfPath = rootFile?.getAttribute('full-path');
    if (opfPath == null || opfPath.trim().isEmpty) {
      throw const FormatException(
        'EPUB container does not point to an OPF file.',
      );
    }

    final opfSource = _readArchiveText(archive, opfPath);
    if (opfSource == null) {
      throw FormatException('EPUB OPF file "$opfPath" is missing.');
    }

    final opf = xml.XmlDocument.parse(opfSource);
    final basePath = _directoryName(opfPath);
    final metadata = _epubMetadata(opf);
    final bookTitle = title ?? metadata.title;
    final manifest = _epubManifest(opf);
    final spineIds = _epubSpineIds(opf);
    final orderedItems = spineIds
        .map((id) => manifest[id])
        .whereType<_EpubManifestItem>()
        .where((item) => item.isReadableDocument)
        .toList();

    final readableItems = orderedItems.isEmpty
        ? manifest.values.where((item) => item.isReadableDocument).toList()
        : orderedItems;

    final chapters = <PizzaChapter>[];
    for (final item in readableItems) {
      final path = _resolveArchivePath(basePath, item.href);
      final document = _readArchiveText(archive, path);
      if (document == null) {
        continue;
      }

      final text = _htmlToText(document);
      if (text.isEmpty) {
        continue;
      }

      chapters.add(
        PizzaChapter(
          id: 'chapter-${chapters.length + 1}',
          title: _htmlTitle(document) ?? 'Chapter ${chapters.length + 1}',
          text: text,
        ),
      );
    }

    if (chapters.isEmpty) {
      throw const FormatException('EPUB does not contain readable chapters.');
    }

    return _bookFromChapters(
      chapters,
      fileName: fileName,
      title: _cleanTitle(bookTitle, fileName),
      sourceKind: 'epub',
      author: metadata.author,
      language: metadata.language,
    );
  }

  PizzaBook _importFb2(
    List<int> bytes, {
    required String fileName,
    String? title,
  }) {
    final source = utf8.decode(bytes, allowMalformed: false);
    final document = xml.XmlDocument.parse(source);
    final metadata = _fb2Metadata(document);
    final chapters = <PizzaChapter>[];

    for (final section in _fb2ReadableSections(document)) {
      final text = _fb2SectionText(section);
      if (text.isEmpty) {
        continue;
      }

      chapters.add(
        PizzaChapter(
          id: 'chapter-${chapters.length + 1}',
          title: _fb2SectionTitle(section) ?? 'Chapter ${chapters.length + 1}',
          text: text,
        ),
      );
    }

    if (chapters.isEmpty) {
      throw const FormatException('FB2 does not contain readable sections.');
    }

    return _bookFromChapters(
      chapters,
      fileName: fileName,
      title: _cleanTitle(title ?? metadata.title, fileName),
      sourceKind: 'fb2',
      author: metadata.author,
      language: metadata.language,
    );
  }

  PizzaBook _bookFromSingleText(
    String text, {
    required String fileName,
    required String sourceKind,
    String? title,
  }) {
    final normalized = _normalizeImportedText(text);
    if (normalized.isEmpty) {
      throw const FormatException('Imported document is empty.');
    }

    final bookTitle = _cleanTitle(title, fileName);
    return _bookFromChapters(
      <PizzaChapter>[
        PizzaChapter(id: 'chapter-1', title: bookTitle, text: normalized),
      ],
      fileName: fileName,
      title: bookTitle,
      sourceKind: sourceKind,
    );
  }

  PizzaBook _bookFromChapters(
    List<PizzaChapter> chapters, {
    required String fileName,
    required String title,
    required String sourceKind,
    String? author,
    String? language,
  }) {
    final textFingerprint = chapters
        .map((chapter) => chapter.text)
        .join('\n\n');
    final id = _stableId(sourceKind, title, textFingerprint);
    final book = PizzaBook(
      id: id,
      title: title,
      author: author,
      language: language,
      chapters: chapters,
      metadata: <String, Object?>{
        'source_file': _baseName(fileName),
        'source_kind': sourceKind,
      },
    );
    book.validate();
    return book;
  }
}

class _EpubManifestItem {
  const _EpubManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
  });

  final String id;
  final String href;
  final String mediaType;

  bool get isReadableDocument {
    final type = mediaType.toLowerCase();
    final lowerHref = href.toLowerCase();
    return type.contains('html') ||
        lowerHref.endsWith('.html') ||
        lowerHref.endsWith('.htm') ||
        lowerHref.endsWith('.xhtml');
  }
}

class _BookMetadata {
  const _BookMetadata({this.title, this.author, this.language});

  final String? title;
  final String? author;
  final String? language;
}

PizzaImportKind _kindFromFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pizzabook')) {
    return PizzaImportKind.pizzaBook;
  }
  if (lower.endsWith('.txt')) {
    return PizzaImportKind.text;
  }
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
    return PizzaImportKind.markdown;
  }
  if (lower.endsWith('.html') || lower.endsWith('.htm')) {
    return PizzaImportKind.html;
  }
  if (lower.endsWith('.epub')) {
    return PizzaImportKind.epub;
  }
  if (lower.endsWith('.fb2')) {
    return PizzaImportKind.fb2;
  }
  if (lower.endsWith('.mobi')) {
    return PizzaImportKind.mobi;
  }
  if (lower.endsWith('.azw') || lower.endsWith('.azw3')) {
    return PizzaImportKind.azw;
  }
  throw FormatException('Unsupported import file type for "$fileName".');
}

_BookMetadata _epubMetadata(xml.XmlDocument opf) {
  final metadata = _firstElement(
    opf,
    (element) => element.name.local == 'metadata',
  );

  return _BookMetadata(
    title: _firstElementText(metadata, 'title'),
    author: _firstElementText(metadata, 'creator'),
    language: _firstElementText(metadata, 'language'),
  );
}

Map<String, _EpubManifestItem> _epubManifest(xml.XmlDocument opf) {
  final manifest = <String, _EpubManifestItem>{};
  for (final element in opf.descendants.whereType<xml.XmlElement>()) {
    if (element.name.local != 'item') {
      continue;
    }

    final id = element.getAttribute('id');
    final href = element.getAttribute('href');
    if (id == null || href == null) {
      continue;
    }

    manifest[id] = _EpubManifestItem(
      id: id,
      href: href,
      mediaType: element.getAttribute('media-type') ?? '',
    );
  }
  return manifest;
}

List<String> _epubSpineIds(xml.XmlDocument opf) {
  final ids = <String>[];
  for (final element in opf.descendants.whereType<xml.XmlElement>()) {
    if (element.name.local == 'itemref') {
      final idref = element.getAttribute('idref');
      if (idref != null && idref.isNotEmpty) {
        ids.add(idref);
      }
    }
  }
  return ids;
}

xml.XmlElement? _fb2TitleInfo(xml.XmlDocument document) {
  final description = _firstElement(
    document,
    (element) => element.name.local == 'description',
  );
  return _firstElement(
    description,
    (element) => element.name.local == 'title-info',
  );
}

_BookMetadata _fb2Metadata(xml.XmlDocument document) {
  final titleInfo = _fb2TitleInfo(document);
  return _BookMetadata(
    title: _firstElementText(titleInfo, 'book-title'),
    author: _fb2Authors(titleInfo),
    language: _firstElementText(titleInfo, 'lang'),
  );
}

String? _fb2Authors(xml.XmlElement? titleInfo) {
  if (titleInfo == null) {
    return null;
  }

  final authors = titleInfo.children
      .whereType<xml.XmlElement>()
      .where((element) => element.name.local == 'author')
      .map(_fb2AuthorName)
      .whereType<String>()
      .toList();
  if (authors.isEmpty) {
    return null;
  }
  return authors.join(', ');
}

String? _fb2AuthorName(xml.XmlElement author) {
  final nameParts = <String>[
    ?_firstElementText(author, 'first-name'),
    ?_firstElementText(author, 'middle-name'),
    ?_firstElementText(author, 'last-name'),
  ];
  if (nameParts.isNotEmpty) {
    return nameParts.join(' ');
  }

  final nickname = _firstElementText(author, 'nickname');
  if (nickname != null) {
    return nickname;
  }

  return _cleanMetadataText(author.innerText);
}

Iterable<xml.XmlElement> _fb2ReadableSections(xml.XmlDocument document) sync* {
  final bodies = document.descendants.whereType<xml.XmlElement>().where((
    element,
  ) {
    if (element.name.local != 'body') {
      return false;
    }
    final name = element.getAttribute('name')?.toLowerCase();
    return name != 'notes' && name != 'comments';
  });

  for (final body in bodies) {
    yield* body.descendants.whereType<xml.XmlElement>().where(
      (element) => element.name.local == 'section',
    );
  }
}

String? _fb2SectionTitle(xml.XmlElement section) {
  for (final child in section.children.whereType<xml.XmlElement>()) {
    if (child.name.local != 'title') {
      continue;
    }

    final blocks = <String>[];
    for (final titleChild in child.children.whereType<xml.XmlElement>()) {
      blocks.addAll(_fb2TextBlocks(titleChild));
    }
    final title =
        _cleanMetadataText(blocks.join(' ')) ??
        _cleanMetadataText(child.innerText);
    if (title != null && title.isNotEmpty) {
      return title;
    }
  }
  return null;
}

String _fb2SectionText(xml.XmlElement section) {
  final blocks = <String>[];
  for (final child in section.children.whereType<xml.XmlElement>()) {
    final localName = child.name.local;
    if (localName == 'title' || localName == 'section') {
      continue;
    }
    blocks.addAll(_fb2TextBlocks(child));
  }
  return _normalizeImportedText(blocks.join('\n\n'));
}

List<String> _fb2TextBlocks(xml.XmlElement element) {
  final localName = element.name.local;
  if (_fb2IgnoredTextTags.contains(localName)) {
    return const <String>[];
  }

  if (_fb2TextBlockTags.contains(localName)) {
    final text = _cleanMetadataText(element.innerText);
    return text == null ? const <String>[] : <String>[text];
  }

  final blocks = <String>[];
  for (final child in element.children.whereType<xml.XmlElement>()) {
    blocks.addAll(_fb2TextBlocks(child));
  }
  if (blocks.isNotEmpty) {
    return blocks;
  }

  final text = _cleanMetadataText(element.innerText);
  return text == null ? const <String>[] : <String>[text];
}

xml.XmlElement? _firstElement(
  xml.XmlNode? node,
  bool Function(xml.XmlElement element) test,
) {
  if (node == null) {
    return null;
  }
  for (final element in node.descendants.whereType<xml.XmlElement>()) {
    if (test(element)) {
      return element;
    }
  }
  return null;
}

String? _firstElementText(xml.XmlNode? node, String localName) {
  final element = _firstElement(
    node,
    (element) => element.name.local == localName,
  );
  return _cleanMetadataText(element?.innerText);
}

String? _readArchiveText(Archive archive, String path) {
  ArchiveFile? file = archive.find(path);
  file ??= archive.find(_normalizeArchivePath(path));
  if (file == null) {
    for (final entry in archive.files) {
      if (_normalizeArchivePath(entry.name) == _normalizeArchivePath(path)) {
        file = entry;
        break;
      }
    }
  }

  final bytes = file?.readBytes();
  if (bytes == null) {
    return null;
  }
  return utf8.decode(bytes, allowMalformed: false);
}

String? _htmlTitle(String source) {
  final document = html_parser.parse(source);
  final title = document.querySelector('title')?.text.trim();
  if (title != null && title.isNotEmpty) {
    return title;
  }
  final heading = document.querySelector('h1')?.text.trim();
  if (heading != null && heading.isNotEmpty) {
    return heading;
  }
  return null;
}

String _htmlToText(String source) {
  final document = html_parser.parse(source);
  final root = document.body ?? document.documentElement ?? document;
  final buffer = StringBuffer();

  void visit(dom.Node node) {
    if (node is dom.Text) {
      buffer.write(node.text);
      buffer.write(' ');
      return;
    }

    if (node is dom.Element) {
      final tag = node.localName ?? '';
      if (_skippedHtmlTags.contains(tag)) {
        return;
      }
      if (tag == 'br') {
        buffer.writeln();
        return;
      }
      if (_blockHtmlTags.contains(tag)) {
        buffer.writeln();
      }
      for (final child in node.nodes) {
        visit(child);
      }
      if (_blockHtmlTags.contains(tag)) {
        buffer.writeln();
      }
      return;
    }

    for (final child in node.nodes) {
      visit(child);
    }
  }

  visit(root);
  return _normalizeImportedText(buffer.toString());
}

String _markdownToPlainText(String source) {
  var text = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = text.replaceFirst(RegExp(r'^---\n[\s\S]*?\n---\n?'), '');
  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*\d+[.)]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'[*_`~]+'), '');
  return _normalizeImportedText(text);
}

String _normalizeImportedText(String text) {
  final normalizedLines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .toList();
  return normalizedLines
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _cleanTitle(String? title, String fileName) {
  final cleaned = _cleanMetadataText(title);
  if (cleaned != null && cleaned.isNotEmpty) {
    return cleaned;
  }
  return _baseNameWithoutExtension(fileName);
}

String _stableId(String sourceKind, String title, String text) {
  final digest = sha256.convert(utf8.encode('$sourceKind\n$title\n$text'));
  return '$sourceKind-${digest.toString().substring(0, 16)}';
}

String _baseNameWithoutExtension(String fileName) {
  final base = _baseName(fileName);
  final dot = base.lastIndexOf('.');
  final withoutExtension = dot <= 0 ? base : base.substring(0, dot);
  final title = withoutExtension
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return title.isEmpty ? 'Untitled' : title;
}

String? _cleanMetadataText(String? value) {
  if (value == null) {
    return null;
  }
  final cleaned = _normalizeImportedText(value);
  return cleaned.isEmpty ? null : cleaned;
}

String _baseName(String fileName) {
  final parts = fileName.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? fileName : parts.last;
}

String _directoryName(String path) {
  final slash = path.lastIndexOf('/');
  if (slash < 0) {
    return '';
  }
  return path.substring(0, slash);
}

String _resolveArchivePath(String basePath, String href) {
  final combined = basePath.isEmpty ? href : '$basePath/$href';
  return _normalizeArchivePath(combined);
}

String _normalizeArchivePath(String path) {
  final output = <String>[];
  for (final rawPart in path.split('/')) {
    final part = Uri.decodeComponent(rawPart);
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (output.isNotEmpty) {
        output.removeLast();
      }
      continue;
    }
    output.add(part);
  }
  return output.join('/');
}

const Set<String> _skippedHtmlTags = <String>{'script', 'style', 'noscript'};

const Set<String> _fb2IgnoredTextTags = <String>{
  'binary',
  'description',
  'image',
  'section',
  'title',
};

const Set<String> _fb2TextBlockTags = <String>{
  'date',
  'p',
  'subtitle',
  'td',
  'text-author',
  'th',
  'v',
};

const Set<String> _blockHtmlTags = <String>{
  'address',
  'article',
  'aside',
  'blockquote',
  'body',
  'dd',
  'div',
  'dl',
  'dt',
  'figcaption',
  'figure',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'li',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'td',
  'th',
  'tr',
  'ul',
};
