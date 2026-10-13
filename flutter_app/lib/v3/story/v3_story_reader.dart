import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../services/session_settings.dart';
import '../../widgets/adaptive/adaptive.dart' show PSHaptics;
import '../ui/v3_ui.dart';
import 'v3_story.dart';
import 'v3_story_audio.dart';
import 'v3_story_store.dart';

/// V3 story reader. Screen contract:
///
/// User arrived to: read one story from the Stories list.
/// They must understand: what each sentence means, how each word is said, and
/// how far they are.
/// Primary action: play the story (or tap a line / word).
/// Secondary: translation on and off, text size, speed, quiz, key words.
/// Success state: the quiz is finished and the story is recorded as read.
/// Must not contain: an image header, a second font, a large modal over the
/// text, anything centered.
///
/// A tapped word shows a small card just above it (never a sheet) and, when
/// "Hear words when tapped" is on, Marie says the word. Narration is live
/// Marie, as in the legacy reader.
class V3StoryReader extends ConsumerStatefulWidget {
  const V3StoryReader({super.key, required this.story, this.startAt = 0});

  final V3Story story;
  final int startAt;

  @override
  ConsumerState<V3StoryReader> createState() => _V3StoryReaderState();
}

class _V3StoryReaderState extends ConsumerState<V3StoryReader>
    with WidgetsBindingObserver {
  final _settings = SessionSettings.shared;
  late final V3StoryAudio _audio;

  var _tab = 0;
  int? _selected;
  late int _current = widget.startAt.clamp(
    0,
    widget.story.sentences.length - 1,
  );
  var _playing = false;
  var _loading = false;
  int? _rawWord;

  final _sentenceKeys = <int, GlobalKey>{};
  final _wordKeys = <String, GlobalKey>{};
  OverlayEntry? _popover;
  ({int sentence, int unit})? _popWord;

  var _qIndex = 0;
  int? _qSelected;
  var _qChecked = false;
  var _qCorrect = 0;
  var _qFinished = false;

  Set<String> _saved = const {};

  V3Story get _story => widget.story;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final events = V3StoryAudioEvents(
      onSentence: (i) {
        if (!mounted) return;
        setState(() {
          _current = i;
          _rawWord = null;
          _playing = true;
        });
        _scrollToCurrent();
      },
      onWord: (i, w) {
        if (mounted) setState(() => _rawWord = w);
      },
      onLoading: (l) {
        if (mounted) setState(() => _loading = l);
      },
      onFinished: () {
        if (mounted) {
          setState(() {
            _playing = false;
            _loading = false;
            _rawWord = null;
          });
        }
      },
      onError: (message) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      },
    );
    _audio = V3StoryAudio.useFake
        ? V3FakeStoryAudio(story: _story, events: events)
        : V3LiveStoryAudio(
            story: _story,
            events: events,
            learningStore: ref.read(learningStoreProvider),
            contextProvider: _marieContext,
            buildContext: () => mounted ? context : null,
          );
    unawaited(
      Future.wait([_settings.load(), V3StoryProgress.loadPrefs()]).then((_) {
        if (mounted) {
          setState(() {});
          _audio.setRate(_settings.playbackRate);
        }
      }),
    );
    unawaited(
      V3StoryProgress.savedWords().then((s) {
        if (mounted) setState(() => _saved = s);
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _audio.handleLifecycle(state);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dismissPopover();
    if (!_qFinished && _current > 0) {
      unawaited(V3StoryProgress.savePosition(_story.id, _current));
    }
    _audio.dispose();
    super.dispose();
  }

  String _marieContext() {
    final b = StringBuffer()
      ..writeln(
        'STORY: ${_story.title} (${_story.titleEn}), level ${_story.level}.',
      )
      ..writeln(
        'STORY SENTENCE PAIRS (use for explanations, never read automatically):',
      );
    for (var i = 0; i < _story.sentences.length; i++) {
      final s = _story.sentences[i];
      b.writeln('[$i] FR: ${s.fr} | EN: ${s.en}');
      if (s.note.isNotEmpty) b.writeln('[$i] NOTE: ${s.note}');
    }
    for (final k in _story.keywords) {
      b.writeln('KEYWORD: $k = ${_story.words[k]!.en}');
    }
    return b.toString();
  }

  // ---- Playback --------------------------------------------------------

  Future<void> _togglePlay() async {
    _dismissPopover();
    if (_playing || _loading) {
      await _audio.stop();
    } else {
      setState(() => _playing = true);
      await _audio.playSentences(_selected ?? _current);
    }
  }

  Future<void> _replaySentence() async {
    _dismissPopover();
    if (_loading) return;
    final i = _selected ?? _current;
    setState(() => _playing = true);
    await _audio.playSentences(i, only: true);
  }

  Future<void> _cycleRate() async {
    final rates = SessionSettings.playbackRates;
    final at = rates.indexWhere(
      (r) => (r - _settings.playbackRate).abs() < 0.001,
    );
    final next = rates[(at < 0 ? 0 : at + 1) % rates.length];
    await _settings.setPlaybackRate(next);
    _audio.setRate(next);
    if (mounted) setState(() {});
  }

  void _scrollToCurrent() {
    final ctx = _sentenceKeys[_current]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: 0.3,
    );
  }

  void _selectSentence(int i) {
    _dismissPopover();
    setState(() {
      _selected = _selected == i ? null : i;
      if (_selected != null) _current = i;
    });
  }

  // ---- Word popover ----------------------------------------------------

  void _onWordTap(int s, int u) {
    final unit = _story.sentences[s].units[u];
    final word = _story.words[unit.key]!;
    final box = _wordKeys['$s.$u']?.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (_popWord == (sentence: s, unit: u)) {
      _dismissPopover();
      return;
    }
    _dismissPopover();
    PSHaptics.selection();
    setState(() {
      _popWord = (sentence: s, unit: u);
      _selected = s;
    });
    _popover = OverlayEntry(
      builder: (_) => _WordPopover(
        anchor: rect,
        word: unit.key,
        meaning: word,
        onDismiss: _dismissPopover,
        onHear: () => unawaited(_audio.speakWord(unit.key)),
      ),
    );
    Overlay.of(context).insert(_popover!);
    if (V3StoryProgress.hearWords.value && !_playing && !_loading) {
      unawaited(_audio.speakWord(unit.key));
    }
  }

  void _dismissPopover() {
    _popover?.remove();
    _popover = null;
    if (_popWord != null) {
      _popWord = null;
      if (mounted) setState(() {});
    }
  }

  // ---- Settings --------------------------------------------------------

  Future<void> _openSettings() async {
    _dismissPopover();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SettingsSheet(
        settings: _settings,
        onRate: (r) {
          _audio.setRate(r);
          if (mounted) setState(() {});
        },
      ),
    );
    if (mounted) setState(() {});
  }

  void _cycleTextSize() {
    final next = _settings.textScale < 0.98
        ? 1.0
        : _settings.textScale < 1.1
        ? 1.2
        : 0.9;
    unawaited(_settings.setTextScale(next));
    setState(() {});
  }

  Future<void> _toggleTranslation() async {
    await _settings.setTranslateSentences(!_settings.translateSentences);
    if (mounted) setState(() {});
  }

  // ---- Build -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: V3Width(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _topBar(),
                  Expanded(
                    child: NotificationListener<ScrollStartNotification>(
                      onNotification: (_) {
                        _dismissPopover();
                        return false;
                      },
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          4,
                          24,
                          _tab == 0 ? 190 : 40,
                        ),
                        children: [
                          _header(),
                          _tabs(),
                          const SizedBox(height: 10),
                          ...switch (_tab) {
                            0 => _storyTab(),
                            1 => _quizTab(),
                            _ => _wordsTab(),
                          },
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_tab == 0) _dock(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconButton(
    Key key,
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool on = false,
  }) {
    return V3Pressable(
      key: key,
      label: label,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: on ? DesignTokens.primarySoft : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 22,
          color: on ? DesignTokens.primary : DesignTokens.ink,
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          _iconButton(
            const ValueKey('story.back'),
            'Back',
            CupertinoIcons.chevron_back,
            () => Navigator.of(context).maybePop(false),
          ),
          const Spacer(),
          _iconButton(
            const ValueKey('story.translate'),
            _settings.translateSentences ? 'Translation on' : 'Translation off',
            CupertinoIcons.textformat_abc,
            _toggleTranslation,
            on: _settings.translateSentences,
          ),
          _iconButton(
            const ValueKey('story.textSize'),
            'Text size',
            CupertinoIcons.textformat_size,
            _cycleTextSize,
          ),
          _iconButton(
            const ValueKey('story.settings'),
            'Story settings',
            CupertinoIcons.gear,
            _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(_story.title, style: V3Type.title(34)),
        const SizedBox(height: 6),
        Text(_story.titleEn, style: V3Type.body(15)),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: DesignTokens.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _story.level,
                style: V3Type.strong(12.5, DesignTokens.primary),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${_story.minutes} min  ·  ${_story.sentences.length} sentences',
              style: V3Type.body(13),
            ),
          ],
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _tabs() {
    const names = ['Story', 'Quiz', 'Words'];
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: DesignTokens.hairline)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < names.length; i++) ...[
            V3Pressable(
              key: ValueKey('story.tab.${names[i].toLowerCase()}'),
              label: names[i],
              onTap: () {
                _dismissPopover();
                if (i != 0 && (_playing || _loading)) unawaited(_audio.stop());
                setState(() => _tab = i);
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.bottomLeft,
                padding: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _tab == i ? DesignTokens.ink : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text(
                  names[i],
                  style: V3Type.strong(
                    16,
                    _tab == i ? DesignTokens.ink : DesignTokens.inkSoft,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 26),
          ],
        ],
      ),
    );
  }

  // ---- Story tab -------------------------------------------------------

  List<Widget> _storyTab() {
    return [for (var i = 0; i < _story.sentences.length; i++) _sentence(i)];
  }

  Widget _sentence(int i) {
    final s = _story.sentences[i];
    final scale = _settings.textScale;
    final active = (_playing || _loading) ? _current == i : _selected == i;
    final playingUnit =
        (_playing &&
            _current == i &&
            _rawWord != null &&
            _settings.highlightWords &&
            s.rawToUnit.isNotEmpty)
        ? s.rawToUnit[math.min(_rawWord!, s.rawToUnit.length - 1)]
        : null;
    return GestureDetector(
      key: _sentenceKeys.putIfAbsent(i, GlobalKey.new),
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectSentence(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        decoration: BoxDecoration(
          color: active ? DesignTokens.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            if (active)
              Positioned(
                left: -16,
                top: 2,
                bottom: 2,
                child: Container(
                  width: 3.5,
                  decoration: BoxDecoration(
                    color: DesignTokens.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  children: [
                    for (var u = 0; u < s.units.length; u++)
                      _word(i, u, s.units[u], scale, playingUnit == u),
                  ],
                ),
                if (_settings.translateSentences) ...[
                  const SizedBox(height: 6),
                  Text(s.en, style: V3Type.body(14.5 * scale)),
                  if (s.note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      s.note,
                      style: V3Type.body(13 * scale, DesignTokens.primary),
                    ),
                  ],
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _word(int s, int u, V3Unit unit, double scale, bool speaking) {
    final tapped = _popWord == (sentence: s, unit: u);
    final base = V3Type.reading(22 * scale);
    final style = (speaking || tapped)
        ? base.copyWith(
            color: DesignTokens.primary,
            backgroundColor: DesignTokens.primary.withValues(
              alpha: speaking ? 0.14 : 0.08,
            ),
            decoration: tapped ? TextDecoration.underline : TextDecoration.none,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: DesignTokens.primary,
            decorationThickness: 2,
          )
        : base;
    return Semantics(
      container: true,
      button: true,
      label: 'Word ${unit.key}',
      excludeSemantics: true,
      onTap: () => _onWordTap(s, u),
      child: GestureDetector(
        key: _wordKeys.putIfAbsent('$s.$u', GlobalKey.new),
        behavior: HitTestBehavior.opaque,
        onTap: () => _onWordTap(s, u),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text('${unit.text} ', style: style),
        ),
      ),
    );
  }

  Widget _dock() {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final total = _story.sentences.length;
    final busy = _playing || _loading;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              DesignTokens.canvas.withValues(alpha: 0),
              DesignTokens.canvas,
              DesignTokens.canvas,
            ],
            stops: const [0, 0.3, 1],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 38, 24, 14 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('${_current + 1} of $total', style: V3Type.body(12.5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (_current + 1) / total,
                        minHeight: 4,
                        backgroundColor: DesignTokens.hairline,
                        color: DesignTokens.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${_story.minutes} min', style: V3Type.body(12.5)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DesignTokens.surface,
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: DesignTokens.hairline),
                  boxShadow: DesignTokens.surfaceShadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dockButton(
                      const ValueKey('story.dock.replay'),
                      'Replay sentence',
                      CupertinoIcons.arrow_counterclockwise,
                      _replaySentence,
                    ),
                    const SizedBox(width: 6),
                    V3Pressable(
                      key: const ValueKey('story.dock.play'),
                      label: busy ? 'Pause story' : 'Play story',
                      onTap: _togglePlay,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: DesignTokens.primary,
                          shape: BoxShape.circle,
                        ),
                        child: _loading && !_playing
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                busy
                                    ? CupertinoIcons.pause_fill
                                    : CupertinoIcons.play_fill,
                                color: DesignTokens.onPrimary,
                                size: 26,
                              ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _dockButton(
                      const ValueKey('story.dock.stop'),
                      'Stop',
                      CupertinoIcons.stop_fill,
                      () async {
                        await _audio.stop();
                      },
                    ),
                    V3Pressable(
                      key: const ValueKey('story.dock.rate'),
                      label:
                          'Speed ${SessionSettings.playbackRateLabel(_settings.playbackRate)}x',
                      onTap: _cycleRate,
                      child: SizedBox(
                        width: 56,
                        height: 48,
                        child: Center(
                          child: Text(
                            '${SessionSettings.playbackRateLabel(_settings.playbackRate)}×',
                            style: V3Type.strong(15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dockButton(
    Key key,
    String label,
    IconData icon,
    FutureOr<void> Function() onTap,
  ) {
    return V3Pressable(
      key: key,
      label: label,
      onTap: () => unawaited(Future.sync(onTap)),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(icon, size: 21, color: DesignTokens.ink),
      ),
    );
  }

  // ---- Quiz tab --------------------------------------------------------

  List<Widget> _quizTab() {
    if (_qFinished) return _quizResult();
    final q = _story.quiz[_qIndex];
    final last = _qIndex == _story.quiz.length - 1;
    return [
      const SizedBox(height: 10),
      Text(
        'QUESTION ${_qIndex + 1} OF ${_story.quiz.length}',
        style: V3Type.eyebrow(),
      ),
      const SizedBox(height: 10),
      Text(q.prompt, style: V3Type.title(26)),
      const SizedBox(height: 20),
      for (var i = 0; i < q.options.length; i++) ...[
        V3OptionCard(
          key: ValueKey('story.quiz.option.$i'),
          title: q.options[i],
          selected: _qSelected == i,
          tone: !_qChecked
              ? V3Tone.none
              : i == q.answer
              ? V3Tone.correct
              : (i == _qSelected ? V3Tone.wrong : V3Tone.none),
          onTap: _qChecked ? null : () => setState(() => _qSelected = i),
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 8),
      if (_qChecked) ...[
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _qSelected == q.answer
                ? DesignTokens.successSoft
                : DesignTokens.dangerSoft,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _qSelected == q.answer ? 'Correct' : 'Not quite',
                style: V3Type.title(
                  22,
                  color: _qSelected == q.answer
                      ? DesignTokens.success
                      : DesignTokens.danger,
                ),
              ),
              const SizedBox(height: 6),
              if (_qSelected != q.answer) ...[
                Text(
                  'Answer: ${q.options[q.answer]}',
                  style: V3Type.strong(15, DesignTokens.danger),
                ),
                const SizedBox(height: 4),
              ],
              Text(q.explain, style: V3Type.body(15, DesignTokens.ink)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        V3Button(
          key: const ValueKey('story.quiz.next'),
          label: last ? 'See result' : 'Next question',
          onTap: () => setState(() {
            if (last) {
              _qFinished = true;
              unawaited(V3StoryProgress.markDone(_story.id));
            } else {
              _qIndex += 1;
              _qSelected = null;
              _qChecked = false;
            }
          }),
        ),
      ] else
        V3Button(
          key: const ValueKey('story.quiz.check'),
          label: 'Check',
          onTap: _qSelected == null
              ? null
              : () => setState(() {
                  _qChecked = true;
                  if (_qSelected == q.answer) {
                    _qCorrect += 1;
                    PSHaptics.success();
                  }
                }),
        ),
    ];
  }

  List<Widget> _quizResult() {
    final total = _story.quiz.length;
    return [
      const SizedBox(height: 14),
      Text('STORY READ', style: V3Type.eyebrow()),
      const SizedBox(height: 10),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$_qCorrect',
              style: V3Type.hero(64, color: DesignTokens.primary),
            ),
            TextSpan(
              text: '  of $total correct',
              style: V3Type.body(20, DesignTokens.ink),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text('Saved. You can read it again any time.', style: V3Type.body(16)),
      const SizedBox(height: 24),
      V3Button(
        key: const ValueKey('story.finish'),
        label: 'Done',
        onTap: () => Navigator.of(context).pop(true),
      ),
    ];
  }

  // ---- Words tab -------------------------------------------------------

  List<Widget> _wordsTab() {
    return [
      const SizedBox(height: 8),
      Text(
        '${_story.keywords.length} KEY WORDS IN THIS STORY',
        style: V3Type.eyebrow(DesignTokens.inkSoft),
      ),
      const SizedBox(height: 4),
      for (final k in _story.keywords) _wordRow(k),
    ];
  }

  Widget _wordRow(String key) {
    final w = _story.words[key]!;
    final saved = _saved.contains('${_story.id}|$key');
    final meta = [
      w.pos,
      if (w.sound.isNotEmpty) w.sound,
    ].where((e) => e.isNotEmpty).join('  ·  ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: DesignTokens.hairline)),
      ),
      child: Row(
        children: [
          V3Pressable(
            key: ValueKey('story.words.hear.$key'),
            label: 'Hear $key',
            onTap: () => unawaited(_audio.speakWord(key)),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: DesignTokens.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.speaker_2_fill,
                size: 19,
                color: DesignTokens.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(key, style: V3Type.strong(19)),
                const SizedBox(height: 2),
                Text(w.en, style: V3Type.body(14)),
                if (meta.isNotEmpty) Text(meta, style: V3Type.body(12.5)),
              ],
            ),
          ),
          V3Pressable(
            key: ValueKey('story.words.save.$key'),
            label: saved ? 'Unsave $key' : 'Save $key',
            onTap: () async {
              await V3StoryProgress.toggleSaved(_story.id, key);
              final s = await V3StoryProgress.savedWords();
              if (mounted) setState(() => _saved = s);
            },
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                saved ? CupertinoIcons.star_fill : CupertinoIcons.star,
                size: 22,
                color: saved ? DesignTokens.mastery : DesignTokens.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The small card that appears just above a tapped word. Small on purpose:
/// the word and its meaning, nothing that competes with the story.
class _WordPopover extends StatelessWidget {
  const _WordPopover({
    required this.anchor,
    required this.word,
    required this.meaning,
    required this.onDismiss,
    required this.onHear,
  });

  final Rect anchor;
  final String word;
  final V3Word meaning;
  final VoidCallback onDismiss;
  final VoidCallback onHear;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(250.0, size.width - 32);
    final left = (anchor.center.dx - width / 2).clamp(
      16.0,
      size.width - 16 - width,
    );
    final arrowX = (anchor.center.dx - left - 7).clamp(18.0, width - 32);
    final above = anchor.top > 190;
    final meta = [
      meaning.pos,
      if (meaning.sound.isNotEmpty) meaning.sound,
    ].where((e) => e.isNotEmpty).join('  ·  ');

    final card = Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignTokens.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(word, style: V3Type.strong(17)),
                const SizedBox(height: 2),
                Text(meaning.en, style: V3Type.body(14.5, DesignTokens.ink)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(meta, style: V3Type.body(12)),
                ],
              ],
            ),
          ),
          V3Pressable(
            key: const ValueKey('story.popover.hear'),
            label: 'Hear word',
            onTap: onHear,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                CupertinoIcons.speaker_2_fill,
                size: 20,
                color: DesignTokens.primary,
              ),
            ),
          ),
        ],
      ),
    );

    final arrow = Positioned(
      left: arrowX,
      top: above ? null : -6,
      bottom: above ? -6 : null,
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            border: Border(
              right: above
                  ? BorderSide(color: DesignTokens.hairline)
                  : BorderSide.none,
              bottom: above
                  ? BorderSide(color: DesignTokens.hairline)
                  : BorderSide.none,
              left: above
                  ? BorderSide.none
                  : BorderSide(color: DesignTokens.hairline),
              top: above
                  ? BorderSide.none
                  : BorderSide(color: DesignTokens.hairline),
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('story.popover.dismiss'),
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: left,
          width: width,
          top: above ? null : anchor.bottom + 10,
          bottom: above ? size.height - anchor.top + 10 : null,
          child: Semantics(
            key: const ValueKey('story.popover'),
            container: true,
            label: 'Meaning of $word: ${meaning.en}',
            child: Material(
              type: MaterialType.transparency,
              child: Stack(clipBehavior: Clip.none, children: [card, arrow]),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.settings, required this.onRate});

  final SessionSettings settings;
  final void Function(double rate) onRate;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  SessionSettings get s => widget.settings;

  Widget _toggle(
    String id,
    String title,
    String sub,
    bool value,
    Future<void> Function(bool) set,
  ) {
    return V3Pressable(
      key: ValueKey('story.settings.$id'),
      label: '$title, ${value ? 'on' : 'off'}',
      onTap: () async {
        await set(!value);
        if (mounted) setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        color: Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: V3Type.strong(16)),
                  const SizedBox(height: 2),
                  Text(sub, style: V3Type.body(13)),
                ],
              ),
            ),
            IgnorePointer(
              child: CupertinoSwitch(
                value: value,
                activeTrackColor: DesignTokens.primary,
                onChanged: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choices<T>(
    String id,
    String title,
    List<(T, String)> items,
    bool Function(T) isOn,
    Future<void> Function(T) set,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V3Type.strong(16)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final it in items) ...[
                Expanded(
                  child: V3Pressable(
                    key: ValueKey('story.settings.$id.${it.$2}'),
                    label: '$title ${it.$2}',
                    onTap: () async {
                      await set(it.$1);
                      if (mounted) setState(() {});
                    },
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isOn(it.$1)
                            ? DesignTokens.primary
                            : DesignTokens.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isOn(it.$1)
                              ? DesignTokens.primary
                              : DesignTokens.hairline,
                        ),
                      ),
                      child: Text(
                        it.$2,
                        style: V3Type.strong(
                          14.5,
                          isOn(it.$1)
                              ? DesignTokens.onPrimary
                              : DesignTokens.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                if (it != items.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + bottom),
      decoration: BoxDecoration(
        color: DesignTokens.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: DesignTokens.hairline,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Story settings', style: V3Type.title(26)),
          const SizedBox(height: 8),
          _toggle(
            'translation',
            'Show translation',
            'English under every sentence',
            s.translateSentences,
            s.setTranslateSentences,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: V3StoryProgress.hearWords,
            builder: (_, on, _) => _toggle(
              'hearWords',
              'Hear words when tapped',
              'Marie says the word you tap',
              on,
              V3StoryProgress.setHearWords,
            ),
          ),
          _toggle(
            'highlight',
            'Highlight the spoken word',
            'Follows Marie while she reads',
            s.highlightWords,
            s.setHighlightWords,
          ),
          _choices<double>(
            'size',
            'Text size',
            const [(0.9, 'Small'), (1.0, 'Medium'), (1.2, 'Large')],
            (v) => (s.textScale - v).abs() < 0.06,
            s.setTextScale,
          ),
          _choices<double>(
            'speed',
            'Reading speed',
            [
              for (final r in SessionSettings.playbackRates)
                (r, '${SessionSettings.playbackRateLabel(r)}×'),
            ],
            (v) => (s.playbackRate - v).abs() < 0.001,
            (v) async {
              await s.setPlaybackRate(v);
              widget.onRate(v);
            },
          ),
        ],
      ),
    );
  }
}
