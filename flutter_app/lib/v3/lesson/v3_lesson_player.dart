import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tutor_persona.dart';
import '../../design/tokens.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/session_recorder.dart';
import '../../widgets/adaptive/adaptive.dart' show PSHaptics;
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
/// Secondary: hear any French line, call the selected tutor, close.
/// Success state: the lesson is complete, recorded, and the result is shown.
/// Must not contain: confetti, XP, hearts, timers, anything centered.
///
/// Voice: every French line has a speaker that plays Gemini Live in the
/// selected tutor's voice (saved after it is made once). The call button opens the
/// live tutor with the current step as context.
class V3LessonPlayer extends ConsumerStatefulWidget {
  const V3LessonPlayer({
    super.key,
    required this.lesson,
    this.startAt = 0,
    this.frontier = 0,
    this.reviewAll = false,
    this.savePathProgress = true,
    this.answerChecker,
    this.onStepChanged,
    this.onCompleted,
    this.completionEyebrow = 'LESSON COMPLETE',
    this.completionTitle = 'Well done.',
    @visibleForTesting this.marie,
  });

  final V3Lesson lesson;

  /// Step to start from when the learner left this lesson half way.
  final int startAt;

  /// The furthest step the learner has really reached (real progress). Going
  /// back to review never lowers it.
  final int frontier;

  /// True when the lesson is already finished: every step can be revisited
  /// freely and nothing here changes the learner's progress.
  final bool reviewAll;

  /// False for authored practice packages that are not part of course order.
  final bool savePathProgress;

  /// Optional trusted check for remotely published challenge answers.
  final Future<V3AnswerFeedback> Function(String stepId, int selectedIndex)?
  answerChecker;

  /// Called when the learner advances, allowing a daily package to resume.
  final Future<void> Function(int step)? onStepChanged;

  /// Called after the final step, without modifying course progress.
  final Future<void> Function(Map<String, bool> results)? onCompleted;

  final String completionEyebrow;
  final String completionTitle;

  /// A second tap on Continue inside this window is ignored, so a double tap
  /// can never skip a step. Tests shorten it because they cannot move the real
  /// clock.
  @visibleForTesting
  static Duration advanceGuard = const Duration(milliseconds: 450);

  /// Tests pass a scripted Marie. Production builds the real one.
  final V3MarieSession? marie;

  @override
  ConsumerState<V3LessonPlayer> createState() => _V3LessonPlayerState();
}

class _V3LessonPlayerState extends ConsumerState<V3LessonPlayer>
    with WidgetsBindingObserver {
  late final V3MarieSession _marie;
  SessionRecorder? _recorder;

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
    try {
      _recorder = SessionRecorder(
        storage: ref.read(storageServiceProvider),
        stage: widget.savePathProgress ? 'v3_lesson' : 'daily_challenge',
        topic: _lesson.title,
      );
    } on UnimplementedError {
      // Isolated layout tests can mount the player without the app database.
      // A fully wired app always provides StorageService, so learner sessions
      // still persist for streak and fingerprint evidence.
    }
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

  /// Furthest step reached. Review (going back) never lowers it.
  late int _frontier = widget.reviewAll
      ? widget.lesson.steps.length - 1
      : widget.frontier.clamp(_index, widget.lesson.steps.length - 1);

  /// What the learner chose on each question this visit, so going back shows
  /// the answer again instead of asking twice.
  final _answers = <String, int>{};
  var _lastAdvance = DateTime.fromMillisecondsSinceEpoch(0);
  int? _selected;
  var _checked = false;
  var _checking = false;
  var _savingProgress = false;
  var _complete = false;
  final _results = <String, bool>{};
  final _missed = <String>[];
  final _listenedOnce = <String>{};
  String? _remoteExplanation;
  String? _remoteCorrectAnswer;

  /// The last step whose lines were already asked for. Each step is asked for
  /// once, so the final steps never trigger a second round.
  var _readyThrough = -1;

  /// The French lines a step's speaker buttons will play.
  List<String> _speakerLines(V3Step step) => switch (step) {
    V3WordStep s => [s.spoken, s.exampleFr],
    V3PhraseStep s => [s.spoken],
    V3ExplainStep s => s.examples.take(2).map((e) => e.fr).toList(),
    V3ChooseStep s => [s.promptFr],
    V3ListenStep s => [s.fr],
    V3TableStep _ => const [],
  };

  /// Asks, once, for the clips of this step and the next five.
  void _prepareUpcomingClips() {
    final steps = _lesson.steps;
    if (steps.isEmpty) return;
    final target = (_index + 5).clamp(0, steps.length - 1);
    final from = _readyThrough + 1 > _index ? _readyThrough + 1 : _index;
    if (from > target) return;
    _readyThrough = target;
    final lines = [
      for (var i = from; i <= target; i++) ..._speakerLines(steps[i]),
    ].where((l) => l.trim().isNotEmpty).toList();
    if (lines.isNotEmpty) _marie.prefetch(lines);
  }

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
  String get _explain =>
      _remoteExplanation ??
      switch (_step) {
        V3ChooseStep s => s.explain,
        V3ListenStep s => s.explain,
        _ => '',
      };

  String _audioId(String slot) => 'v3-${_lesson.id}-${_step.id}-$slot';

  Future<void> _check() async {
    if (_checking || _savingProgress || _selected == null) return;
    _lastAdvance = DateTime.now();
    V3AnswerFeedback? remote;
    if (widget.answerChecker != null) {
      setState(() => _checking = true);
      try {
        remote = await widget.answerChecker!(_step.id, _selected!);
      } catch (_) {
        if (!mounted) return;
        setState(() => _checking = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not check this answer. Try again.'),
            ),
          );
        return;
      }
      if (!mounted) return;
      setState(() => _checking = false);
    }
    final correct = remote?.correct ?? _selected == _answer;
    _remoteExplanation = remote?.explanation;
    _remoteCorrectAnswer = remote?.correctAnswer;
    _results[_step.id] = correct;
    _answers[_step.id] = _selected!;
    if (!correct) {
      _missed.add(switch (_step) {
        V3ChooseStep s => s.promptFr.isNotEmpty ? s.promptFr : s.prompt,
        V3ListenStep s => s.question,
        _ => '',
      });
    }
    if (correct) {
      // This brief native click is intentionally paired with a soft success
      // haptic. Close Marie's mic first so the sound can never be transcribed
      // as learner speech; the short hold also covers the system sound tail.
      _marie.blockMicUntil(
        DateTime.now().add(const Duration(milliseconds: 700)),
      );
      unawaited(SystemSound.play(SystemSoundType.click));
      PSHaptics.success();
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() => _checked = true);
    _marie.screenUpdated();
  }

  Future<void> _next() async {
    if (_savingProgress) return;
    // A double tap must never skip a step: ignore a second tap right away.
    final now = DateTime.now();
    if (now.difference(_lastAdvance) < V3LessonPlayer.advanceGuard) return;
    _lastAdvance = now;
    if (_index == _lesson.steps.length - 1) {
      if (widget.savePathProgress) {
        await V3Progress.markDone(
          _lesson.id,
          store: ref.read(learningStoreProvider),
        );
      }
      _recorder?.finish(
        summary: widget.savePathProgress
            ? 'Completed the course lesson.'
            : 'Completed the daily TCF challenge.',
        autoNote: false,
      );
      unawaited(_marie.end());
      final completed = widget.onCompleted;
      if (completed != null) await completed(Map.unmodifiable(_results));
      if (!mounted) return;
      setState(() => _complete = true);
      return;
    }
    final changed = widget.onStepChanged;
    final previousIndex = _index;
    final previousFrontier = _frontier;
    setState(() {
      _index += 1;
      if (_index > _frontier) _frontier = _index;
      _savingProgress = changed != null;
      _restoreStepState();
    });
    if (widget.savePathProgress) {
      await V3Progress.advanceFrontier(
        _lesson.id,
        _index,
        store: ref.read(learningStoreProvider),
      );
    }
    if (!mounted) return;
    if (changed != null) {
      try {
        await changed(_index);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _index = previousIndex;
          _frontier = previousFrontier;
          _savingProgress = false;
          _restoreStepState();
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Progress could not be saved. Try continuing again.',
              ),
            ),
          );
        _marie.screenChanged();
        return;
      }
      if (!mounted) return;
      setState(() => _savingProgress = false);
    }
    _marie.screenChanged();
  }

  /// Back to the step before, to look again. Real progress is untouched: the
  /// frontier stays where it was, so Resume still returns there.
  void _back() {
    if (_savingProgress || _index == 0) return;
    setState(() {
      _index -= 1;
      _restoreStepState();
    });
    _marie.screenChanged();
  }

  void _jumpToFrontier() {
    if (_savingProgress || _index >= _frontier) return;
    setState(() {
      _index = _frontier;
      _restoreStepState();
    });
    _marie.screenChanged();
  }

  /// A step the learner already answered shows that answer; anything else is
  /// fresh.
  void _restoreStepState() {
    final answered = _answers[_step.id];
    _selected = answered;
    _checked = answered != null;
    _checking = false;
    _remoteExplanation = null;
    _remoteCorrectAnswer = null;
  }

  bool get _reviewing => !widget.reviewAll && _index < _frontier;

  /// What Marie knows about the screen, replaced on every step. Small on
  /// purpose: it is re-sent whenever the step changes.
  String _marieContext() {
    String cut(String v, [int max = 700]) =>
        v.length <= max ? v : '${v.substring(0, max)}...';
    final level = LivePrompts.normalizeLevel(
      ref.read(learningStoreProvider).profile().level,
    );
    final b = StringBuffer(
      'LEARNER LEVEL: $level${level == 'A1' || level == 'A2' ? ' (reply ONLY in English, even if asked in French; put French words inside the English)' : ''}. LESSON: ${_lesson.title} '
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
        b.write(
          ' If asked to repeat or say it slower, say ONLY "${s.fr}" slowly in '
          'French and stop.',
        );
      case V3PhraseStep s:
        b.write(
          'ON SCREEN (phrase to say aloud): "${s.fr}" means "${s.en}". '
          'If the learner says it, give pronunciation feedback. If asked to '
          'repeat or say it slower, say ONLY that French slowly and stop.',
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
    if (_readyThrough < _index + 5 &&
        _readyThrough < _lesson.steps.length - 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prepareUpcomingClips();
      });
    }
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
        if (_reviewing)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Reviewing. Your progress is at step ${_frontier + 1}.',
                    style: V3Type.body(13.5, DesignTokens.inkSoft),
                  ),
                ),
                V3Pressable(
                  key: const ValueKey('lesson.jumpToFrontier'),
                  label: 'Go to step ${_frontier + 1}',
                  onTap: _jumpToFrontier,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      'Go to step ${_frontier + 1}',
                      style: V3Type.strong(14, DesignTokens.primary),
                    ),
                  ),
                ),
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
        V3Speaker(text: line.fr, session: _marie, size: 44),
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
        V3Speaker(text: s.spoken, session: _marie, size: 56),
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
        V3Speaker(text: s.spoken, session: _marie, size: 56),
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
      'Listen first, then say it yourself. Call your tutor if you want feedback.',
      style: V3Type.body(15),
    ),
  ];

  /// Letters, numbers and months: each item with its own speaker, two to a
  /// line when there is room (one on a narrow screen or at large text).
  /// `letters` plays the bundled recording of the chosen tutor; `groups` says
  /// the French cell through the shared clip store.
  List<Widget> _groupsTable(V3TableStep s) {
    final letters = s.layout == 'letters';
    final g = letters ? 2 : s.group;
    final hearIn = letters ? 0 : (s.hear < 0 ? 0 : s.hear);
    final tutor = ActiveTutor.current.id;
    final cells = <List<String>>[
      for (final row in s.rows)
        for (var c = 0; c + g <= row.length; c += g)
          if (row[c].trim().isNotEmpty) row.sublist(c, c + g),
    ];
    final minCell = letters ? 140.0 : (g >= 3 ? 200.0 : 150.0);

    Widget cell(List<String> c, int index) {
      final lead = !letters && hearIn != 0;
      final main = c[hearIn];
      final speech = letters ? c[0] : V3TableStep.speechOf(main);
      final others = [
        for (var i = 0; i < c.length; i++)
          if (i != hearIn && !(lead && i == 0) && c[i].trim().isNotEmpty) c[i],
      ];
      return Row(
        children: [
          if (letters)
            SizedBox(
              width: 30,
              child: Text(
                c[0],
                style: V3Type.strong(
                  22,
                  DesignTokens.ink,
                ).copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          if (lead)
            SizedBox(
              width: 40,
              child: Text(
                c[0],
                style: V3Type.strong(
                  18,
                  DesignTokens.ink,
                ).copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          Expanded(
            child: letters
                ? Text(c[1], style: V3Type.body(16, DesignTokens.ink))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(main, style: V3Type.strong(17, DesignTokens.ink)),
                      if (others.isNotEmpty)
                        Text(
                          others.join('  ·  '),
                          style: V3Type.body(13, DesignTokens.inkSoft),
                        ),
                    ],
                  ),
          ),
          if (speech != null)
            V3Speaker(
              key: ValueKey(
                letters ? 'table.letter.${c[0]}' : 'table.cell.$index',
              ),
              text: speech,
              asset: letters
                  ? 'assets/audio/alphabet/$tutor/alphabet_letter_${c[0]}.pcm'
                  : null,
              session: _marie,
              size: 40,
            ),
        ],
      );
    }

    return [
      Text('REFERENCE', style: V3Type.eyebrow()),
      const SizedBox(height: 10),
      Text(s.title, style: V3Type.title(28)),
      const SizedBox(height: 18),
      LayoutBuilder(
        builder: (context, box) {
          final pref = letters ? 2 : s.perRow.clamp(1, 4);
          final roomy =
              box.maxWidth / pref >= minCell &&
              MediaQuery.textScalerOf(context).scale(16) <= 21;
          final perRow = roomy ? pref : 1;
          return Container(
            decoration: BoxDecoration(
              color: DesignTokens.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: DesignTokens.hairline),
            ),
            child: Column(
              children: [
                for (var i = 0; i < cells.length; i += perRow)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : Border(
                              top: BorderSide(color: DesignTokens.hairline),
                            ),
                    ),
                    child: Row(
                      children: [
                        for (var k = 0; k < perRow; k++) ...[
                          if (k > 0) const SizedBox(width: 12),
                          Expanded(
                            child: i + k < cells.length
                                ? cell(cells[i + k], i + k)
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ];
  }

  List<Widget> _table(V3TableStep s) {
    if (s.layout == 'letters' || s.layout == 'groups') return _groupsTable(s);
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
                          child: _gridCell(s, r, c),
                        ),
                      ),
                    if (s.hear >= 0 &&
                        V3TableStep.speechOf(s.rows[r][s.hear]) != null)
                      V3Speaker(
                        text: V3TableStep.speechOf(s.rows[r][s.hear])!,
                        session: _marie,
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

  /// One cell of the plain grid. A French cell listed in `hearCols` can be
  /// tapped to hear it.
  Widget _gridCell(V3TableStep s, int r, int c) {
    final text = s.rows[r][c];
    final style = c == 0
        ? V3Type.strong(15)
        : V3Type.body(14, DesignTokens.ink);
    if (!s.hearCols.contains(c)) return Text(text, style: style);
    final speech = V3TableStep.speechOf(
      text,
      prefix: s.hearPrefix && c != 0 ? s.rows[r][0] : null,
    );
    if (speech == null) return Text(text, style: style);
    return _HearCell(
      key: ValueKey('table.hear.$r.$c'),
      shown: text,
      speech: speech,
      session: _marie,
      style: style,
    );
  }

  List<Widget> _choose(V3ChooseStep s) => [
    Text('CHOOSE', style: V3Type.eyebrow()),
    const SizedBox(height: 12),
    Text(s.prompt, style: V3Type.title(28)),
    if (s.promptFr.isNotEmpty) ...[
      const SizedBox(height: 16),
      Row(
        children: [
          V3Speaker(text: s.promptFr, session: _marie, size: 52),
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
            session: _marie,
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

  Widget _backButton() {
    return V3Pressable(
      key: const ValueKey('lesson.back'),
      label: 'Previous step',
      onTap: _savingProgress ? null : _back,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: DesignTokens.hairline),
        ),
        child: Icon(
          CupertinoIcons.chevron_left,
          size: 22,
          color: DesignTokens.ink,
        ),
      ),
    );
  }

  /// The main button, with a Previous button beside it once there is a step to
  /// go back to. Continue stays the one dominant action.
  Widget _withBack(Widget main) {
    if (_index == 0) return main;
    return Row(
      children: [
        _backButton(),
        const SizedBox(width: 12),
        Expanded(child: main),
      ],
    );
  }

  Widget _bottomBar() {
    // The bar owns the bottom inset so the feedback colour reaches the edge.
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    if (_isQuestion && _checked) {
      final correct =
          _results[_step.id] == true ||
          (!_results.containsKey(_step.id) && _answers[_step.id] == _answer);
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
                'Answer: ${_remoteCorrectAnswer ?? _options[_answer]}',
                style: V3Type.strong(16, tone),
              ),
            ],
            if (_explain.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_explain, style: V3Type.body(15, DesignTokens.ink)),
            ],
            const SizedBox(height: 16),
            _withBack(
              V3Button(
                key: const ValueKey('lesson.continue'),
                label: _savingProgress ? 'Saving…' : 'Continue',
                onTap: _savingProgress ? null : () => unawaited(_next()),
              ),
            ),
          ],
        ),
      );
    }
    // Looking again at a question from earlier: answering is optional.
    final skippable =
        _isQuestion && !_checked && (_reviewing || widget.reviewAll);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _withBack(
            _isQuestion
                ? V3Button(
                    key: const ValueKey('lesson.check'),
                    label: _savingProgress
                        ? 'Saving…'
                        : _checking
                        ? 'Checking…'
                        : 'Check',
                    onTap: _selected == null || _checking || _savingProgress
                        ? null
                        : () => unawaited(_check()),
                  )
                : V3Button(
                    key: const ValueKey('lesson.continue'),
                    label: _savingProgress ? 'Saving…' : 'Continue',
                    onTap: _savingProgress ? null : () => unawaited(_next()),
                  ),
          ),
          if (skippable)
            V3Pressable(
              key: const ValueKey('lesson.skipQuestion'),
              label: 'Skip this question',
              onTap: _savingProgress ? null : () => unawaited(_next()),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.center,
                child: Text(
                  'Skip this question',
                  style: V3Type.strong(14.5, DesignTokens.primary),
                ),
              ),
            ),
        ],
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
          Text(widget.completionEyebrow, style: V3Type.eyebrow()),
          const SizedBox(height: 12),
          Text(widget.completionTitle, style: V3Type.hero(54)),
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

/// Speaker for one French line. It asks the tutor (live Marie, or whichever
/// tutor the learner chose) to say it, on the one warm connection the lesson
/// keeps. That is how the old vocabulary lessons worked: fast, always the
/// chosen voice, nothing saved that could be missing or in the wrong voice.
///
/// [oneShot] allows a single play, like the TCF listening test. It locks only
/// after the tutor was really reached, so a failed tap can be retried.
/// [hidden] keeps the French text out of the accessibility label until it may
/// be seen.
/// A table cell you tap to hear: the text with a small speaker beside it.
class _HearCell extends StatefulWidget {
  const _HearCell({
    super.key,
    required this.shown,
    required this.speech,
    required this.session,
    required this.style,
  });

  final String shown;
  final String speech;
  final V3MarieSession session;
  final TextStyle style;

  @override
  State<_HearCell> createState() => _HearCellState();
}

class _HearCellState extends State<_HearCell> {
  var _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final reached = await widget.session.speak(context, widget.speech);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!reached) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not play the audio. Check your connection and tap again.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final speaking = widget.session.speakingText == widget.speech;
        return V3Pressable(
          label: 'Hear ${widget.speech}',
          onTap: _tap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CupertinoActivityIndicator(radius: 7),
                      )
                    : Icon(
                        speaking
                            ? CupertinoIcons.speaker_3_fill
                            : CupertinoIcons.speaker_2_fill,
                        size: 16,
                        color: DesignTokens.primary,
                      ),
                const SizedBox(width: 6),
                Flexible(child: Text(widget.shown, style: widget.style)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class V3Speaker extends StatefulWidget {
  const V3Speaker({
    super.key,
    required this.text,
    required this.session,
    this.size = 48,
    this.oneShot = false,
    this.hidden = false,
    this.onPlayed,
    this.asset,
  });

  final String text;

  /// A bundled recording to play instead of a made clip.
  final String? asset;
  final V3MarieSession session;
  final double size;
  final bool oneShot;
  final bool hidden;
  final VoidCallback? onPlayed;

  @override
  State<V3Speaker> createState() => _V3SpeakerState();
}

class _V3SpeakerState extends State<V3Speaker> {
  var _played = false;
  var _busy = false;

  Future<void> _tap() async {
    if (_busy || (widget.oneShot && _played)) return;
    setState(() => _busy = true);
    final reached = await widget.session.speak(
      context,
      widget.text,
      reveal: !widget.hidden,
      asset: widget.asset,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (reached) _played = true;
    });
    if (reached) {
      widget.onPlayed?.call();
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not play the audio. Check your connection and tap the speaker to try again.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.oneShot && _played;
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final speaking = widget.session.speakingText == widget.text;
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
              child: _busy
                  ? SizedBox.square(
                      dimension: widget.size * 0.4,
                      child: const CupertinoActivityIndicator(),
                    )
                  : Icon(
                      speaking
                          ? CupertinoIcons.speaker_3_fill
                          : CupertinoIcons.speaker_2_fill,
                      color: DesignTokens.primary,
                      size: widget.size * 0.44,
                    ),
            ),
          ),
        );
      },
    );
  }
}
