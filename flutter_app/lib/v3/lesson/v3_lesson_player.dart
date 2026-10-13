import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart' show PSHaptics;
import '../../widgets/tts_play_button.dart';
import '../marie/v3_marie_dock.dart';
import '../marie/v3_marie_session.dart';
import '../ui/v3_ui.dart';
import 'v3_course.dart';
import 'v3_lesson.dart';

/// V3 lesson player. Screen contract:
///
/// User arrived to: do one lesson from the Learn tab.
/// They must understand: what to do on this step, and how far they are.
/// Primary action: one per step (Continue, or Check then Continue).
/// Secondary: hear any French line, Ask Marie, close.
/// Success state: the lesson is complete, recorded, and the result is shown.
/// Must not contain: confetti, XP, hearts, timers, anything centered.
///
/// Voice: every French line has a speaker that plays Gemini Live in the
/// selected tutor's voice (saved after it is made once). Ask Marie opens the
/// live tutor with the current step as context.
class V3LessonPlayer extends ConsumerStatefulWidget {
  const V3LessonPlayer({
    super.key,
    required this.lesson,
    this.startAt = 0,
    @visibleForTesting this.marie,
  });

  final V3Lesson lesson;

  /// Step to start from when the learner left this lesson half way.
  final int startAt;

  /// Tests pass a scripted Marie. Production builds the real one.
  final V3MarieSession? marie;

  @override
  ConsumerState<V3LessonPlayer> createState() => _V3LessonPlayerState();
}

class _V3LessonPlayerState extends ConsumerState<V3LessonPlayer>
    with WidgetsBindingObserver {
  late final V3MarieSession _marie;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _marie =
        widget.marie ??
        V3MarieSession.create(
          store: () => ref.read(learningStoreProvider),
          context: _marieContext,
        );
    _marie.addListener(_onMarie);
  }

  void _onMarie() {
    if (!mounted) return;
    setState(() {});
    final note = _marie.endedNote;
    if (note != null) {
      _marie.clearEndedNote();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(note)));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _marie.handleLifecycle(state);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _marie.removeListener(_onMarie);
    // A scripted Marie passed in by a test belongs to the test.
    if (widget.marie == null) _marie.dispose();
    super.dispose();
  }

  late int _index = widget.startAt.clamp(0, widget.lesson.steps.length - 1);
  var _lastAdvance = DateTime.fromMillisecondsSinceEpoch(0);
  int? _selected;
  var _checked = false;
  var _complete = false;
  final _results = <String, bool>{};
  final _missed = <String>[];
  final _listenedOnce = <String>{};

  V3Lesson get _lesson => widget.lesson;
  V3Step get _step => _lesson.steps[_index];
  bool get _isQuestion => _step is V3ChooseStep || _step is V3ListenStep;
  int get _answer => switch (_step) {
    V3ChooseStep s => s.answer,
    V3ListenStep s => s.answer,
    _ => -1,
  };
  List<String> get _options => switch (_step) {
    V3ChooseStep s => s.options,
    V3ListenStep s => s.options,
    _ => const [],
  };
  String get _explain => switch (_step) {
    V3ChooseStep s => s.explain,
    V3ListenStep s => s.explain,
    _ => '',
  };

  String _audioId(String slot) => 'v3-${_lesson.id}-${_step.id}-$slot';

  void _check() {
    _lastAdvance = DateTime.now();
    final correct = _selected == _answer;
    _results[_step.id] = correct;
    if (!correct) {
      _missed.add(switch (_step) {
        V3ChooseStep s => s.promptFr.isNotEmpty ? s.promptFr : s.prompt,
        V3ListenStep s => s.question,
        _ => '',
      });
    }
    correct ? PSHaptics.success() : HapticFeedback.heavyImpact();
    setState(() => _checked = true);
    _marie.screenUpdated();
  }

  void _next() {
    // A double tap must never skip a step: ignore a second tap right away.
    final now = DateTime.now();
    if (now.difference(_lastAdvance) < const Duration(milliseconds: 450)) {
      return;
    }
    _lastAdvance = now;
    if (_index == _lesson.steps.length - 1) {
      unawaited(V3Progress.markDone(_lesson.id));
      unawaited(_marie.end());
      setState(() => _complete = true);
      return;
    }
    setState(() {
      _index += 1;
      _selected = null;
      _checked = false;
    });
    unawaited(V3Progress.savePosition(_lesson.id, _index));
    _marie.screenChanged();
  }

  /// What Marie knows about the screen, replaced on every step. Small on
  /// purpose: it is re-sent whenever the step changes.
  String _marieContext() {
    String cut(String v, [int max = 700]) =>
        v.length <= max ? v : '${v.substring(0, max)}...';
    final level = LivePrompts.normalizeLevel(
      ref.read(learningStoreProvider).profile().level,
    );
    final b = StringBuffer(
      'LEARNER LEVEL: $level. LESSON: ${_lesson.title} '
      '(step ${_index + 1} of ${_lesson.steps.length}). ',
    );
    switch (_step) {
      case V3ExplainStep s:
        b.write('ON SCREEN (explanation): ${s.title}. ${cut(s.body)}');
        if (s.examples.isNotEmpty) {
          b.write(
            ' Examples: ${s.examples.take(6).map((e) => '${e.fr} = ${e.en}').join('; ')}.',
          );
        }
      case V3WordStep s:
        b.write('ON SCREEN (new word): "${s.fr}" means "${s.en}".');
        if (s.sound.isNotEmpty) b.write(' Sound guide shown: ${s.sound}.');
        if (s.exampleFr.isNotEmpty) {
          b.write(' Example shown: ${s.exampleFr} (${s.exampleEn}).');
        }
      case V3PhraseStep s:
        b.write(
          'ON SCREEN (phrase to say aloud): "${s.fr}" means "${s.en}". '
          'If the learner says it, give pronunciation feedback.',
        );
      case V3TableStep s:
        b.write(
          'ON SCREEN (reference table): ${s.title}. Columns: ${s.headers.join(', ')}. '
          'Rows: ${s.rows.take(8).map((r) => r.join(' | ')).join('; ')}.',
        );
      case V3ChooseStep s:
        b.write(
          'ON SCREEN (question): ${s.prompt} ${s.promptFr}. '
          'Options: ${s.options.join(' / ')}. ',
        );
        b.write(
          _checked
              ? 'ANSWERED: the learner chose "${s.options[_selected ?? 0]}"; the '
                    'correct answer is "${s.options[s.answer]}". You may explain.'
              : 'NOT ANSWERED YET: do not reveal the answer; hint or explain the rule.',
        );
      case V3ListenStep s:
        b.write(
          'ON SCREEN (listening question): ${s.question} '
          'Options: ${s.options.join(' / ')}. ',
        );
        b.write(
          _checked
              ? 'ANSWERED: the audio said "${s.fr}"; the correct answer is '
                    '"${s.options[s.answer]}". You may explain.'
              : 'NOT ANSWERED YET: do not reveal the audio text or the answer.',
        );
    }
    return b.toString();
  }

  void _toggleMarie() => unawaited(_marie.toggle(context));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: V3Width(
        child: SafeArea(
          bottom: false,
          child: _complete ? _completeView() : _lessonView(),
        ),
      ),
    );
  }

  // ---- Lesson view -------------------------------------------------------

  Widget _lessonView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 20, 0),
          child: Row(
            children: [
              V3Pressable(
                key: const ValueKey('lesson.close'),
                label: 'Close lesson',
                onTap: () => Navigator.of(context).pop(false),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.close_rounded, color: DesignTokens.ink),
                ),
              ),
              Expanded(
                child: V3Segments(count: _lesson.steps.length, current: _index),
              ),
              const SizedBox(width: 14),
              V3MarieCallButton(session: _marie, onTap: _toggleMarie),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: ListView(
              key: ValueKey('step-${_step.id}'),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              children: _stepBody(),
            ),
          ),
        ),
        V3MarieDock(session: _marie),
        _bottomBar(),
      ],
    );
  }

  List<Widget> _stepBody() {
    final s = _step;
    return switch (s) {
      V3ExplainStep() => _explainBody(s),
      V3WordStep() => _word(s),
      V3PhraseStep() => _phrase(s),
      V3TableStep() => _table(s),
      V3ChooseStep() => _choose(s),
      V3ListenStep() => _listen(s),
    };
  }

  List<Widget> _explainBody(V3ExplainStep s) => [
    Text('LEARN', style: V3Type.eyebrow()),
    const SizedBox(height: 10),
    Text(s.title, style: V3Type.title(34)),
    const SizedBox(height: 18),
    for (final p in s.body.split('\n\n')) ...[
      Text(p, style: V3Type.body(18, DesignTokens.ink)),
      const SizedBox(height: 14),
    ],
    if (s.examples.isNotEmpty) ...[
      const SizedBox(height: 6),
      for (var i = 0; i < s.examples.length; i++)
        _exampleRow(s.examples[i], '${_audioId('ex')}-$i'),
    ],
  ];

  Widget _exampleRow(V3FrLine line, String audioId) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: DesignTokens.hairline)),
    ),
    child: Row(
      children: [
        V3Speaker(text: line.fr, audioId: audioId, size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.fr, style: V3Type.strong(19)),
              const SizedBox(height: 2),
              Text(line.en, style: V3Type.body(14.5)),
            ],
          ),
        ),
      ],
    ),
  );

  List<Widget> _word(V3WordStep s) => [
    Text('NEW WORD', style: V3Type.eyebrow()),
    const SizedBox(height: 14),
    Text(
      s.fr,
      style: V3Type.hero(
        s.fr.length <= 10
            ? 58
            : s.fr.length <= 18
            ? 42
            : 30,
      ),
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        V3Speaker(text: s.spoken, audioId: _audioId('word'), size: 56),
        if (s.sound.isNotEmpty) ...[
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Sounds like  ${s.sound}',
              style: V3Type.body(16, DesignTokens.ink),
            ),
          ),
        ],
      ],
    ),
    const SizedBox(height: 28),
    Text(s.en, style: V3Type.title(30, color: DesignTokens.primary)),
    if (s.exampleFr.isNotEmpty) ...[
      const SizedBox(height: 28),
      Text('IN A SENTENCE', style: V3Type.eyebrow(DesignTokens.inkSoft)),
      const SizedBox(height: 8),
      _exampleRow(V3FrLine(s.exampleFr, s.exampleEn), _audioId('ex')),
    ],
  ];

  List<Widget> _phrase(V3PhraseStep s) => [
    Text('SAY IT OUT LOUD', style: V3Type.eyebrow()),
    const SizedBox(height: 14),
    Text(s.fr, style: V3Type.title(s.fr.length <= 24 ? 38 : 28)),
    const SizedBox(height: 16),
    Row(
      children: [
        V3Speaker(text: s.spoken, audioId: _audioId('phrase'), size: 56),
        const SizedBox(width: 16),
        Expanded(child: Text(s.en, style: V3Type.body(17, DesignTokens.ink))),
      ],
    ),
    if (s.tip.isNotEmpty) ...[
      const SizedBox(height: 26),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DesignTokens.primarySoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(s.tip, style: V3Type.body(15, DesignTokens.ink)),
      ),
    ],
    const SizedBox(height: 22),
    Text(
      'Listen first, then say it yourself. Tap Ask Marie if you want her to listen.',
      style: V3Type.body(15),
    ),
  ];

  List<Widget> _table(V3TableStep s) {
    final cols = s.headers.length;
    return [
      Text('REFERENCE', style: V3Type.eyebrow()),
      const SizedBox(height: 10),
      Text(s.title, style: V3Type.title(28)),
      const SizedBox(height: 18),
      Container(
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: DesignTokens.hairline),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  for (var c = 0; c < cols; c++)
                    Expanded(
                      flex: c == s.hear ? 3 : 2,
                      child: Text(
                        s.headers[c].toUpperCase(),
                        style: V3Type.eyebrow(DesignTokens.inkSoft),
                      ),
                    ),
                ],
              ),
            ),
            for (var r = 0; r < s.rows.length; r++)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: DesignTokens.hairline)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var c = 0; c < cols; c++)
                      Expanded(
                        flex: c == s.hear ? 3 : 2,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            s.rows[r][c],
                            style: c == 0
                                ? V3Type.strong(15)
                                : V3Type.body(14, DesignTokens.ink),
                          ),
                        ),
                      ),
                    if (s.hear >= 0)
                      V3Speaker(
                        text: s.rows[r][s.hear],
                        audioId: '${_audioId('row')}-$r',
                        size: 40,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _choose(V3ChooseStep s) => [
    Text('CHOOSE', style: V3Type.eyebrow()),
    const SizedBox(height: 12),
    Text(s.prompt, style: V3Type.title(28)),
    if (s.promptFr.isNotEmpty) ...[
      const SizedBox(height: 16),
      Row(
        children: [
          V3Speaker(text: s.promptFr, audioId: _audioId('prompt'), size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: s.promptFr.length > 30
                ? Text(s.promptFr, style: V3Type.reading(21))
                : Text(
                    s.promptFr,
                    style: V3Type.title(34, color: DesignTokens.primary),
                  ),
          ),
        ],
      ),
    ],
    const SizedBox(height: 22),
    ..._optionCards(),
  ];

  List<Widget> _listen(V3ListenStep s) {
    final locked = _listenedOnce.contains(s.id) && !_checked;
    return [
      Text('LISTEN ONCE', style: V3Type.eyebrow()),
      const SizedBox(height: 12),
      Text(s.question, style: V3Type.title(28)),
      const SizedBox(height: 18),
      Row(
        children: [
          V3Speaker(
            text: s.fr,
            audioId: _audioId('listen'),
            size: 72,
            oneShot: !_checked,
            onPlayed: () => setState(() => _listenedOnce.add(s.id)),
            hidden: !_checked,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _checked
                  ? s.fr
                  : locked
                  ? 'Played. Now choose your answer.'
                  : 'Tap to listen. You can play it once, like the real test.',
              style: _checked
                  ? V3Type.strong(20)
                  : V3Type.body(15.5, DesignTokens.ink),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      ..._optionCards(),
    ];
  }

  List<Widget> _optionCards() {
    final options = _options;
    return [
      for (var i = 0; i < options.length; i++) ...[
        V3OptionCard(
          key: ValueKey('lesson.option.$i'),
          title: options[i],
          selected: _selected == i,
          tone: !_checked
              ? V3Tone.none
              : i == _answer
              ? V3Tone.correct
              : (i == _selected ? V3Tone.wrong : V3Tone.none),
          onTap: _checked ? null : () => setState(() => _selected = i),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  // ---- Bottom bar --------------------------------------------------------

  Widget _bottomBar() {
    // The bar owns the bottom inset so the feedback colour reaches the edge.
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    if (_isQuestion && _checked) {
      final correct = _results[_step.id] == true;
      final tone = correct ? DesignTokens.success : DesignTokens.danger;
      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(24, 18, 24, 16 + safeBottom),
        decoration: BoxDecoration(
          color: correct ? DesignTokens.successSoft : DesignTokens.dangerSoft,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              correct ? 'Correct' : 'Not quite',
              style: V3Type.title(24, color: tone),
            ),
            if (!correct) ...[
              const SizedBox(height: 6),
              Text(
                'Answer: ${_options[_answer]}',
                style: V3Type.strong(16, tone),
              ),
            ],
            if (_explain.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_explain, style: V3Type.body(15, DesignTokens.ink)),
            ],
            const SizedBox(height: 16),
            V3Button(
              key: const ValueKey('lesson.continue'),
              label: 'Continue',
              onTap: _next,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + safeBottom),
      child: _isQuestion
          ? V3Button(
              key: const ValueKey('lesson.check'),
              label: 'Check',
              onTap: _selected == null ? null : _check,
            )
          : V3Button(
              key: const ValueKey('lesson.continue'),
              label: 'Continue',
              onTap: _next,
            ),
    );
  }

  // ---- Complete view -----------------------------------------------------

  Widget _completeView() {
    final total = _lesson.questionCount;
    final right = _results.values.where((v) => v).length;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LESSON COMPLETE', style: V3Type.eyebrow()),
          const SizedBox(height: 12),
          Text('Well done.', style: V3Type.hero(54)),
          const SizedBox(height: 10),
          Text(_lesson.title, style: V3Type.body(18)),
          const SizedBox(height: 26),
          if (total > 0)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$right',
                    style: V3Type.hero(64, color: DesignTokens.primary),
                  ),
                  TextSpan(
                    text: '  of $total correct',
                    style: V3Type.body(20, DesignTokens.ink),
                  ),
                ],
              ),
            ),
          if (_missed.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('REVIEW THESE', style: V3Type.eyebrow(DesignTokens.danger)),
            const SizedBox(height: 8),
            for (final m in _missed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(m, style: V3Type.strong(17)),
              ),
          ],
          const Spacer(),
          V3Button(
            key: const ValueKey('lesson.done'),
            label: 'Done',
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}

/// Speaker for one French line. Plays Gemini Live in the selected tutor's
/// voice through the existing [TtsPlayButton] (saved after the first play).
/// [oneShot] allows a single play, like the TCF listening test. [hidden]
/// keeps the French text out of the accessibility label until it may be seen.
class V3Speaker extends StatefulWidget {
  const V3Speaker({
    super.key,
    required this.text,
    required this.audioId,
    this.size = 48,
    this.oneShot = false,
    this.hidden = false,
    this.onPlayed,
  });

  final String text;
  final String audioId;
  final double size;
  final bool oneShot;
  final bool hidden;
  final VoidCallback? onPlayed;

  @override
  State<V3Speaker> createState() => _V3SpeakerState();
}

class _V3SpeakerState extends State<V3Speaker> {
  final _tts = GlobalKey<TtsPlayButtonState>();
  var _played = false;

  Future<void> _tap() async {
    if (widget.oneShot && _played) return;
    _played = true;
    widget.onPlayed?.call();
    await _tts.currentState?.trigger();
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.oneShot && _played;
    return V3Pressable(
      label: widget.hidden ? 'Play audio' : 'Hear ${widget.text}',
      onTap: locked ? null : _tap,
      child: Opacity(
        opacity: locked ? 0.45 : 1,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: DesignTokens.primarySoft,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: IgnorePointer(
            child: TtsPlayButton(
              key: _tts,
              text: widget.text,
              contentItemId: widget.audioId,
              size: widget.size,
              iconSize: widget.size * 0.44,
              onError: (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not play the audio. Check your connection.',
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
