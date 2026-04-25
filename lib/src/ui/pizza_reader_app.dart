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

  Timer? _timer;
  late PizzaBook _book;
  late reader.ReaderController _reader;
  var _mode = reader.ReaderMode.auto;
  var _wpm = 360.0;
  var _isPlaying = false;
  var _textMapOpen = false;
  var _importBusy = false;
  var _authBusy = false;
  var _codeSent = false;
  var _status = 'Importa un ebook o prova il demo locale';
  var _libraryBooks = <LibraryBook>[];

  @override
  void initState() {
    super.initState();
    _book = _demoBook();
    _reader = _newReaderFor(_book, initialMode: _mode);
    _loadLibrary();
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    setState(() {
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
      setState(() => _libraryBooks = books);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _libraryBooks = const []);
    }
  }

  Future<void> _importBook() async {
    if (_importBusy) {
      return;
    }
    setState(() {
      _importBusy = true;
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
          'pb',
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
        });
        return;
      }

      final book = _importer.importBytes(bytes, fileName: file.name);
      final pbBytes = _codec.encode(book);
      await widget.libraryRepository.uploadBook(
        bytes: pbBytes,
        title: book.title,
        author: book.author,
        sourceFileName: file.name,
        bookId: book.id,
      );

      _replaceBook(book);
      await _loadLibrary();
      setState(() {
        _status = 'Convertito e caricato ${file.name} come .pb';
        _importBusy = false;
      });
    } on UnsupportedError catch (error) {
      setState(() {
        _status = error.message ?? 'Formato non supportato';
        _importBusy = false;
      });
    } on Object catch (error) {
      setState(() {
        _status = 'Import fallito: $error';
        _importBusy = false;
      });
    }
  }

  Future<void> _sendMagicCode() async {
    if (_authBusy) {
      return;
    }
    setState(() => _authBusy = true);
    try {
      await widget.authRepository.sendMagicCode(_emailController.text);
      setState(() {
        _codeSent = true;
        _status = 'Codice inviato a ${normalizeEmail(_emailController.text)}';
      });
    } on Object catch (error) {
      setState(() => _status = 'Login: $error');
    } finally {
      if (mounted) {
        setState(() => _authBusy = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (_authBusy) {
      return;
    }
    setState(() => _authBusy = true);
    try {
      await widget.authRepository.verifyEmailOtp(
        _emailController.text,
        _otpController.text,
      );
      await _loadLibrary();
      setState(() {
        _codeSent = false;
        _otpController.clear();
        _status = 'Login completato';
      });
    } on Object catch (error) {
      setState(() => _status = 'Codice non valido: $error');
    } finally {
      if (mounted) {
        setState(() => _authBusy = false);
      }
    }
  }

  Future<void> _signOut() async {
    await widget.authRepository.signOut();
    await _loadLibrary();
    setState(() => _status = 'Logout completato');
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

  void _selectChapter(int index) {
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

  int _wordCountForChapter(int chapterIndex) {
    return _wordMapForChapter(chapterIndex).words.length;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      body: CustomPaint(
        painter: const _PizzaBackgroundPainter(),
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
            activeChapterIndex: _reader.position.chapterIndex,
            wordCountForChapter: _wordCountForChapter,
            onChapterSelected: _selectChapter,
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
        _MobileHeader(book: _book, onImport: _importBook),
        const Divider(height: 1),
        Expanded(child: _ReaderStage(state: this, compact: true)),
        const Divider(height: 1),
        _MobileControls(state: this),
      ],
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
              chapter: chapter,
              wordMap: wordMap,
              activeWordIndex: state._reader.position.wordIndex,
              onClose: state._closeTextMap,
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
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '$progress - $status',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: PizzaColors.muted),
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Apri testo normale',
          child: IconButton.filledTonal(
            onPressed: onOpenText,
            icon: const Icon(Icons.subject_rounded),
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
            if (constraints.maxHeight >= 132) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: math.min(520, constraints.maxWidth * 0.82),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: PizzaColors.line,
                    valueColor: const AlwaysStoppedAnimation(PizzaColors.basil),
                  ),
                ),
              ),
            ],
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
            cloudEnabled: state.widget.cloudEnabled,
            onPressed: state._importBook,
          ),
          const SizedBox(height: 20),
          _SpeedPanel(state: state),
          const SizedBox(height: 20),
          _ModePanel(state: state),
          const SizedBox(height: 20),
          _ChapterPanel(
            book: state._book,
            activeChapterIndex: state._reader.position.chapterIndex,
            wordCountForChapter: state._wordCountForChapter,
            onChapterSelected: state._selectChapter,
          ),
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
      title: user == null ? 'Accesso' : 'Account',
      trailing: Icon(
        state.widget.cloudEnabled
            ? Icons.cloud_done_rounded
            : Icons.laptop_mac_rounded,
        color: state.widget.cloudEnabled
            ? PizzaColors.basil
            : PizzaColors.blueCheese,
      ),
      child: user == null
          ? Column(
              children: [
                TextField(
                  controller: state._emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_rounded),
                  ),
                ),
                if (state._codeSent) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: state._otpController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Magic code',
                      prefixIcon: Icon(Icons.pin_rounded),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: state._authBusy
                        ? null
                        : state._codeSent
                        ? state._verifyOtp
                        : state._sendMagicCode,
                    icon: Icon(
                      state._codeSent
                          ? Icons.verified_rounded
                          : Icons.send_rounded,
                    ),
                    label: Text(state._codeSent ? 'Verifica' : 'Invia codice'),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    user.email ?? user.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Tooltip(
                  message: 'Logout',
                  child: IconButton(
                    onPressed: state._signOut,
                    icon: const Icon(Icons.logout_rounded),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ImportPanel extends StatelessWidget {
  const _ImportPanel({
    required this.busy,
    required this.cloudEnabled,
    required this.onPressed,
  });

  final bool busy;
  final bool cloudEnabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PizzaColors.paper,
        border: Border.all(color: PizzaColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/brand/pizzalogo.png',
                  width: 44,
                  height: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Importa ebook',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              cloudEnabled
                  ? 'Conversione nel browser, poi upload privato su Supabase.'
                  : 'Conversione nel browser con repository locale fake per sviluppo.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: PizzaColors.muted),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onPressed,
                icon: Icon(
                  busy
                      ? Icons.hourglass_top_rounded
                      : Icons.upload_file_rounded,
                ),
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
    return _PanelShell(
      title: 'Velocita',
      trailing: Text(
        '${state._wpm.round()} WPM',
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: PizzaColors.tomatoDeep),
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

class _ChapterPanel extends StatelessWidget {
  const _ChapterPanel({
    required this.book,
    required this.activeChapterIndex,
    required this.wordCountForChapter,
    required this.onChapterSelected,
  });

  final PizzaBook book;
  final int activeChapterIndex;
  final int Function(int index) wordCountForChapter;
  final ValueChanged<int> onChapterSelected;

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      title: 'Capitoli',
      child: Column(
        children: [
          for (var i = 0; i < book.chapters.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: _ChapterTile(
                chapter: book.chapters[i],
                wordCount: wordCountForChapter(i),
                active: i == activeChapterIndex,
                onTap: () => onChapterSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PizzaColors.paper,
        border: Border.all(color: PizzaColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 12),
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
    required this.activeChapterIndex,
    required this.wordCountForChapter,
    required this.onChapterSelected,
  });

  final PizzaBook book;
  final List<LibraryBook> libraryBooks;
  final int activeChapterIndex;
  final int Function(int index) wordCountForChapter;
  final ValueChanged<int> onChapterSelected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PizzaColors.paper.withValues(alpha: 0.82),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Image.asset('assets/brand/pizzalogo.png', width: 52, height: 52),
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
          const SizedBox(height: 28),
          Text('Libreria', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _BookTile(
            title: book.title,
            subtitle: '${book.chapters.length} capitoli - attivo',
            active: true,
          ),
          for (final stored in libraryBooks)
            if (stored.id != book.id)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _BookTile(
                  title: stored.title,
                  subtitle: '${stored.byteLength} byte .pb',
                  active: false,
                ),
              ),
          const SizedBox(height: 28),
          Text('Indice', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          for (var i = 0; i < book.chapters.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: _ChapterTile(
                chapter: book.chapters[i],
                wordCount: wordCountForChapter(i),
                active: i == activeChapterIndex,
                onTap: () => onChapterSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.title,
    required this.subtitle,
    required this.active,
  });

  final String title;
  final String subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? PizzaColors.dough : PizzaColors.paper,
        border: Border.all(
          color: active ? PizzaColors.crust : PizzaColors.line,
          width: active ? 1.4 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: PizzaColors.muted),
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
    required this.wordCount,
    required this.active,
    required this.onTap,
  });

  final PizzaChapter chapter;
  final int wordCount;
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
                active ? Icons.local_pizza_rounded : Icons.menu_book_rounded,
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
                '$wordCount',
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
    required this.chapter,
    required this.wordMap,
    required this.activeWordIndex,
    required this.onClose,
    required this.onJump,
  });

  final PizzaChapter chapter;
  final WordMap wordMap;
  final int activeWordIndex;
  final VoidCallback onClose;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final lines = _textLines(chapter.text, wordMap);
    return ColoredBox(
      color: PizzaColors.paper.withValues(alpha: 0.96),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chapter.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Tooltip(
                    message: 'Chiudi testo',
                    child: IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
          ),
        ),
      ),
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
  const _MobileHeader({required this.book, required this.onImport});

  final PizzaBook book;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PizzaColors.paper.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Image.asset('assets/brand/pizzalogo.png', width: 40, height: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: onImport,
              icon: const Icon(Icons.upload_file_rounded),
              tooltip: 'Importa ebook',
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModePanel(state: state),
            const SizedBox(height: 10),
            _SpeedPanel(state: state),
          ],
        ),
      ),
    );
  }
}

class _PizzaBackgroundPainter extends CustomPainter {
  const _PizzaBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = PizzaColors.dough;
    canvas.drawRect(Offset.zero & size, base);

    final sauce = Paint()
      ..color = PizzaColors.tomato.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18;
    final crust = Paint()
      ..color = PizzaColors.crust.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final center = Offset(size.width * 0.58, size.height * 0.48);
    final radius = math.max(size.width, size.height) * 0.42;
    canvas.drawCircle(center, radius, sauce);
    for (var i = 0; i < 10; i++) {
      final angle = i * math.pi / 5;
      final end = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawLine(center, end, crust);
    }
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

PizzaBook _demoBook() {
  return PizzaBook(
    id: 'demo-pizza-book',
    title: 'Demo Pizza Book',
    author: 'Pizza Reader',
    language: 'it',
    metadata: const <String, Object?>{
      'source_kind': 'demo',
      'source_file': 'demo.pb',
    },
    chapters: const [
      PizzaChapter(
        id: 'chapter-1',
        title: 'Impasto',
        text:
            'Ogni libro entra nel forno del browser. Il testo viene pulito, '
            'ordinato in capitoli e trasformato in un formato Pizza Book '
            'uguale per ogni sorgente.',
      ),
      PizzaChapter(
        id: 'chapter-2',
        title: 'Cottura',
        text:
            'La lettura mostra una parola alla volta, con il centro ottico '
            'in evidenza. La velocita media resta vicina al WPM scelto, '
            'ma punteggiatura e parole lunghe ricevono piu respiro.',
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
