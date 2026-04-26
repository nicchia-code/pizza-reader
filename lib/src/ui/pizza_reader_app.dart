import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/pizza_book.dart';
import '../core/pizza_book_codec.dart';
import '../importing/pizza_importer.dart';
import '../reader/reader_controller.dart' as reader;
import '../reader/reading_pace.dart';
import '../reader/word_tokenizer.dart';
import '../supabase/supabase.dart';
import 'pizza_theme.dart';

class PizzaReaderApp extends StatelessWidget {
  PizzaReaderApp({
    super.key,
    AuthRepository? authRepository,
    LibraryRepository? libraryRepository,
    this.cloudEnabled = false,
  }) : authRepository = authRepository ?? FakeAuthRepository(),
       libraryRepository = libraryRepository ?? FakeLibraryRepository();

  final AuthRepository authRepository;
  final LibraryRepository libraryRepository;
  final bool cloudEnabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pizza Reader',
      theme: buildPizzaTheme(),
      home: PizzaReaderHome(
        authRepository: authRepository,
        libraryRepository: libraryRepository,
        cloudEnabled: cloudEnabled,
      ),
    );
  }
}

class PizzaReaderLoadingApp extends StatelessWidget {
  const PizzaReaderLoadingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pizza Reader',
      theme: buildPizzaTheme(),
      home: const _PizzaLoadingScreen(),
    );
  }
}

class PizzaReaderStartupErrorApp extends StatelessWidget {
  const PizzaReaderStartupErrorApp({super.key, required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pizza Reader',
      theme: buildPizzaTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: PizzaColors.tomatoDeep,
                    size: 42,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Avvio non riuscito',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: PizzaColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PizzaLoadingScreen extends StatelessWidget {
  const _PizzaLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: PizzaColors.paper,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/brand/pizzalogo.png', width: 96, height: 96),
              const SizedBox(height: 22),
              Text(
                'Pizza Reader',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PizzaReaderHome extends StatefulWidget {
  const PizzaReaderHome({
    super.key,
    required this.authRepository,
    required this.libraryRepository,
    required this.cloudEnabled,
  });

  final AuthRepository authRepository;
  final LibraryRepository libraryRepository;
  final bool cloudEnabled;

  @override
  State<PizzaReaderHome> createState() => _PizzaReaderHomeState();
}

class _PizzaReaderHomeState extends State<PizzaReaderHome> {
  final _codec = const PizzaBookCodec();
  final _importer = const PizzaImporter();
  final _tokenizer = const WordTokenizer();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _workspaceRevision = ValueNotifier<int>(0);

  Timer? _timer;
  late PizzaBook _book;
  late reader.ReaderController _reader;
  var _mode = reader.ReaderMode.auto;
  var _wpm = 200.0;
  var _isPlaying = false;
  var _textMapOpen = false;
  var _importBusy = false;
  var _authBusy = false;
  var _codeSent = false;
  var _showReadingTime = false;
  var _status = 'Importa un ebook o prova il testo locale';
  String? _importError;
  var _libraryBooks = <LibraryBook>[];

  @override
  void initState() {
    super.initState();
    _book = _starterBook();
    _reader = _newReaderFor(_book, initialMode: _mode);
    _loadLibrary();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _workspaceRevision.dispose();
    _emailController.dispose();
    _otpController.dispose();
    final auth = widget.authRepository;
    if (auth is FakeAuthRepository) {
      auth.dispose();
    }
    super.dispose();
  }

  reader.ReaderController _newReaderFor(
    PizzaBook book, {
    required reader.ReaderMode initialMode,
  }) {
    return reader.ReaderController(
      book,
      pace: ReadingPace(wordsPerMinute: _wpm.round()),
      initialMode: initialMode,
      tokenizer: _tokenizer,
    );
  }

  void _replaceBook(PizzaBook book) {
    _timer?.cancel();
    _setStateAndRefreshWorkspace(() {
      _book = book;
      _reader = _newReaderFor(book, initialMode: _mode);
      _isPlaying = false;
      _textMapOpen = false;
      _status = '${book.title} pronto';
    });
  }

  Future<void> _loadLibrary() async {
    try {
      final books = await widget.libraryRepository.listBooks();
      if (!mounted) {
        return;
      }
      _setStateAndRefreshWorkspace(() => _libraryBooks = books);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _setStateAndRefreshWorkspace(() => _libraryBooks = const []);
    }
  }

  void _applyLibraryTitleLocally(
    String bookId,
    String title, {
    String? status,
  }) {
    _setStateAndRefreshWorkspace(() {
      _libraryBooks = [
        for (final stored in _libraryBooks)
          stored.id == bookId ? stored.copyWith(title: title) : stored,
      ];
      if (_book.id == bookId) {
        _book = _book.copyWith(title: title);
      }
      if (status != null) {
        _status = status;
      }
    });
  }

  void _setStateAndRefreshWorkspace(VoidCallback update) {
    setState(update);
    _workspaceRevision.value++;
  }

  Future<void> _importBook() async {
    if (_importBusy) {
      return;
    }
    setState(() {
      _importBusy = true;
      _importError = null;
      _status = 'Scelta file in corso';
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const [
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
        ],
      );

      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) {
        setState(() {
          _status = 'Import annullato';
          _importBusy = false;
          _importError = null;
        });
        return;
      }

      final book = _importer.importBytes(bytes, fileName: file.name);
      final readerBytes = _codec.encode(book);
      await widget.libraryRepository.uploadBook(
        bytes: readerBytes,
        title: book.title,
        author: book.author,
        sourceFileName: file.name,
        bookId: book.id,
      );

      _replaceBook(book);
      await _loadLibrary();
      setState(() {
        _status = 'Importato ${file.name}';
        _importBusy = false;
        _importError = null;
      });
    } on UnsupportedError catch (error) {
      setState(() {
        _importError = error.message ?? 'Formato non supportato';
        _status = _importError!;
        _importBusy = false;
      });
    } on Object catch (error) {
      setState(() {
        _importError = 'Import fallito: $error';
        _status = _importError!;
        _importBusy = false;
      });
    }
  }

  Future<void> _confirmDeleteLibraryBook(LibraryBook book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Elimina libro'),
          content: Text(
            'Vuoi eliminare "${book.title}" dalla libreria? '
            'L\'azione non puo essere annullata.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Elimina'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteLibraryBook(book);
    }
  }

  Future<void> _renameLibraryBook(LibraryBook book) async {
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => _RenameBookDialog(initialTitle: book.title),
    );

    final title = newTitle?.trim();
    if (title == null || title.isEmpty || title == book.title.trim()) {
      return;
    }

    _stopTimedReading();
    _applyLibraryTitleLocally(book.id, title, status: 'Rinominato in $title');

    try {
      PizzaBook? renamedReaderBook;
      try {
        final bytes = await widget.libraryRepository.downloadBookBytes(book);
        final decodedBook = _codec.decodeBytes(bytes);
        renamedReaderBook = decodedBook.copyWith(title: title);
        await widget.libraryRepository.uploadBook(
          bytes: _codec.encode(renamedReaderBook),
          title: title,
          author: renamedReaderBook.author,
          sourceFileName: book.sourceFileName,
          bookId: book.id,
        );
      } on Object {
        await widget.libraryRepository.upsertBookMetadata(
          book.copyWith(title: title),
        );
        if (book.id == _book.id) {
          renamedReaderBook = _book.copyWith(title: title);
        }
      }

      await _loadLibrary();
      if (!mounted) {
        return;
      }
      if (book.id == _book.id && renamedReaderBook != null) {
        _setStateAndRefreshWorkspace(() => _book = renamedReaderBook!);
      }
      _setStateAndRefreshWorkspace(() {
        _status = 'Rinominato in $title';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      await _loadLibrary();
      if (book.id == _book.id) {
        _setStateAndRefreshWorkspace(
          () => _book = _book.copyWith(title: book.title),
        );
      }
      _setStateAndRefreshWorkspace(() {
        _status = 'Rinomina fallita: $error';
      });
    }
  }

  Future<void> _openLibraryBook(LibraryBook book) async {
    if (book.id == _book.id) {
      return;
    }

    _stopTimedReading();
    _setStateAndRefreshWorkspace(() {
      _status = 'Apro ${book.title}';
      _importError = null;
    });

    try {
      final bytes = await widget.libraryRepository.downloadBookBytes(book);
      final selectedBook = _codec.decodeBytes(bytes);
      if (!mounted) {
        return;
      }
      _replaceBook(selectedBook);
      _setStateAndRefreshWorkspace(() {
        _status = 'Aperto ${selectedBook.title}';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _setStateAndRefreshWorkspace(() {
        _status = 'Apertura fallita: $error';
      });
    }
  }

  Future<void> _deleteLibraryBook(LibraryBook book) async {
    _stopTimedReading();
    _setStateAndRefreshWorkspace(() {
      _status = 'Elimino ${book.title}';
    });

    try {
      final wasActive = book.id == _book.id;
      await widget.libraryRepository.deleteBook(book.id);
      await _loadLibrary();
      if (!mounted) {
        return;
      }
      if (wasActive) {
        _replaceBook(_starterBook());
      }
      _setStateAndRefreshWorkspace(() {
        _status = 'Eliminato ${book.title}';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _setStateAndRefreshWorkspace(() {
        _status = 'Eliminazione fallita: $error';
      });
    }
  }

  Future<void> _sendMagicCode() async {
    if (_authBusy) {
      return;
    }
    _setStateAndRefreshWorkspace(() {
      _authBusy = true;
      _status = 'Invio codice';
    });
    try {
      await widget.authRepository.sendMagicCode(_emailController.text);
      _setStateAndRefreshWorkspace(() {
        _codeSent = true;
        _status = 'Codice inviato a ${normalizeEmail(_emailController.text)}';
      });
    } on Object catch (error) {
      _setStateAndRefreshWorkspace(() => _status = 'Login: $error');
    } finally {
      if (mounted) {
        _setStateAndRefreshWorkspace(() => _authBusy = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (_authBusy) {
      return;
    }
    _setStateAndRefreshWorkspace(() {
      _authBusy = true;
      _status = 'Verifica codice';
    });
    try {
      await widget.authRepository.verifyEmailOtp(
        _emailController.text,
        _otpController.text,
      );
      await _loadLibrary();
      _setStateAndRefreshWorkspace(() {
        _codeSent = false;
        _otpController.clear();
        _status = 'Login completato';
      });
    } on Object catch (error) {
      _setStateAndRefreshWorkspace(() => _status = 'Codice non valido: $error');
    } finally {
      if (mounted) {
        _setStateAndRefreshWorkspace(() => _authBusy = false);
      }
    }
  }

  Future<void> _signOut() async {
    if (_authBusy) {
      return;
    }
    _setStateAndRefreshWorkspace(() {
      _authBusy = true;
      _status = 'Logout in corso';
    });
    try {
      await widget.authRepository.signOut();
      await _loadLibrary();
      _setStateAndRefreshWorkspace(() {
        _codeSent = false;
        _otpController.clear();
        _status = 'Logout completato';
      });
    } finally {
      if (mounted) {
        _setStateAndRefreshWorkspace(() => _authBusy = false);
      }
    }
  }

  void _setMode(reader.ReaderMode mode) {
    _stopTimedReading();
    setState(() {
      _mode = mode;
      _reader.setMode(mode);
      _status = switch (mode) {
        reader.ReaderMode.hold => 'Hold: tieni premuto per leggere',
        reader.ReaderMode.auto => 'Auto pronta',
        reader.ReaderMode.manual => 'Manual: un tap per parola',
      };
    });
  }

  void _setWpm(double value) {
    final position = _reader.position;
    final wasPlaying = _isPlaying;
    _timer?.cancel();
    setState(() {
      _wpm = value;
      _reader = _newReaderFor(_book, initialMode: _mode);
      _reader.seekChapter(position.chapterIndex, wordIndex: position.wordIndex);
      _status = '${value.round()} WPM';
      _isPlaying = false;
    });
    if (wasPlaying && _mode == reader.ReaderMode.auto) {
      _startTimedReading(reader.ReaderMode.auto);
    }
  }

  void _toggleSpeedReadout() {
    setState(() => _showReadingTime = !_showReadingTime);
  }

  _SpeedReadoutValue _speedReadoutValue() {
    if (_showReadingTime) {
      final durationLabel = _durationLabelForChapter(
        _reader.position.chapterIndex,
      );
      return _SpeedReadoutValue(
        primary: durationLabel,
        secondary: 'tempo',
        inline: durationLabel,
        tooltip: 'Mostra WPM',
      );
    }

    final wpm = _wpm.round();
    return _SpeedReadoutValue(
      primary: '$wpm',
      secondary: 'WPM',
      inline: '$wpm WPM',
      tooltip: 'Mostra tempo',
    );
  }

  void _toggleAuto() {
    if (_mode != reader.ReaderMode.auto) {
      _setMode(reader.ReaderMode.auto);
    }
    if (_isPlaying) {
      _stopTimedReading();
    } else {
      _startTimedReading(reader.ReaderMode.auto);
    }
  }

  void _startTimedReading(reader.ReaderMode mode) {
    _timer?.cancel();
    setState(() {
      _mode = mode;
      _reader.setMode(mode);
      _isPlaying = true;
      _status = mode == reader.ReaderMode.hold
          ? 'Hold attivo a ${_wpm.round()} WPM'
          : 'Auto a ${_wpm.round()} WPM';
    });
    _scheduleNextTick();
  }

  void _stopTimedReading() {
    _timer?.cancel();
    _timer = null;
    if (_isPlaying) {
      setState(() => _isPlaying = false);
    }
  }

  void _scheduleNextTick() {
    if (!_isPlaying || _reader.isCompleted) {
      _stopTimedReading();
      return;
    }
    final duration = _reader.currentWordDuration;
    _timer = Timer(duration, () {
      if (!mounted || !_isPlaying) {
        return;
      }
      setState(() {
        _reader.tick(duration);
        if (_reader.isCompleted) {
          _status = 'Fine libro';
        }
      });
      _scheduleNextTick();
    });
  }

  void _nextWord() {
    setState(() {
      if (_mode == reader.ReaderMode.manual) {
        _reader.manualNext();
      } else {
        _reader.next();
      }
    });
  }

  void _previousWord() {
    setState(() {
      if (_mode == reader.ReaderMode.manual) {
        _reader.manualPrevious();
      } else {
        _reader.previous();
      }
    });
  }

  void _selectChapterInBook(int index) {
    _stopTimedReading();
    setState(() {
      _reader.seekChapter(index);
      _textMapOpen = false;
      _status = '${_book.chapters[index].title} selezionato';
    });
  }

  void _jumpToOffset(int offset) {
    _stopTimedReading();
    setState(() {
      _reader.seekTextOffset(offset);
      _textMapOpen = false;
      _status = 'Jump alla parola ${_reader.position.wordIndex + 1}';
    });
  }

  void _toggleTextMap() {
    setState(() => _textMapOpen = !_textMapOpen);
  }

  void _closeTextMap() {
    setState(() => _textMapOpen = false);
  }

  WordMap _wordMapForChapter(int chapterIndex) {
    return _tokenizer.tokenize(_book.chapters[chapterIndex].text);
  }

  String _durationLabelForChapter(int chapterIndex) {
    final words = _wordMapForChapter(chapterIndex).words;
    final durations = ReadingPace(
      wordsPerMinute: _wpm.round(),
    ).durationsFor(words);
    final micros = durations.fold<int>(
      0,
      (total, duration) => total + duration.inMicroseconds,
    );
    return _formatReadingDuration(Duration(microseconds: micros));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      body: CustomPaint(
        painter: const _ReaderBackgroundPainter(),
        child: SafeArea(
          child: wide ? _buildWideLayout(context) : _buildNarrowLayout(context),
        ),
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 288,
          child: _LibraryRail(
            book: _book,
            libraryBooks: _libraryBooks,
            onOpenBook: _openLibraryBook,
            onRenameBook: _renameLibraryBook,
            onDeleteBook: _confirmDeleteLibraryBook,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _ReaderStage(state: this)),
        const VerticalDivider(width: 1),
        SizedBox(width: 352, child: _ControlRail(state: this)),
      ],
    );
  }

  Widget _buildNarrowLayout(BuildContext context) {
    return Column(
      children: [
        _MobileHeader(
          book: _book,
          importBusy: _importBusy,
          importError: _importError,
          onOpenWorkspace: _openMobileWorkspace,
        ),
        const Divider(height: 1),
        Expanded(child: _ReaderStage(state: this, compact: true)),
        const Divider(height: 1),
        _MobileControls(state: this),
      ],
    );
  }

  void _openMobileWorkspace() {
    _stopTimedReading();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PizzaColors.paper,
      constraints: const BoxConstraints(maxWidth: 680),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => _MobileWorkspaceSheet(state: this),
    );
  }
}

class _ReaderStage extends StatelessWidget {
  const _ReaderStage({required this.state, this.compact = false});

  final _PizzaReaderHomeState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final chapter = state._reader.currentChapter;
    final wordMap = state._reader.currentWordMap;
    final progress = wordMap.words.isEmpty
        ? 0.0
        : (state._reader.position.wordIndex + 1) / wordMap.words.length;
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 32,
            compact ? 14 : 28,
            compact ? 16 : 32,
            compact ? 16 : 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReaderTopBar(
                title: chapter.title,
                progress:
                    '${state._reader.position.wordIndex + 1} / ${wordMap.words.length} parole',
                status: state._status,
                onOpenText: state._toggleTextMap,
              ),
              const SizedBox(height: 18),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: state._mode == reader.ReaderMode.manual
                      ? state._nextWord
                      : null,
                  child: Center(
                    child: _WordFocusDisplay(
                      word: state._reader.currentWord,
                      progress: progress,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _ReaderTransport(state: state),
            ],
          ),
        ),
        if (state._textMapOpen)
          Positioned.fill(
            child: _NormalTextOverlay(
              book: state._book,
              activeChapterIndex: state._reader.position.chapterIndex,
              durationLabelForChapter: state._durationLabelForChapter,
              wordMap: wordMap,
              activeWordIndex: state._reader.position.wordIndex,
              onClose: state._closeTextMap,
              onChapterSelected: state._selectChapterInBook,
              onJump: state._jumpToOffset,
            ),
          ),
      ],
    );
  }
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.title,
    required this.progress,
    required this.status,
    required this.onOpenText,
  });

  final String title;
  final String progress;
  final String status;
  final VoidCallback onOpenText;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '$progress - $status',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: PizzaColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: 'Apri libro',
          child: IconButton.filledTonal(
            onPressed: onOpenText,
            icon: const Icon(Icons.menu_book_rounded),
          ),
        ),
      ],
    );
  }
}

class _WordFocusDisplay extends StatelessWidget {
  const _WordFocusDisplay({required this.word, required this.progress});

  final ReadingWord word;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final focusHeight = constraints.maxHeight < 72
            ? constraints.maxHeight
            : math.min(184.0, math.max(72.0, constraints.maxHeight - 32));
        final fontSize = math.min(
          86.0,
          math.max(
            20.0,
            math.min(
              focusHeight * 0.46,
              constraints.maxWidth / math.max(6, word.text.length) * 1.25,
            ),
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: math.min(760, constraints.maxWidth),
              height: focusHeight,
              child: CustomPaint(
                painter: _WordContourPainter(progress: progress),
                child: Center(
                  child: _PivotWord(word: word, fontSize: fontSize),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PivotWord extends StatelessWidget {
  const _PivotWord({required this.word, required this.fontSize});

  final ReadingWord word;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final text = word.text;
    final pivot = word.pivotIndex
        .clamp(0, math.max(0, text.length - 1))
        .toInt();
    final before = text.substring(0, pivot);
    final letter = text.isEmpty ? '' : text.substring(pivot, pivot + 1);
    final after = text.isEmpty ? '' : text.substring(pivot + 1);

    TextStyle base(Color color) => TextStyle(
      color: color,
      fontSize: fontSize,
      height: 1,
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
    );

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Semantics(
        label: text,
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(text: before, style: base(PizzaColors.ink)),
              TextSpan(text: letter, style: base(PizzaColors.tomato)),
              TextSpan(text: after, style: base(PizzaColors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderTransport extends StatelessWidget {
  const _ReaderTransport({required this.state});

  final _PizzaReaderHomeState state;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.center,
      children: [
        Tooltip(
          message: 'Parola precedente',
          child: IconButton.outlined(
            onPressed: state._previousWord,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
        ),
        _PrimaryReaderButton(state: state),
        Tooltip(
          message: 'Parola successiva',
          child: IconButton.outlined(
            onPressed: state._nextWord,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ),
      ],
    );
  }
}

class _PrimaryReaderButton extends StatelessWidget {
  const _PrimaryReaderButton({required this.state});

  final _PizzaReaderHomeState state;

  @override
  Widget build(BuildContext context) {
    if (state._mode == reader.ReaderMode.hold) {
      return Listener(
        onPointerDown: (_) => state._startTimedReading(reader.ReaderMode.hold),
        onPointerUp: (_) => state._stopTimedReading(),
        onPointerCancel: (_) => state._stopTimedReading(),
        child: FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.touch_app_rounded),
          label: const Text('Hold'),
        ),
      );
    }

    final icon = state._mode == reader.ReaderMode.manual
        ? Icons.ads_click_rounded
        : state._isPlaying
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;
    final label = state._mode == reader.ReaderMode.manual
        ? 'Tap'
        : state._isPlaying
        ? 'Pausa'
        : 'Auto';
    return FilledButton.icon(
      onPressed: state._mode == reader.ReaderMode.manual
          ? state._nextWord
          : state._toggleAuto,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _ControlRail extends StatelessWidget {
  const _ControlRail({required this.state});

  final _PizzaReaderHomeState state;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PizzaColors.paper.withValues(alpha: 0.86),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _AuthPanel(state: state),
          const SizedBox(height: 20),
          _ImportPanel(
            busy: state._importBusy,
            error: state._importError,
            cloudEnabled: state.widget.cloudEnabled,
            onPressed: state._importBook,
          ),
          const SizedBox(height: 20),
          _SpeedPanel(state: state),
          const SizedBox(height: 20),
          _ModePanel(state: state),
        ],
      ),
    );
  }
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({required this.state});

  final _PizzaReaderHomeState state;

  @override
  Widget build(BuildContext context) {
    final user = state.widget.authRepository.currentUser;
    return _PanelShell(
      title: 'Accesso',
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      titleGap: 10,
      trailing: _EnvironmentBadge(cloudEnabled: state.widget.cloudEnabled),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: user == null
            ? _SignedOutAuthContent(
                key: const ValueKey('signed-out'),
                state: state,
              )
            : _SignedInAuthContent(
                key: const ValueKey('signed-in'),
                email: user.email ?? user.id,
                busy: state._authBusy,
                onSignOut: state._signOut,
              ),
      ),
    );
  }
}

class _SignedOutAuthContent extends StatelessWidget {
  const _SignedOutAuthContent({super.key, required this.state});

  final _PizzaReaderHomeState state;

  @override
  Widget build(BuildContext context) {
    final helper = state._codeSent
        ? 'Codice inviato. Inseriscilo qui.'
        : 'Magic code via email, nessuna password.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Non connesso',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: PizzaColors.muted),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: state._emailController,
          enabled: !state._authBusy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_rounded, size: 18),
            prefixIconConstraints: BoxConstraints(minWidth: 38),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: state._otpController,
          builder: (context, value, _) {
            final hasCode = value.text.trim().isNotEmpty;
            final shouldVerify = state._codeSent || hasCode;
            return Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: state._otpController,
                    enabled: !state._authBusy,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!state._authBusy &&
                          state._otpController.text.trim().isNotEmpty) {
                        state._verifyOtp();
                      }
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Code',
                      prefixIcon: Icon(Icons.pin_rounded, size: 18),
                      prefixIconConstraints: BoxConstraints(minWidth: 38),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: state._authBusy
                      ? null
                      : shouldVerify
                      ? state._verifyOtp
                      : state._sendMagicCode,
                  icon: state._authBusy
                      ? const _SmallBusyIndicator()
                      : Icon(
                          shouldVerify
                              ? Icons.verified_rounded
                              : Icons.send_rounded,
                          size: 18,
                        ),
                  label: Text(shouldVerify ? 'Verifica' : 'Invia'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 7),
        Text(
          helper,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: PizzaColors.muted),
        ),
      ],
    );
  }
}

class _RenameBookDialog extends StatefulWidget {
  const _RenameBookDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameBookDialog> createState() => _RenameBookDialogState();
}

class _RenameBookDialogState extends State<_RenameBookDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rinomina libro'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Titolo',
          prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          icon: const Icon(Icons.check_rounded),
          label: const Text('Rinomina'),
        ),
      ],
    );
  }
}

class _SignedInAuthContent extends StatelessWidget {
  const _SignedInAuthContent({
    super.key,
    required this.email,
    required this.busy,
    required this.onSignOut,
  });

  final String email;
  final bool busy;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.verified_user_rounded, color: PizzaColors.basil),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connesso',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: PizzaColors.basilDeep,
                    ),
                  ),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: PizzaColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: busy ? null : onSignOut,
          icon: busy
              ? const _SmallBusyIndicator()
              : const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Esci dall\'account'),
        ),
      ],
    );
  }
}

class _SmallBusyIndicator extends StatelessWidget {
  const _SmallBusyIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation(
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}

class _EnvironmentBadge extends StatelessWidget {
  const _EnvironmentBadge({required this.cloudEnabled});

  final bool cloudEnabled;

  @override
  Widget build(BuildContext context) {
    final color = cloudEnabled ? PizzaColors.basil : PizzaColors.blueCheese;
    final icon = cloudEnabled
        ? Icons.cloud_done_rounded
        : Icons.laptop_mac_rounded;
    final label = cloudEnabled ? 'Supabase' : 'Local/Fake';
    return Tooltip(
      message: cloudEnabled
          ? 'Archivio collegato a Supabase'
          : 'Archivio locale fake per sviluppo',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.36)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 5),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: color, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportPanel extends StatelessWidget {
  const _ImportPanel({
    required this.busy,
    required this.error,
    required this.cloudEnabled,
    required this.onPressed,
  });

  final bool busy;
  final String? error;
  final bool cloudEnabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final borderColor = error != null
        ? PizzaColors.tomatoDeep
        : busy
        ? PizzaColors.crust
        : PizzaColors.line;
    final helper =
        error ??
        (busy
            ? 'Conversione e salvataggio in corso.'
            : cloudEnabled
            ? 'Importa ebook e salva su Supabase.'
            : 'Importa ebook nel repository locale fake.');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: error == null
            ? PizzaColors.paper
            : PizzaColors.tomato.withValues(alpha: 0.05),
        border: Border.all(color: borderColor, width: busy ? 1.4 : 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: PizzaColors.blueCheese.withValues(alpha: 0.1),
                    border: Border.all(
                      color: PizzaColors.blueCheese.withValues(alpha: 0.22),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const SizedBox.square(
                    dimension: 44,
                    child: Icon(
                      Icons.upload_file_rounded,
                      color: PizzaColors.blueCheese,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Importa ebook',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 140),
                  child: busy
                      ? const _SmallBusyIndicator(key: ValueKey('busy-import'))
                      : Icon(
                          error == null
                              ? Icons.check_circle_outline_rounded
                              : Icons.error_outline_rounded,
                          key: ValueKey(
                            error == null ? 'idle-import' : 'error-import',
                          ),
                          color: error == null
                              ? PizzaColors.basil
                              : PizzaColors.tomatoDeep,
                          size: 22,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: Text(
                helper,
                key: ValueKey(helper),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: error == null
                      ? PizzaColors.muted
                      : PizzaColors.tomatoDeep,
                  fontWeight: error == null ? FontWeight.w400 : FontWeight.w700,
                ),
              ),
            ),
            if (busy) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: const LinearProgressIndicator(minHeight: 5),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onPressed,
                icon: busy
                    ? const _SmallBusyIndicator()
                    : const Icon(Icons.upload_file_rounded),
                label: Text(busy ? 'Import...' : 'Scegli file'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedPanel extends StatelessWidget {
  const _SpeedPanel({required this.state});

  final _PizzaReaderHomeState state;

  @override
  Widget build(BuildContext context) {
    final readout = state._speedReadoutValue();
    return _PanelShell(
      title: 'Velocita',
      trailing: _SpeedReadoutToggle(
        value: readout,
        onTap: state._toggleSpeedReadout,
        compact: false,
      ),
      child: Slider(
        value: state._wpm,
        min: 120,
        max: 900,
        divisions: 39,
        label: '${state._wpm.round()} WPM',
        onChanged: state._setWpm,
      ),
    );
  }
}

class _ModePanel extends StatelessWidget {
  const _ModePanel({required this.state});

  final _PizzaReaderHomeState state;

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      title: 'Modalita',
      child: SegmentedButton<reader.ReaderMode>(
        segments: const [
          ButtonSegment(
            value: reader.ReaderMode.hold,
            icon: Icon(Icons.touch_app_rounded),
            label: Text('Hold'),
          ),
          ButtonSegment(
            value: reader.ReaderMode.auto,
            icon: Icon(Icons.play_arrow_rounded),
            label: Text('Auto'),
          ),
          ButtonSegment(
            value: reader.ReaderMode.manual,
            icon: Icon(Icons.ads_click_rounded),
            label: Text('Manual'),
          ),
        ],
        selected: {state._mode},
        onSelectionChanged: (value) => state._setMode(value.first),
      ),
    );
  }
}

class _MobileWorkspaceSheet extends StatelessWidget {
  const _MobileWorkspaceSheet({required this.state});

  final _PizzaReaderHomeState state;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: state._workspaceRevision,
      builder: (context, _, _) {
        LibraryBook? activeStoredBook;
        for (final stored in state._libraryBooks) {
          if (stored.id == state._book.id) {
            activeStoredBook = stored;
            break;
          }
        }

        final bottomPadding =
            MediaQuery.paddingOf(context).bottom +
            MediaQuery.viewInsetsOf(context).bottom +
            18;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.45,
          maxChildSize: 0.96,
          builder: (context, scrollController) => Column(
            children: [
              Padding(
                key: const ValueKey('mobile-workspace-header'),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  children: [
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: PizzaColors.line,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const SizedBox(width: 42, height: 4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.account_circle_rounded,
                          color: PizzaColors.blueCheese,
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Account e libreria',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Chiudi',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
                  children: [
                    _AuthPanel(state: state),
                    const SizedBox(height: 18),
                    _ImportPanel(
                      busy: state._importBusy,
                      error: state._importError,
                      cloudEnabled: state.widget.cloudEnabled,
                      onPressed: () {
                        Navigator.of(context).pop();
                        state._importBook();
                      },
                    ),
                    const SizedBox(height: 22),
                    _MobileLibrarySection(
                      book: state._book,
                      storedBook: activeStoredBook,
                      libraryBooks: state._libraryBooks,
                      onOpenBook: (book) {
                        Navigator.of(context).pop();
                        state._openLibraryBook(book);
                      },
                      onRenameBook: state._renameLibraryBook,
                      onDeleteBook: state._confirmDeleteLibraryBook,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MobileLibrarySection extends StatelessWidget {
  const _MobileLibrarySection({
    required this.book,
    required this.storedBook,
    required this.libraryBooks,
    required this.onOpenBook,
    required this.onRenameBook,
    required this.onDeleteBook,
  });

  final PizzaBook book;
  final LibraryBook? storedBook;
  final List<LibraryBook> libraryBooks;
  final ValueChanged<LibraryBook> onOpenBook;
  final ValueChanged<LibraryBook> onRenameBook;
  final ValueChanged<LibraryBook> onDeleteBook;

  @override
  Widget build(BuildContext context) {
    final otherBooks = _otherLibraryBooks(libraryBooks, activeBook: book);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Libreria',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _CountBadge(count: libraryBooks.length),
          ],
        ),
        const SizedBox(height: 10),
        _ActiveBookCard(
          book: book,
          storedBook: storedBook,
          onRename: storedBook == null ? null : () => onRenameBook(storedBook!),
          onDelete: storedBook == null ? null : () => onDeleteBook(storedBook!),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: libraryBooks.isEmpty
              ? const _LibraryEmptyState(key: ValueKey('mobile-empty-library'))
              : otherBooks.isEmpty
              ? const _LibraryCurrentOnlyState(
                  key: ValueKey('mobile-current-only-library'),
                )
              : Column(
                  key: ValueKey('mobile-library-${otherBooks.length}'),
                  children: [
                    for (var i = 0; i < otherBooks.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                        child: _LibraryBookCard(
                          book: otherBooks[i],
                          active: false,
                          onOpen: () => onOpenBook(otherBooks[i]),
                          onRename: () => onRenameBook(otherBooks[i]),
                          onDelete: () => onDeleteBook(otherBooks[i]),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.titleGap = 12,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final double titleGap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PizzaColors.paper,
        border: Border.all(color: PizzaColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
            SizedBox(height: titleGap),
            child,
          ],
        ),
      ),
    );
  }
}

class _LibraryRail extends StatelessWidget {
  const _LibraryRail({
    required this.book,
    required this.libraryBooks,
    required this.onOpenBook,
    required this.onRenameBook,
    required this.onDeleteBook,
  });

  final PizzaBook book;
  final List<LibraryBook> libraryBooks;
  final ValueChanged<LibraryBook> onOpenBook;
  final ValueChanged<LibraryBook> onRenameBook;
  final ValueChanged<LibraryBook> onDeleteBook;

  @override
  Widget build(BuildContext context) {
    LibraryBook? activeStoredBook;
    for (final stored in libraryBooks) {
      if (stored.id == book.id) {
        activeStoredBook = stored;
        break;
      }
    }
    final otherBooks = _otherLibraryBooks(libraryBooks, activeBook: book);

    return ColoredBox(
      color: PizzaColors.paper.withValues(alpha: 0.82),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              const _PizzaFaviconMark(size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Pizza\nReader',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(height: 0.92),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('In lettura', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _ActiveBookCard(
            book: book,
            storedBook: activeStoredBook,
            onRename: activeStoredBook == null
                ? null
                : () => onRenameBook(activeStoredBook!),
            onDelete: activeStoredBook == null
                ? null
                : () => onDeleteBook(activeStoredBook!),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Libri importati',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _CountBadge(count: libraryBooks.length),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: libraryBooks.isEmpty
                ? const _LibraryEmptyState(key: ValueKey('empty-library'))
                : otherBooks.isEmpty
                ? const _LibraryCurrentOnlyState(
                    key: ValueKey('current-only-library'),
                  )
                : Column(
                    key: ValueKey('library-${otherBooks.length}'),
                    children: [
                      for (var i = 0; i < otherBooks.length; i++)
                        Padding(
                          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                          child: _LibraryBookCard(
                            book: otherBooks[i],
                            active: false,
                            onOpen: () => onOpenBook(otherBooks[i]),
                            onRename: () => onRenameBook(otherBooks[i]),
                            onDelete: () => onDeleteBook(otherBooks[i]),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ActiveBookCard extends StatelessWidget {
  const _ActiveBookCard({
    required this.book,
    required this.storedBook,
    required this.onRename,
    required this.onDelete,
  });

  final PizzaBook book;
  final LibraryBook? storedBook;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final stored = storedBook;
    final detail = stored == null
        ? '${book.chapters.length} capitoli - ${_pizzaBookFormat(book)}'
        : '${_formatByteLength(stored.byteLength)} - ${_libraryBookFormat(stored)}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PizzaColors.dough,
        border: Border.all(color: PizzaColors.crust, width: 1.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.play_circle_fill_rounded,
                  color: PizzaColors.tomato,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (stored != null && onRename != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    key: ValueKey('rename-book-${stored.id}'),
                    onPressed: onRename,
                    icon: const Icon(Icons.drive_file_rename_outline_rounded),
                    tooltip: 'Rinomina libro',
                  ),
                ],
                if (stored != null && onDelete != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    key: ValueKey('delete-book-${stored.id}'),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: 'Elimina libro',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                const _MetaPill(
                  icon: Icons.play_arrow_rounded,
                  label: 'Attivo',
                  color: PizzaColors.tomato,
                ),
                _MetaPill(
                  icon: Icons.insert_drive_file_rounded,
                  label: detail,
                  color: PizzaColors.blueCheese,
                ),
              ],
            ),
            if (book.author != null && book.author!.trim().isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                book.author!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: PizzaColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PizzaFaviconMark extends StatelessWidget {
  const _PizzaFaviconMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/brand/pizza-favicon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _LibraryBookCard extends StatelessWidget {
  const _LibraryBookCard({
    required this.book,
    required this.active,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final LibraryBook book;
  final bool active;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(8);
    return Material(
      color: active ? PizzaColors.dough : PizzaColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          color: active ? PizzaColors.crust : PizzaColors.line,
          width: active ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _LibraryBookCardBody(
            book: book,
            active: active,
            onRename: onRename,
            onDelete: onDelete,
          ),
        ),
      ),
    );
  }
}

class _LibraryBookCardBody extends StatelessWidget {
  const _LibraryBookCardBody({
    required this.book,
    required this.active,
    required this.onRename,
    required this.onDelete,
  });

  final LibraryBook book;
  final bool active;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              active ? Icons.play_circle_fill_rounded : Icons.menu_book_rounded,
              color: active ? PizzaColors.tomato : PizzaColors.basil,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              key: ValueKey('rename-book-${book.id}'),
              onPressed: onRename,
              icon: const Icon(Icons.drive_file_rename_outline_rounded),
              tooltip: 'Rinomina libro',
            ),
            const SizedBox(width: 2),
            IconButton(
              key: ValueKey('delete-book-${book.id}'),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Elimina libro',
            ),
          ],
        ),
        if (book.author != null && book.author!.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            book.author!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: PizzaColors.muted),
          ),
        ],
        const SizedBox(height: 9),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _MetaPill(
              icon: active
                  ? Icons.play_arrow_rounded
                  : Icons.check_circle_outline_rounded,
              label: active ? 'Attivo' : 'Importato',
              color: active ? PizzaColors.tomato : PizzaColors.basil,
            ),
            _MetaPill(
              icon: Icons.data_object_rounded,
              label: _formatByteLength(book.byteLength),
              color: PizzaColors.blueCheese,
            ),
            _MetaPill(
              icon: Icons.description_rounded,
              label: _libraryBookFormat(book),
              color: PizzaColors.crustDeep,
            ),
          ],
        ),
        if (book.sourceFileName != null &&
            book.sourceFileName!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            book.sourceFileName!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: PizzaColors.muted),
          ),
        ],
      ],
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PizzaColors.paperAlt.withValues(alpha: 0.62),
        border: Border.all(color: PizzaColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.library_books_rounded, color: PizzaColors.basil),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nessun libro importato',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Il testo locale resta attivo.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: PizzaColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryCurrentOnlyState extends StatelessWidget {
  const _LibraryCurrentOnlyState({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PizzaColors.paperAlt.withValues(alpha: 0.62),
        border: Border.all(color: PizzaColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: PizzaColors.basil,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nessun altro libro',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Il libro importato e gia in lettura.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: PizzaColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PizzaColors.paperAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PizzaColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          '$count',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: PizzaColors.muted),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        border: Border.all(color: color.withValues(alpha: 0.26)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: color, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.chapter,
    required this.durationLabel,
    required this.active,
    required this.onTap,
  });

  final PizzaChapter chapter;
  final String durationLabel;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? PizzaColors.tomato.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                active ? Icons.bookmark_rounded : Icons.menu_book_rounded,
                color: active ? PizzaColors.tomato : PizzaColors.basil,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  chapter.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                durationLabel,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: PizzaColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NormalTextOverlay extends StatelessWidget {
  const _NormalTextOverlay({
    required this.book,
    required this.activeChapterIndex,
    required this.durationLabelForChapter,
    required this.wordMap,
    required this.activeWordIndex,
    required this.onClose,
    required this.onChapterSelected,
    required this.onJump,
  });

  final PizzaBook book;
  final int activeChapterIndex;
  final String Function(int index) durationLabelForChapter;
  final WordMap wordMap;
  final int activeWordIndex;
  final VoidCallback onClose;
  final ValueChanged<int> onChapterSelected;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final chapter = book.chapters[activeChapterIndex];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final chapterSelector = _BookChapterSelector(
          book: book,
          activeChapterIndex: activeChapterIndex,
          durationLabelForChapter: durationLabelForChapter,
          onChapterSelected: onChapterSelected,
        );
        Widget body = chapterSelector;
        if (_bookTextLineSelectorEnabled) {
          final lines = _textLines(chapter.text, wordMap);
          final textList = _BookTextLineList(
            lines: lines,
            activeWordIndex: activeWordIndex,
            onJump: onJump,
          );
          body = wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 286, child: chapterSelector),
                    const VerticalDivider(width: 28),
                    Expanded(child: textList),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 142, child: chapterSelector),
                    const SizedBox(height: 14),
                    Expanded(child: textList),
                  ],
                );
        }

        return ColoredBox(
          color: PizzaColors.paper.withValues(alpha: 0.96),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(wide ? 22 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              chapter.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: PizzaColors.muted),
                            ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: 'Chiudi libro',
                        child: IconButton(
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<_TextLine> _textLines(String text, WordMap wordMap) {
    final matches = RegExp(r'[^.!?\n]+[.!?]?|\n+').allMatches(text);
    final lines = <_TextLine>[];
    for (final match in matches) {
      final raw = match.group(0)?.trim();
      if (raw == null || raw.isEmpty) {
        continue;
      }
      final first = wordMap.wordIndexForTextOffset(match.start) ?? 0;
      final last = wordMap.wordIndexForTextOffset(match.end - 1) ?? first;
      lines.add(
        _TextLine(
          text: raw,
          startOffset: match.start,
          firstWordIndex: first,
          lastWordIndex: last,
        ),
      );
    }
    if (lines.isEmpty) {
      lines.add(
        _TextLine(
          text: text,
          startOffset: 0,
          firstWordIndex: 0,
          lastWordIndex: math.max(0, wordMap.words.length - 1),
        ),
      );
    }
    return lines;
  }
}

// Parked for the next pass on sentence/line selection inside the book panel.
bool get _bookTextLineSelectorEnabled => false;

class _BookChapterSelector extends StatelessWidget {
  const _BookChapterSelector({
    required this.book,
    required this.activeChapterIndex,
    required this.durationLabelForChapter,
    required this.onChapterSelected,
  });

  final PizzaBook book;
  final int activeChapterIndex;
  final String Function(int index) durationLabelForChapter;
  final ValueChanged<int> onChapterSelected;

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      itemCount: book.chapters.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _ChapterTile(
          chapter: book.chapters[index],
          durationLabel: durationLabelForChapter(index),
          active: index == activeChapterIndex,
          onTap: () => onChapterSelected(index),
        );
      },
    );

    return Column(
      key: const ValueKey('book-chapter-selector'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Capitoli', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Expanded(child: list),
      ],
    );
  }
}

class _BookTextLineList extends StatelessWidget {
  const _BookTextLineList({
    required this.lines,
    required this.activeWordIndex,
    required this.onJump,
  });

  final List<_TextLine> lines;
  final int activeWordIndex;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('book-text-lines'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Testo', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: lines.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final line = lines[index];
              return _TextJumpLine(
                line: line,
                active:
                    activeWordIndex >= line.firstWordIndex &&
                    activeWordIndex <= line.lastWordIndex,
                onTap: () => onJump(line.startOffset),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TextJumpLine extends StatelessWidget {
  const _TextJumpLine({
    required this.line,
    required this.active,
    required this.onTap,
  });

  final _TextLine line;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? PizzaColors.crust.withValues(alpha: 0.16)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            line.text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.book,
    required this.importBusy,
    required this.importError,
    required this.onOpenWorkspace,
  });

  final PizzaBook book;
  final bool importBusy;
  final String? importError;
  final VoidCallback onOpenWorkspace;

  @override
  Widget build(BuildContext context) {
    final status = importBusy
        ? 'Import in corso'
        : importError == null
        ? null
        : 'Import fallito';
    return ColoredBox(
      color: PizzaColors.paper.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            const _PizzaFaviconMark(size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: importBusy
                            ? PizzaColors.muted
                            : PizzaColors.tomatoDeep,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onOpenWorkspace,
              icon: const Icon(Icons.account_circle_rounded),
              tooltip: 'Account e libreria',
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileControls extends StatelessWidget {
  const _MobileControls({required this.state});

  final _PizzaReaderHomeState state;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PizzaColors.paper,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _CompactModeSelector(state: state)),
                  const SizedBox(width: 10),
                  _SpeedReadoutToggle(
                    value: state._speedReadoutValue(),
                    onTap: state._toggleSpeedReadout,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SliderTheme(
                data: Theme.of(context).sliderTheme.copyWith(trackHeight: 5),
                child: Slider(
                  value: state._wpm,
                  min: 120,
                  max: 900,
                  divisions: 39,
                  label: '${state._wpm.round()} WPM',
                  onChanged: state._setWpm,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactModeSelector extends StatelessWidget {
  const _CompactModeSelector({required this.state});

  final _PizzaReaderHomeState state;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<reader.ReaderMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: reader.ReaderMode.hold,
          icon: Icon(Icons.touch_app_rounded),
          tooltip: 'Hold',
        ),
        ButtonSegment(
          value: reader.ReaderMode.auto,
          icon: Icon(Icons.play_arrow_rounded),
          tooltip: 'Auto',
        ),
        ButtonSegment(
          value: reader.ReaderMode.manual,
          icon: Icon(Icons.ads_click_rounded),
          tooltip: 'Manual',
        ),
      ],
      selected: {state._mode},
      onSelectionChanged: (value) => state._setMode(value.first),
    );
  }
}

class _SpeedReadoutValue {
  const _SpeedReadoutValue({
    required this.primary,
    required this.secondary,
    required this.inline,
    required this.tooltip,
  });

  final String primary;
  final String secondary;
  final String inline;
  final String tooltip;
}

class _SpeedReadoutToggle extends StatelessWidget {
  const _SpeedReadoutToggle({
    required this.value,
    required this.onTap,
    required this.compact,
  });

  final _SpeedReadoutValue value;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(8);
    return Tooltip(
      message: value.tooltip,
      child: Semantics(
        button: true,
        label: value.inline,
        child: Material(
          color: PizzaColors.dough,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: const BorderSide(color: PizzaColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('speed-readout-toggle'),
            onTap: onTap,
            child: SizedBox(
              width: compact ? 92 : 104,
              height: compact ? 42 : 34,
              child: compact
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            value.primary,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: PizzaColors.tomatoDeep,
                                  height: 1,
                                ),
                          ),
                        ),
                        Text(
                          value.secondary,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: PizzaColors.muted,
                                fontSize: 11,
                                height: 1,
                              ),
                        ),
                      ],
                    )
                  : Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          value.inline,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: PizzaColors.tomatoDeep),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderBackgroundPainter extends CustomPainter {
  const _ReaderBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = PizzaColors.dough;
    canvas.drawRect(Offset.zero & size, base);

    final guide = Paint()
      ..color = PizzaColors.crust.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final accent = Paint()
      ..color = PizzaColors.tomato.withValues(alpha: 0.035)
      ..style = PaintingStyle.fill;

    final bandHeight = math.max(76.0, size.height * 0.11);
    for (var y = bandHeight; y < size.height; y += bandHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.58, 0, size.width * 0.42, size.height),
        const Radius.circular(0),
      ),
      accent,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WordContourPainter extends CustomPainter {
  const _WordContourPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centerY = size.height / 2;
    final line = Paint()
      ..color = PizzaColors.line
      ..strokeWidth = 2;
    final accent = Paint()
      ..color = PizzaColors.tomato
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(8), const Radius.circular(8)),
      Paint()
        ..color = PizzaColors.paper.withValues(alpha: 0.78)
        ..style = PaintingStyle.fill,
    );
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), line);
    canvas.drawLine(
      Offset(size.width / 2, 18),
      Offset(size.width / 2, size.height - 18),
      line,
    );
    canvas.drawLine(
      Offset(20, size.height - 16),
      Offset(20 + (size.width - 40) * progress.clamp(0, 1), size.height - 16),
      accent,
    );
  }

  @override
  bool shouldRepaint(covariant _WordContourPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

String _formatByteLength(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kib = bytes / 1024;
  if (kib < 1024) {
    return '${_compactDecimal(kib)} KB';
  }
  return '${_compactDecimal(kib / 1024)} MB';
}

String _compactDecimal(double value) {
  final fixed = value >= 10
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

String _formatReadingDuration(Duration duration) {
  final seconds = math.max(1, (duration.inMilliseconds / 1000).round());
  if (seconds < 60) {
    return '${seconds}s';
  }

  final minutes = math.max(1, (seconds / 60).round());
  if (minutes < 60) {
    return '${minutes}m';
  }

  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (remainingMinutes == 0) {
    return '${hours}h';
  }
  return '${hours}h ${remainingMinutes}m';
}

List<LibraryBook> _otherLibraryBooks(
  List<LibraryBook> books, {
  required PizzaBook activeBook,
}) {
  return books
      .where((book) => book.id != activeBook.id)
      .toList(growable: false);
}

String _libraryBookFormat(LibraryBook book) {
  final source = _fileExtension(book.sourceFileName);
  return source ?? 'EBOOK';
}

String _pizzaBookFormat(PizzaBook book) {
  final sourceFile = book.metadata['source_file'];
  if (sourceFile is String) {
    return _fileExtension(sourceFile) ?? 'EBOOK';
  }
  return 'EBOOK';
}

String? _fileExtension(String? path) {
  if (path == null) {
    return null;
  }
  final name = path.trim().split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) {
    return null;
  }
  return name.substring(dot + 1).toUpperCase();
}

class _TextLine {
  const _TextLine({
    required this.text,
    required this.startOffset,
    required this.firstWordIndex,
    required this.lastWordIndex,
  });

  final String text;
  final int startOffset;
  final int firstWordIndex;
  final int lastWordIndex;
}

PizzaBook _starterBook() {
  return PizzaBook(
    id: 'starter-pizza-book',
    title: 'Testo locale',
    author: 'Pizza Reader',
    language: 'it',
    metadata: const <String, Object?>{
      'source_kind': 'local',
      'source_file': 'testo-locale.epub',
    },
    chapters: const [
      PizzaChapter(
        id: 'chapter-1',
        title: 'Impasto',
        text:
            'Ogni libro entra nel forno del browser. Il testo viene pulito, '
            'ordinato in capitoli e preparato per una lettura rapida '
            'coerente su ogni sorgente.',
      ),
      PizzaChapter(
        id: 'chapter-2',
        title: 'Cottura',
        text:
            'La lettura mostra una parola alla volta, con il centro ottico '
            'in evidenza. La velocita media resta vicina al WPM scelto, '
            'ma punteggiatura e parole lunghe ricevono piu respiro. '
            'Precipitevolissimevolmente, internazionalizzazione ed '
            'elettroencefalograficamente servono a testare il layout.',
      ),
      PizzaChapter(
        id: 'chapter-3',
        title: 'Taglio',
        text:
            'Quando serve orientarsi, il testo torna normale. Un tap su una '
            'riga riporta subito il reader alla posizione corretta.',
      ),
    ],
  );
}
