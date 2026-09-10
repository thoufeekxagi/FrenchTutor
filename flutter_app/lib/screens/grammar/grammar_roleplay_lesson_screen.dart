import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../models/grammar_course.dart';
import '../../models/grammar_course_session_result.dart';
import '../../providers/database_provider.dart';
import '../../prompts/live_prompts.dart';
import '../../services/inline_call_controller.dart';
import '../../widgets/ai_voice_disclosure.dart';
import '../../widgets/grammar_live_audio_button.dart';
import '../../widgets/inline_call_bar.dart';
import '../../widgets/web/web_constrained_view.dart';

/// A grammar roleplay is one short live scene, not a multiple-choice deck.
/// Each turn keeps the same target grammar in a real exchange, and the app
/// owns turn boundaries and progression while the tutor stays in character.
class GrammarRoleplayLessonScreen extends ConsumerStatefulWidget {
  const GrammarRoleplayLessonScreen({
    super.key,
    required this.session,
    this.warmupSessions = const [],
  });

  final GrammarCourseSession session;
  final List<GrammarCourseSession> warmupSessions;

  @override
  ConsumerState<GrammarRoleplayLessonScreen> createState() =>
      _GrammarRoleplayLessonScreenState();
}

class _GrammarRoleplayLessonScreenState
    extends ConsumerState<GrammarRoleplayLessonScreen>
    with WidgetsBindingObserver {
  late final InlineCallController _call;
  int _index = 0;
  bool _recording = false;
  bool _checking = false;
  bool _turnClosing = false;
  bool _submitted = false;
  bool? _matched;
  String _heard = '';
  String? _error;
  int _correctCount = 0;
  int _attemptedCount = 0;
  Timer? _checkingTimeout;

  GrammarCourseStep get _step => widget.session.steps[_index];
  bool get _isLastTurn => _index == widget.session.steps.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _call = InlineCallController(
      sessionType: LiveSessionType.grammarStage,
      lessonContext: _lessonContext,
      learningStoreForProfile: ref.read(learningStoreProvider),
      openingPrompt: _openingPrompt,
      onUserTranscript: _onTranscript,
      onTurnComplete: _onTurnComplete,
      onChanged: () {
        if (mounted) setState(() {});
      },
      manualLearnerTurns: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_autoConnectMarie());
    });
  }

  Future<void> _autoConnectMarie() async {
    if (!mounted || !await AiVoiceDisclosure.isAccepted()) return;
    if (!mounted) return;
    await _call.start(context, sendOpeningPrompt: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _call.handleAppLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkingTimeout?.cancel();
    _call.dispose();
    super.dispose();
  }

  String get _openingPrompt =>
      '''
(App instruction, not the learner: start the current grammar roleplay turn.)
Say one short English coaching sentence, then say this exact French partner line
once, naturally and clearly: "${_step.partnerFrench}". Give its short English
meaning, then stop and wait for the learner's reply. Play only this current turn.
Do not offer answer choices, invent another sentence, or move to a later turn.
''';

  String _lessonContext() =>
      '''
GRAMMAR ROLEPLAY SESSION: ${widget.session.title}
LEVEL: ${widget.session.level}
TENSE: ${widget.session.tense}
GRAMMAR FOCUS: ${widget.session.grammarFocus}
MODE: ROLEPLAY

CURRENT SCREEN SNAPSHOT — replace every previous snapshot:
TURN: ${_index + 1} of ${widget.session.steps.length}
CURRENT PARTNER FRENCH: ${_step.partnerFrench}
CURRENT PARTNER ENGLISH: ${_step.partnerEnglish}
VISIBLE LEARNER GOAL: ${_step.prompt}
VISIBLE ENGLISH GOAL: ${_matched == true ? _step.promptEnglish : '(context withheld until the learner matches the target)'}
LEARNER STATE: ${_recording
          ? 'recording'
          : _checking
          ? 'checking'
          : _matched == true
          ? 'matched'
          : _matched == false
          ? 'try again'
          : 'ready'}
LATEST LEARNER TRANSCRIPT: ${_heard.trim().isEmpty ? '(none)' : _heard.trim()}

STRICT ROLEPLAY SCOPE:
- Coach only this exact current turn and grammar target.
- Stay in character as the partner and respond to the learner's current reply.
- Before the app reports a match, never say, spell, translate, paraphrase, or
  complete the learner's hidden target. Do not use the English goal to supply
  the missing form. The app owns answer checking.
- Never reveal or offer the private answer key as a list of choices.
- Never introduce a new sentence, new vocabulary, future turn, or unrelated example.
- If explaining past, present, or future, transform only the current target while
  preserving its meaning and vocabulary, then return to this turn.
- The app owns recording, grading, progression, and completion. Never advance it.
''';

  Future<void> _startRecording() async {
    if (_submitted || _checking || _recording) return;
    if (!_call.isLive) {
      setState(() {
        _error = 'Turn on the tutor with the phone button before replying.';
      });
      return;
    }
    if (!_call.isReadyForLearnerTurn) {
      setState(() {
        _error = _call.reconnecting
            ? 'The tutor is reconnecting. Try again in a moment.'
            : 'The tutor is still connecting. Try again in a moment.';
      });
      return;
    }
    setState(() {
      _recording = true;
      _turnClosing = false;
      _heard = '';
      _matched = null;
      _error = null;
    });
    final started = await _call.startLearnerTurn();
    if (!started && mounted) {
      setState(() {
        _recording = false;
        _error = 'The tutor is not ready to record yet. Try again in a moment.';
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    setState(() {
      _recording = false;
      _checking = true;
      _turnClosing = true;
      _error = null;
    });
    await _call.endLearnerTurn();
    _checkingTimeout?.cancel();
    _checkingTimeout = Timer(const Duration(seconds: 20), () {
      if (!mounted || !_turnClosing || !_checking || _submitted) return;
      _turnClosing = false;
      setState(() {
        _checking = false;
        _submitted = true;
        _matched = false;
        _error =
            'No French speech was transcribed. Please try this turn again.';
      });
    });
    if (mounted && _turnClosing && _heard.trim().isNotEmpty) {
      _finishAttempt(_heard);
    }
  }

  void _onTranscript(String transcript) {
    if (!mounted || (!_recording && !_turnClosing)) return;
    final clean = transcript.trim();
    if (clean.isEmpty) return;
    final combined = _heard.trim().isEmpty ? clean : '${_heard.trim()} $clean';
    setState(() => _heard = combined);
    if (_turnClosing) _finishAttempt(combined);
  }

  void _onTurnComplete() {
    if (!mounted || !_turnClosing || _heard.trim().isEmpty) return;
    _finishAttempt(_heard);
  }

  void _finishAttempt(String transcript) {
    if (!mounted || _submitted) return;
    final clean = transcript.trim();
    if (clean.isEmpty) return;
    _checkingTimeout?.cancel();
    _checkingTimeout = null;
    _turnClosing = false;
    final matched = _matchesTarget(clean, _step.answer);
    setState(() {
      _submitted = true;
      _checking = false;
      _heard = clean;
      _matched = matched;
      _attemptedCount++;
      if (matched) _correctCount++;
    });
    _call.updateLessonContext();
    _call.promptTutor(
      matched
          ? 'APP FEEDBACK: The learner matched this turn. Say one short '
                'encouraging English sentence explaining that the reply fits the '
                '${widget.session.tense.toLowerCase()} grammar focus, then wait.'
          : 'APP FEEDBACK: The learner did not match this turn. Give one short '
                'English clue about the subject and grammar focus without saying '
                'the answer, then wait.',
    );
  }

  void _retry() {
    _checkingTimeout?.cancel();
    _checkingTimeout = null;
    setState(() {
      _recording = false;
      _checking = false;
      _turnClosing = false;
      _submitted = false;
      _matched = null;
      _heard = '';
      _error = null;
    });
    _call.updateLessonContext();
  }

  void _nextTurn() {
    if (!_submitted || _matched != true) return;
    final store = ref.read(learningStoreProvider);
    store.setLessonStatus(
      '${widget.session.progressId}_step_$_index',
      'completed',
      score: 1,
    );
    if (_isLastTurn) {
      store.setLessonStatus(widget.session.progressId, 'completed', score: 1);
      if (!mounted) return;
      Navigator.of(context).pop(
        GrammarCourseSessionResult(
          sessionId: widget.session.id,
          correct: _correctCount,
          attempted: _attemptedCount,
          completed: true,
        ),
      );
      return;
    }
    setState(() {
      _index++;
      _recording = false;
      _checking = false;
      _turnClosing = false;
      _submitted = false;
      _matched = null;
      _heard = '';
      _error = null;
    });
    _checkingTimeout?.cancel();
    _checkingTimeout = null;
    _call.updateLessonContext();
    _call.promptTutor('''
The app moved to the next roleplay turn. Say only this exact current partner
line once, give its short meaning, then wait: "${_step.partnerFrench}".
''');
  }

  bool _matchesTarget(String heard, String target) {
    final left = _fold(heard);
    final right = _fold(target);
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right || left.contains(right) || right.contains(left)) {
      return true;
    }
    final heardWords = left.split(' ').where((word) => word.isNotEmpty).toSet();
    final targetWords = right
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toSet();
    if (targetWords.isEmpty) return false;
    final overlap = heardWords.intersection(targetWords).length;
    return overlap / targetWords.length >= 0.72;
  }

  String _fold(String value) {
    const accents = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ÿ': 'y',
    };
    var folded = value.toLowerCase().trim();
    accents.forEach((from, to) => folded = folded.replaceAll(from, to));
    return folded
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DesignTokens.canvas,
    body: SafeArea(
      child: WebConstrainedView(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  _metaRow(),
                  const SizedBox(height: 9),
                  _titleRow(),
                  const SizedBox(height: 6),
                  Text(
                    _step.promptEnglish,
                    style: DesignTokens.body(
                      15,
                    ).copyWith(color: DesignTokens.muted, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  _partnerSurface(),
                  const SizedBox(height: 12),
                  _goalSurface(),
                  const SizedBox(height: 12),
                  _learnerSurface(),
                  if (_call.isLive || _call.error != null) ...[
                    const SizedBox(height: 12),
                    InlineCallStatusCard(
                      controller: _call,
                      listeningLabel: _recording
                          ? 'Listening to your reply.'
                          : 'Tutor ready for your reply.',
                      compact: true,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _messageSurface(_error!),
                  ],
                ],
              ),
            ),
            _bottomAction(),
          ],
        ),
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
    child: Column(
      children: [
        SizedBox(
          height: 54,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Close grammar roleplay',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(CupertinoIcons.xmark),
              ),
              Expanded(
                child: Text(
                  widget.session.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.display(18),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  widget.session.level,
                  textAlign: TextAlign.end,
                  style: DesignTokens.label(12),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              minHeight: 5,
              value:
                  (_index + (_matched == true ? 1 : 0)) /
                  widget.session.steps.length,
              backgroundColor: DesignTokens.hairline,
              valueColor: AlwaysStoppedAnimation(DesignTokens.primary),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _metaRow() => Row(
    children: [
      Expanded(
        child: Text(
          'ROLEPLAY · ${widget.session.tense.toUpperCase()}',
          style: DesignTokens.label(
            12,
            weight: FontWeight.w800,
          ).copyWith(color: DesignTokens.primary, letterSpacing: 1.1),
        ),
      ),
      Text(
        'TURN ${_index + 1} OF ${widget.session.steps.length}',
        style: DesignTokens.label(10).copyWith(color: DesignTokens.muted),
      ),
    ],
  );

  Widget _titleRow() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text('Reply in the scene', style: DesignTokens.display(30)),
      ),
      const SizedBox(width: 8),
      InlineCallActions(controller: _call, accentColor: DesignTokens.primary),
    ],
  );

  Widget _surface({required Widget child, Color? color, bool focus = false}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color ?? DesignTokens.surface,
          borderRadius: BorderRadius.circular(21),
          border: Border.all(
            color: focus
                ? DesignTokens.primary.withValues(alpha: 0.65)
                : DesignTokens.hairline,
          ),
        ),
        child: child,
      );

  Widget _partnerSurface() => _surface(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TUTOR',
                style: DesignTokens.label(
                  10,
                  weight: FontWeight.w800,
                ).copyWith(color: DesignTokens.primary, letterSpacing: 1.1),
              ),
              const SizedBox(height: 8),
              Text(_step.partnerFrench!, style: DesignTokens.display(21)),
              const SizedBox(height: 6),
              Text(
                _step.partnerEnglish!,
                style: DesignTokens.body(
                  14,
                ).copyWith(color: DesignTokens.muted),
              ),
            ],
          ),
        ),
        GrammarLiveAudioButton(
          controller: _call,
          text: _step.partnerFrench!,
          size: 42,
        ),
      ],
    ),
  );

  Widget _goalSurface() => _surface(
    color: DesignTokens.primarySoft,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.track_changes_rounded, color: DesignTokens.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _step.prompt,
            style: DesignTokens.body(14, weight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _learnerSurface() => _surface(
    focus: _recording || _matched == true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _matched == true
                    ? 'MATCHED'
                    : _matched == false
                    ? 'TRY AGAIN'
                    : _recording
                    ? 'SPEAK NOW'
                    : _checking
                    ? 'CHECKING'
                    : 'YOUR REPLY',
                style: DesignTokens.label(
                  10,
                  weight: FontWeight.w800,
                ).copyWith(color: DesignTokens.primary, letterSpacing: 1.1),
              ),
            ),
            if (_matched == true)
              Icon(Icons.check_circle_rounded, color: DesignTokens.success),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          _heard.isEmpty
              ? (_recording
                    ? 'Say the reply in French, then tap stop.'
                    : 'Turn on the tutor, then record your reply.')
              : _heard,
          style: DesignTokens.display(20).copyWith(
            color: _heard.isEmpty ? DesignTokens.muted : DesignTokens.ink,
          ),
        ),
        if (_matched == true) ...[
          const SizedBox(height: 8),
          Text(
            'Good. Keep the same meaning and continue the scene.',
            style: DesignTokens.body(13).copyWith(color: DesignTokens.muted),
          ),
        ] else if (_matched == false) ...[
          const SizedBox(height: 8),
          Text(
            'Try the same reply again. The tutor will keep this turn in view.',
            style: DesignTokens.body(13).copyWith(color: DesignTokens.muted),
          ),
        ],
      ],
    ),
  );

  Widget _messageSurface(String message) => _surface(
    color: DesignTokens.primarySoft,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: DesignTokens.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: DesignTokens.body(13, weight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _bottomAction() {
    final canRecord = _call.isReadyForLearnerTurn;
    final String label;
    if (_matched == true) {
      label = _isLastTurn ? 'Finish scene' : 'Next turn';
    } else if (_matched == false) {
      label = 'Try again';
    } else if (_recording) {
      label = 'Stop reply';
    } else if (_checking) {
      label = 'Checking reply…';
    } else {
      label = canRecord ? 'Record reply' : 'Turn on tutor to reply';
    }
    final enabled =
        _matched == true ||
        _matched == false ||
        _recording ||
        (!_checking && canRecord);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: BoxDecoration(
        color: DesignTokens.canvas,
        border: Border(top: BorderSide(color: DesignTokens.hairline)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: enabled
              ? () {
                  if (_matched == true) {
                    _nextTurn();
                  } else if (_matched == false) {
                    _retry();
                  } else if (_recording) {
                    unawaited(_stopRecording());
                  } else {
                    unawaited(_startRecording());
                  }
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: DesignTokens.primary,
            foregroundColor: DesignTokens.onPrimary,
            disabledBackgroundColor: DesignTokens.hairline,
            elevation: 0,
            minimumSize: const Size(0, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
          child: Text(
            label,
            style: DesignTokens.body(15, weight: FontWeight.w800).copyWith(
              color: enabled ? DesignTokens.onPrimary : DesignTokens.muted,
            ),
          ),
        ),
      ),
    );
  }
}
