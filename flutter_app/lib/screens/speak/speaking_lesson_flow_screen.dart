import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/speaking_course.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../providers/tutor_helper_provider.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/tutor_helper_settings.dart';

/// The three controlled stages used by a Guided Speaking lesson.
enum SpeakingGuidedStage { wordChoice, sentenceBuilder, speak }

/// One fixed phrase or micro-exercise in the controlled Speak-style lesson.
///
/// The French line is the source of truth. Guided lessons can teach it in
/// order: identify one missing word, rebuild the sentence, then say it aloud.
/// Free Talk and Roleplay keep the default [SpeakingGuidedStage.speak] stage.
class SpeakingPhraseStep {
  const SpeakingPhraseStep({
    required this.french,
    required this.english,
    this.partnerFrench,
    this.partnerEnglish,
    this.tip = '',
    this.openResponse = false,
    this.stage = SpeakingGuidedStage.speak,
    this.blankWord,
    this.wordChoices = const [],
    this.sentenceTokens = const [],
  });

  final String french;
  final String english;
  final String? partnerFrench;
  final String? partnerEnglish;
  final String tip;
  final bool openResponse;
  final SpeakingGuidedStage stage;
  final String? blankWord;
  final List<String> wordChoices;
  final List<String> sentenceTokens;
}

enum _SpeakingStepState { ready, recording, checking, success, retry }

class _SpeakingChatTurn {
  const _SpeakingChatTurn({
    required this.index,
    required this.partnerFrench,
    required this.partnerEnglish,
    required this.learnerFrench,
    required this.learnerEnglish,
    required this.heard,
  });

  final int index;
  final String partnerFrench;
  final String? partnerEnglish;
  final String learnerFrench;
  final String learnerEnglish;
  final String heard;
}

/// Shared controlled speaking flow used by the course lesson and quick drill.
///
/// This is intentionally a single route. The reference changes state inside
/// the same lesson surface instead of pushing a separate random result page.
class SpeakingLessonFlowScreen extends ConsumerStatefulWidget {
  const SpeakingLessonFlowScreen({
    super.key,
    required this.title,
    required this.level,
    required this.steps,
    this.topic,
    this.contentKey,
    this.tutor,
  });

  final String title;
  final String level;
  final List<SpeakingPhraseStep> steps;
  final String? topic;
  final String? contentKey;

  /// Optional pin for a deliberate course voice; otherwise use the tutor the
  /// learner selected in Settings for both lesson audio and live coaching.
  final TutorPersona? tutor;

  @override
  ConsumerState<SpeakingLessonFlowScreen> createState() =>
      _SpeakingLessonFlowScreenState();
}

class _SpeakingLessonFlowScreenState
    extends ConsumerState<SpeakingLessonFlowScreen>
    with WidgetsBindingObserver {
  final Stopwatch _sessionClock = Stopwatch();
  late final InlineCallController _murray;
  int _index = 0;
  int _successful = 0;
  bool _playing = false;
  bool _showMeaning = true;
  String _heard = '';
  String? _error;
  _SpeakingStepState _state = _SpeakingStepState.ready;
  String? _selectedWord;
  final List<int> _selectedSentenceTokens = [];
  final List<_SpeakingChatTurn> _chatHistory = [];
  final Set<String> _revealedTranslations = {};
  bool _restartMurrayAfterRecording = false;

  SpeakingPhraseStep get _step => widget.steps[_index];
  TutorPersona get _tutor => widget.tutor ?? ActiveTutor.current;
  bool get _isFreeTalk => widget.steps.any((step) => step.openResponse);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _murray = InlineCallController(
      sessionType: _murraySessionType,
      lessonContext: () => _murrayContext,
      learningStoreForProfile: ref.read(learningStoreProvider),
      openingPrompt:
          '(Note from the app: the learner opened tutor help inside the current '
          'speaking lesson. Give one short, warm sentence offering help with '
          'the current phrase only, then wait. Never leave the lesson context.)',
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _sessionClock.start();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final helperEnabled = ref
          .read(tutorHelperSettingsProvider)
          .isEnabled(TutorHelperSurface.speaking);
      if (_isFreeTalk && helperEnabled) {
        await _startMurray(sendOpeningPrompt: true);
      } else {
        await _playCurrentPrompt();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _murray.dispose();
    unawaited(LessonSpeechService.shared.deactivate());
    _sessionClock.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _murray.handleAppLifecycle(state);
  }

  LiveSessionType get _murraySessionType =>
      widget.steps.any((step) => step.openResponse)
      ? LiveSessionType.freeTalk
      : LiveSessionType.speakingGuided;

  String get _murrayContext {
    final step = _step;
    final partner = step.partnerFrench;
    return '''
SPEAKING LESSON: "${widget.title}".
MODE: ${_murraySessionType == LiveSessionType.freeTalk ? 'FREE TALK' : 'GUIDED CONVERSATION'}.
CEFR LEVEL: ${widget.level}.
CURRENT STEP: ${_index + 1} of ${widget.steps.length}.
CURRENT FRENCH TARGET: "${step.french}".
CURRENT ENGLISH MEANING: "${step.english}".
${partner == null ? '' : 'CURRENT PARTNER LINE: "$partner" = "${step.partnerEnglish ?? ''}".'}
${step.tip.trim().isEmpty ? '' : 'CURRENT PRONUNCIATION TIP: "${step.tip}".'}
LEARNER STATE: ${_state.name}.
${_heard.trim().isEmpty ? '' : 'LATEST TRANSCRIPT: "$_heard".'}

BOUNDARY: You are the learner's in-lesson coach. Explain, model, or give one
short hint about the current target only. Do not create a new lesson, switch
topics, introduce advanced vocabulary, reveal future lines, or control the
app's next button. The app owns recording, matching, retries, and progression.
For A1/A2, use short English coaching and clear French examples. Wait after
one helpful response so the learner can practise.
''';
  }

  Future<void> _setMurrayEnabled(bool enabled) async {
    if (!enabled) {
      await _murray.end();
    } else if (_isFreeTalk && !_murray.isLive) {
      await _startMurray(sendOpeningPrompt: true);
    }
    if (!mounted) return;
    await ref
        .read(tutorHelperSettingsProvider)
        .setEnabled(TutorHelperSurface.speaking, enabled);
    if (mounted) setState(() {});
  }

  Future<void> _startMurray({required bool sendOpeningPrompt}) async {
    if (!_isFreeTalk || _murray.isLive || !mounted) return;
    await _murray.start(context, sendOpeningPrompt: sendOpeningPrompt);
    if (!mounted || _murray.error == null) return;
    setState(() => _error = _murray.error);
  }

  Future<void> _playPhrase() async {
    if (_playing || !mounted) return;
    setState(() {
      _playing = true;
      _error = null;
    });
    await LessonSpeechService.shared.speak(
      items: [
        SpeechItem(
          text: _step.french,
          language: 'fr-FR',
          contentItemId: widget.contentKey,
          voiceName: _tutor.voiceName,
        ),
      ],
      rate: 0.34,
      onPlaybackReady: () {
        if (mounted) setState(() => _playing = false);
      },
      onFinished: () {
        if (mounted) setState(() => _playing = false);
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _playing = false;
            _error = 'Audio could not be played: $error';
          });
        }
      },
    );
    if (mounted && _playing) setState(() => _playing = false);
  }

  Future<void> _startRecording() async {
    if (_isGuidedExercise) return;
    if (_state == _SpeakingStepState.checking ||
        _state == _SpeakingStepState.recording) {
      return;
    }
    if (_state == _SpeakingStepState.success) return;
    if (_isFreeTalk && _murray.isLive) {
      _restartMurrayAfterRecording = true;
      await _murray.end();
    }
    setState(() {
      _state = _SpeakingStepState.recording;
      _heard = '';
      _error = null;
    });
    await LessonSpeechService.shared.startListening(
      locale: 'fr-FR',
      onPartial: (_) {},
      onFinal: _finishRecording,
    );
  }

  Future<void> _finishRecording(String transcript) async {
    if (!mounted) return;
    setState(() {
      _state = _SpeakingStepState.checking;
      _heard = transcript.trim();
    });
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    final match = _step.openResponse
        ? _fold(_heard).split(' ').where((word) => word.isNotEmpty).length >= 2
        : _matchesTarget(_heard, _step.french);
    setState(() {
      _state = match ? _SpeakingStepState.success : _SpeakingStepState.retry;
      if (_heard.isEmpty) {
        _error =
            'No French speech was transcribed. Please try this line again.';
      }
      if (match) _successful++;
    });
    if (_restartMurrayAfterRecording) {
      _restartMurrayAfterRecording = false;
      unawaited(_startMurray(sendOpeningPrompt: false));
    }
  }

  Future<void> _stopRecording() async {
    if (_state != _SpeakingStepState.recording) return;
    await LessonSpeechService.shared.stopListening();
  }

  bool get _isGuidedExercise =>
      !_isFreeTalk && _step.stage != SpeakingGuidedStage.speak;

  void _chooseWord(String choice) {
    if (_state == _SpeakingStepState.success ||
        _state == _SpeakingStepState.checking) {
      return;
    }
    final correct = _fold(choice) == _fold(_step.blankWord ?? '');
    setState(() {
      _selectedWord = choice;
      _state = correct ? _SpeakingStepState.success : _SpeakingStepState.retry;
      _error = correct ? null : 'Try the word that completes the sentence.';
      if (correct) _successful++;
    });
  }

  void _chooseSentenceToken(int tokenIndex) {
    if (_state == _SpeakingStepState.success ||
        _state == _SpeakingStepState.checking ||
        _selectedSentenceTokens.contains(tokenIndex)) {
      return;
    }
    var selection = [..._selectedSentenceTokens];
    if (_state == _SpeakingStepState.retry) selection = [];
    selection.add(tokenIndex);
    final complete = selection.length == _step.sentenceTokens.length;
    final correct =
        complete &&
        selection.asMap().entries.every((entry) => entry.key == entry.value);
    setState(() {
      _selectedSentenceTokens
        ..clear()
        ..addAll(selection);
      if (complete) {
        _state = correct
            ? _SpeakingStepState.success
            : _SpeakingStepState.retry;
        _error = correct ? null : 'Try the sentence again in the right order.';
        if (correct) _successful++;
      } else {
        _state = _SpeakingStepState.ready;
        _error = null;
      }
    });
  }

  void _resetGuidedExercise() {
    setState(() {
      _selectedWord = null;
      _selectedSentenceTokens.clear();
      _state = _SpeakingStepState.ready;
      _error = null;
    });
  }

  void _next() {
    if (_state != _SpeakingStepState.success) return;
    if (_index + 1 >= widget.steps.length) {
      _finishLesson();
      return;
    }
    if (_isFreeTalk) {
      _chatHistory.add(
        _SpeakingChatTurn(
          index: _index,
          partnerFrench: _step.partnerFrench ?? '',
          partnerEnglish: _step.partnerEnglish,
          learnerFrench: _step.french,
          learnerEnglish: _step.english,
          heard: _heard,
        ),
      );
    }
    setState(() {
      _index++;
      _state = _SpeakingStepState.ready;
      _heard = '';
      _error = null;
      _selectedWord = null;
      _selectedSentenceTokens.clear();
    });
    unawaited(_playCurrentPrompt());
  }

  Future<void> _playCurrentPrompt() async {
    final partner = _step.partnerFrench;
    if (_isFreeTalk && _murray.isLive && partner != null) {
      _murray.promptTutor(
        'For the current Free Talk beat, say this exact French prompt aloud once, then wait for the learner: "$partner". Do not add another question or change the topic.',
      );
      return;
    }
    if (partner == null) {
      await _playPhrase();
    } else {
      await _playPartnerLine();
    }
  }

  void _finishLesson() {
    _sessionClock.stop();
    final seconds = _sessionClock.elapsed.inSeconds;
    Navigator.of(context).pop(
      SpeakingResult(
        connected: true,
        durationSeconds: seconds,
        learnerUtteranceCount: _successful,
        endedReason: _isFreeTalk ? 'free_talk_complete' : 'guided_complete',
      ),
    );
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
  Widget build(BuildContext context) {
    final murrayEnabled = ref
        .watch(tutorHelperSettingsProvider)
        .isEnabled(TutorHelperSurface.speaking);
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (_isFreeTalk) _murrayToggleCard(murrayEnabled),
                  const SizedBox(height: 14),
                  _progressBar(),
                  const SizedBox(height: 24),
                  _lessonHeading(),
                  const SizedBox(height: 18),
                  _phraseCard(),
                  const SizedBox(height: 16),
                  _coachCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _messageCard(_error!, DesignTokens.danger),
                  ],
                ],
              ),
            ),
            _bottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close lesson',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, color: DesignTokens.nightText),
          ),
          Expanded(
            child: Text(
              widget.level.toUpperCase(),
              textAlign: TextAlign.center,
              style: _label(11).copyWith(letterSpacing: 1.4),
            ),
          ),
          IconButton(
            tooltip: 'Save lesson',
            onPressed: () {},
            icon: Icon(
              Icons.bookmark_border_rounded,
              color: DesignTokens.nightText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressBar() {
    final progress =
        (_index + (_state == _SpeakingStepState.success ? 1 : 0)) /
        widget.steps.length;
    return Column(
      children: [
        Row(
          children: [
            Text('${_index + 1} of ${widget.steps.length}', style: _label(12)),
            const Spacer(),
            Text(
              '${(_successful / widget.steps.length * 100).round()}%',
              style: _label(12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: DesignTokens.nightHairline,
            valueColor: AlwaysStoppedAnimation(DesignTokens.nightAccent),
          ),
        ),
      ],
    );
  }

  Widget _lessonHeading() {
    final heading = _isFreeTalk
        ? 'FREE TALK'
        : _step.partnerFrench == null
        ? 'GUIDED SPEAKING'
        : 'ROLEPLAY';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: _label(11).copyWith(letterSpacing: 1.5)),
        const SizedBox(height: 6),
        Text(widget.title, style: _display(28)),
        const SizedBox(height: 5),
        Text(
          widget.topic ?? 'Hear it, repeat it, use it.',
          style: _body(14).copyWith(color: DesignTokens.nightMuted),
        ),
      ],
    );
  }

  Widget _murrayToggleCard(bool enabled) {
    final tutor = ActiveTutor.current;
    final status = _murray.isLive
        ? 'Live · pauses while you answer'
        : enabled
        ? 'On by default · starts with this lesson'
        : 'Off · practise without in-lesson coaching';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: DesignTokens.nightAccentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.support_agent_rounded,
              size: 20,
              color: enabled
                  ? DesignTokens.nightAccent
                  : DesignTokens.nightMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tutor.displayName} help',
                  style: _body(13, weight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _body(11).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: _setMurrayEnabled,
            activeThumbColor: DesignTokens.nightAccent,
          ),
        ],
      ),
    );
  }

  Widget _freeTalkChatCard() {
    return Container(
      height: 380,
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
          children: [
            for (final turn in _chatHistory) ...[
              _chatBubble(
                keyName: '${turn.index}:partner',
                label: 'MARIE',
                french: turn.partnerFrench,
                english: turn.partnerEnglish,
                tutor: true,
              ),
              _chatBubble(
                keyName: '${turn.index}:learner',
                label: 'YOU',
                french: turn.heard.isEmpty ? turn.learnerFrench : turn.heard,
                english: turn.learnerEnglish,
                tutor: false,
                success: true,
              ),
            ],
            if (_step.partnerFrench?.trim().isNotEmpty ?? false)
              _chatBubble(
                keyName: '$_index:partner',
                label: 'MARIE',
                french: _step.partnerFrench!,
                english: _step.partnerEnglish,
                tutor: true,
                onPlay: _playing ? null : _playPartnerLine,
              ),
            const SizedBox(height: 10),
            _currentLearnerBubble(),
          ],
        ),
      ),
    );
  }

  Widget _chatBubble({
    required String keyName,
    required String label,
    required String french,
    required String? english,
    required bool tutor,
    bool success = false,
    VoidCallback? onPlay,
  }) {
    final translationVisible = _revealedTranslations.contains(keyName);
    final borderColor = success
        ? DesignTokens.success.withValues(alpha: 0.75)
        : DesignTokens.nightHairline;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: tutor
            ? DesignTokens.nightSurfaceRaised
            : DesignTokens.nightAccentSoft.withValues(alpha: 0.42),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(tutor ? 6 : 18),
          topRight: Radius.circular(tutor ? 18 : 6),
          bottomLeft: const Radius.circular(18),
          bottomRight: const Radius.circular(18),
        ),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: _label(10).copyWith(
                    color: tutor
                        ? DesignTokens.nightAccent
                        : DesignTokens.nightMuted,
                  ),
                ),
                const SizedBox(height: 5),
                Text(french, style: _body(17, weight: FontWeight.w700)),
                if (translationVisible && (english?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 5),
                  Text(
                    english!,
                    style: _body(13).copyWith(color: DesignTokens.nightMuted),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: tutor ? 'Play Marie’s line' : 'Play phrase',
            onPressed: onPlay,
            icon: Icon(
              Icons.volume_up_outlined,
              color: onPlay == null
                  ? DesignTokens.nightMuted
                  : DesignTokens.nightText,
              size: 21,
            ),
          ),
          IconButton(
            tooltip: translationVisible
                ? 'Hide translation'
                : 'Show translation',
            onPressed: english?.trim().isEmpty ?? true
                ? null
                : () => setState(() {
                    if (translationVisible) {
                      _revealedTranslations.remove(keyName);
                    } else {
                      _revealedTranslations.add(keyName);
                    }
                  }),
            icon: Icon(
              translationVisible
                  ? Icons.translate_rounded
                  : Icons.translate_outlined,
              color: english?.trim().isEmpty ?? true
                  ? DesignTokens.nightMuted
                  : DesignTokens.nightAccent,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentLearnerBubble() {
    final success = _state == _SpeakingStepState.success;
    final retry = _state == _SpeakingStepState.retry;
    final translationVisible = _revealedTranslations.contains(
      '$_index:learner',
    );
    final stateLabel = success
        ? 'MATCHED'
        : retry
        ? 'TRY AGAIN'
        : _state == _SpeakingStepState.recording
        ? 'LISTENING'
        : 'SPEAK NOW';
    final stateColor = success
        ? DesignTokens.success
        : retry
        ? DesignTokens.danger
        : DesignTokens.nightAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
      decoration: BoxDecoration(
        color: success
            ? DesignTokens.success.withValues(alpha: 0.12)
            : DesignTokens.nightSurfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: success || retry ? stateColor : DesignTokens.nightHairline,
          width: success || retry ? 1.4 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stateLabel, style: _label(10).copyWith(color: stateColor)),
                const SizedBox(height: 9),
                Text(_step.french, style: _display(27).copyWith(height: 1.12)),
                if (translationVisible) ...[
                  const SizedBox(height: 6),
                  Text(
                    _step.english,
                    style: _body(13).copyWith(color: DesignTokens.nightMuted),
                  ),
                ],
                if (_heard.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('I HEARD', style: _label(10)),
                  const SizedBox(height: 4),
                  Text(
                    _heard,
                    style: _body(14, weight: FontWeight.w700).copyWith(
                      color: success
                          ? DesignTokens.success
                          : DesignTokens.nightText,
                    ),
                  ),
                ],
                if (_step.tip.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _step.tip,
                    style: _body(12).copyWith(color: DesignTokens.nightMuted),
                  ),
                ],
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                tooltip: 'Play phrase',
                onPressed: _playing ? null : _playPhrase,
                icon: Icon(
                  _playing
                      ? Icons.graphic_eq_rounded
                      : Icons.volume_up_outlined,
                  color: DesignTokens.nightText,
                  size: 21,
                ),
              ),
              IconButton(
                tooltip: translationVisible
                    ? 'Hide translation'
                    : 'Show translation',
                onPressed: () => setState(() {
                  if (translationVisible) {
                    _revealedTranslations.remove('$_index:learner');
                  } else {
                    _revealedTranslations.add('$_index:learner');
                  }
                }),
                icon: Icon(
                  translationVisible
                      ? Icons.translate_rounded
                      : Icons.translate_outlined,
                  color: DesignTokens.nightAccent,
                  size: 21,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _phraseCard() {
    if (_isFreeTalk) return _freeTalkChatCard();
    if (_step.stage == SpeakingGuidedStage.wordChoice) {
      return _wordChoiceCard();
    }
    if (_step.stage == SpeakingGuidedStage.sentenceBuilder) {
      return _sentenceBuilderCard();
    }
    final success = _state == _SpeakingStepState.success;
    final retry = _state == _SpeakingStepState.retry;
    final border = success
        ? DesignTokens.success
        : retry
        ? DesignTokens.danger
        : DesignTokens.nightHairline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_step.partnerFrench != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 310),
              padding: const EdgeInsets.fromLTRB(15, 13, 10, 13),
              decoration: BoxDecoration(
                color: DesignTokens.nightSurfaceRaised,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(color: DesignTokens.nightHairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MARIE',
                          style: _label(
                            10,
                          ).copyWith(color: DesignTokens.nightAccent),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _step.partnerFrench!,
                          style: _body(16, weight: FontWeight.w700),
                        ),
                        if (_showMeaning &&
                            (_step.partnerEnglish?.isNotEmpty ?? false)) ...[
                          const SizedBox(height: 4),
                          Text(
                            _step.partnerEnglish!,
                            style: _body(
                              12,
                            ).copyWith(color: DesignTokens.nightMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Play Marie’s line',
                    onPressed: _playing ? null : _playPartnerLine,
                    icon: Icon(
                      Icons.volume_up_outlined,
                      color: DesignTokens.nightText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: success
                ? DesignTokens.success.withValues(alpha: 0.14)
                : DesignTokens.nightSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: border,
              width: success || retry ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    success
                        ? Icons.check_circle_rounded
                        : Icons.format_quote_rounded,
                    color: success
                        ? DesignTokens.success
                        : DesignTokens.nightAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    success
                        ? 'Nice work'
                        : retry
                        ? 'Try it again'
                        : 'Speak now',
                    style: _body(13, weight: FontWeight.w800).copyWith(
                      color: success
                          ? DesignTokens.success
                          : retry
                          ? DesignTokens.danger
                          : DesignTokens.nightAccent,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Play phrase',
                    onPressed: _playing ? null : _playPhrase,
                    icon: Icon(
                      _playing
                          ? Icons.graphic_eq_rounded
                          : Icons.volume_up_outlined,
                      color: DesignTokens.nightText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(_step.french, style: _display(30).copyWith(height: 1.15)),
              if (_showMeaning) ...[
                const SizedBox(height: 12),
                Text(
                  _step.english,
                  style: _body(
                    16,
                  ).copyWith(color: DesignTokens.nightMuted, height: 1.3),
                ),
              ],
              if (_step.tip.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _step.tip,
                  style: _body(12).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
              if (_heard.trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(success ? 'MATCHED' : 'I HEARD', style: _label(10)),
                const SizedBox(height: 4),
                Text(
                  _heard,
                  style: _body(14, weight: FontWeight.w700).copyWith(
                    color: success
                        ? DesignTokens.success
                        : DesignTokens.nightText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _wordChoiceCard() {
    final success = _state == _SpeakingStepState.success;
    final retry = _state == _SpeakingStepState.retry;
    final stateColor = success
        ? DesignTokens.success
        : retry
        ? DesignTokens.danger
        : DesignTokens.nightAccent;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: success
            ? DesignTokens.success.withValues(alpha: 0.12)
            : DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: success || retry ? stateColor : DesignTokens.nightHairline,
          width: success || retry ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                success
                    ? Icons.check_circle_rounded
                    : Icons.text_fields_rounded,
                color: stateColor,
              ),
              const SizedBox(width: 8),
              Text(
                success
                    ? 'Nice work'
                    : retry
                    ? 'Try it again'
                    : 'Complete the phrase',
                style: _body(
                  13,
                  weight: FontWeight.w800,
                ).copyWith(color: stateColor),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Play phrase',
                onPressed: _playing ? null : _playPhrase,
                icon: Icon(
                  _playing
                      ? Icons.graphic_eq_rounded
                      : Icons.volume_up_outlined,
                  color: DesignTokens.nightText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(_blankedSentence(), style: _display(27).copyWith(height: 1.15)),
          if (_showMeaning) ...[
            const SizedBox(height: 9),
            Text(
              _step.english,
              style: _body(
                15,
              ).copyWith(color: DesignTokens.nightMuted, height: 1.3),
            ),
          ],
          const SizedBox(height: 18),
          Text('TAP THE MISSING WORD', style: _label(10)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in _step.wordChoices)
                ChoiceChip(
                  label: Text(choice),
                  selected: _selectedWord == choice,
                  onSelected: success ? null : (_) => _chooseWord(choice),
                  selectedColor: success
                      ? DesignTokens.success
                      : DesignTokens.nightAccent,
                  backgroundColor: DesignTokens.nightSurfaceRaised,
                  side: BorderSide(color: DesignTokens.nightHairline),
                  labelStyle: _body(14, weight: FontWeight.w700).copyWith(
                    color: _selectedWord == choice && success
                        ? Colors.black
                        : DesignTokens.nightText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sentenceBuilderCard() {
    final success = _state == _SpeakingStepState.success;
    final retry = _state == _SpeakingStepState.retry;
    final stateColor = success
        ? DesignTokens.success
        : retry
        ? DesignTokens.danger
        : DesignTokens.nightAccent;
    final available = [
      for (var index = 0; index < _step.sentenceTokens.length; index++)
        if (!_selectedSentenceTokens.contains(index)) index,
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: success
            ? DesignTokens.success.withValues(alpha: 0.12)
            : DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: success || retry ? stateColor : DesignTokens.nightHairline,
          width: success || retry ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                success
                    ? Icons.check_circle_rounded
                    : Icons.format_list_bulleted_rounded,
                color: stateColor,
              ),
              const SizedBox(width: 8),
              Text(
                success
                    ? 'Nice work'
                    : retry
                    ? 'Try it again'
                    : 'Build the sentence',
                style: _body(
                  13,
                  weight: FontWeight.w800,
                ).copyWith(color: stateColor),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Play phrase',
                onPressed: _playing ? null : _playPhrase,
                icon: Icon(
                  _playing
                      ? Icons.graphic_eq_rounded
                      : Icons.volume_up_outlined,
                  color: DesignTokens.nightText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _selectedSentenceTokens.isEmpty
                ? 'Tap the words in the right order.'
                : _selectedSentenceTokens
                      .map((index) => _step.sentenceTokens[index])
                      .join(' '),
            style: _display(24).copyWith(
              height: 1.18,
              color: _selectedSentenceTokens.isEmpty
                  ? DesignTokens.nightMuted
                  : DesignTokens.nightText,
            ),
          ),
          if (_showMeaning) ...[
            const SizedBox(height: 9),
            Text(
              _step.english,
              style: _body(
                15,
              ).copyWith(color: DesignTokens.nightMuted, height: 1.3),
            ),
          ],
          const SizedBox(height: 18),
          Text('SENTENCE WORDS', style: _label(10)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final index in available.reversed)
                ActionChip(
                  label: Text(_step.sentenceTokens[index]),
                  onPressed: success ? null : () => _chooseSentenceToken(index),
                  backgroundColor: DesignTokens.nightSurfaceRaised,
                  side: BorderSide(color: DesignTokens.nightHairline),
                  labelStyle: _body(14, weight: FontWeight.w700),
                ),
            ],
          ),
          if (retry) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _resetGuidedExercise,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Start this sentence again'),
              style: TextButton.styleFrom(foregroundColor: DesignTokens.danger),
            ),
          ],
        ],
      ),
    );
  }

  String _blankedSentence() {
    final blank = _fold(_step.blankWord ?? '');
    return _step.french
        .split(RegExp(r'\s+'))
        .map((word) => _fold(word) == blank ? '_____' : word)
        .join(' ');
  }

  Future<void> _playPartnerLine() async {
    final line = _step.partnerFrench;
    if (line == null || line.trim().isEmpty || _playing || !mounted) return;
    setState(() {
      _playing = true;
      _error = null;
    });
    await LessonSpeechService.shared.speak(
      items: [
        SpeechItem(
          text: line,
          language: 'fr-FR',
          contentItemId:
              '${widget.contentKey ?? widget.title}_${_index}_partner',
          voiceName: _tutor.voiceName,
        ),
      ],
      rate: 0.34,
      onPlaybackReady: () {
        if (mounted) setState(() => _playing = false);
      },
      onFinished: () {
        if (mounted) setState(() => _playing = false);
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _playing = false;
            _error = 'Marie’s line could not be played: $error';
          });
        }
      },
    );
    if (mounted && _playing) setState(() => _playing = false);
  }

  Widget _coachCard() {
    final text = _isGuidedExercise
        ? switch (_step.stage) {
            SpeakingGuidedStage.wordChoice => switch (_state) {
              _SpeakingStepState.success => 'That word completes the phrase.',
              _SpeakingStepState.retry => 'Try the other word choices.',
              _ => 'Tap the word that completes the French phrase.',
            },
            SpeakingGuidedStage.sentenceBuilder => switch (_state) {
              _SpeakingStepState.success =>
                'The sentence is in the right order.',
              _SpeakingStepState.retry =>
                'Start again and follow the French order.',
              _ => 'Tap each word to build the sentence.',
            },
            SpeakingGuidedStage.speak => 'Listen once, then say the phrase.',
          }
        : switch (_state) {
            _SpeakingStepState.ready =>
              'Listen once, then hold the microphone and say the phrase.',
            _SpeakingStepState.recording =>
              'Listening… release when you finish the phrase.',
            _SpeakingStepState.checking => 'Checking your words…',
            _SpeakingStepState.success =>
              'Your phrase matched. Keep going while it is fresh.',
            _SpeakingStepState.retry =>
              'The phrase was not close enough yet. Replay it and try again.',
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Row(
        children: [
          Icon(
            Icons.tips_and_updates_outlined,
            color: DesignTokens.nightAccent,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: _body(13).copyWith(color: DesignTokens.nightMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomControls() {
    if (_isFreeTalk) return _freeTalkBottomControls();
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 10, 26, 15),
      decoration: BoxDecoration(
        color: DesignTokens.nightCanvas,
        border: Border(top: BorderSide(color: DesignTokens.nightHairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _smallControl(
              icon: _showMeaning
                  ? Icons.translate_rounded
                  : Icons.translate_outlined,
              label: _showMeaning ? 'Meaning on' : 'Meaning off',
              onTap: () => setState(() => _showMeaning = !_showMeaning),
            ),
          ),
          _guidedRoundAction(),
          Expanded(
            child: _smallControl(
              icon: Icons.volume_up_outlined,
              label: 'Replay target',
              onTap: _playing ? null : _playPhrase,
            ),
          ),
        ],
      ),
    );
  }

  Widget _guidedRoundAction() {
    final recording = _state == _SpeakingStepState.recording;
    final checking = _state == _SpeakingStepState.checking;
    final success = _state == _SpeakingStepState.success;
    final retry = _state == _SpeakingStepState.retry;
    final exercise = _isGuidedExercise;
    final active = success
        ? DesignTokens.success
        : retry || recording
        ? DesignTokens.danger
        : exercise && checking
        ? DesignTokens.nightSurfaceRaised
        : DesignTokens.nightAccent;
    final label = success
        ? 'Next phrase'
        : retry && exercise
        ? 'Try again'
        : recording
        ? 'Release to check'
        : checking
        ? 'Checking…'
        : exercise
        ? _step.stage == SpeakingGuidedStage.wordChoice
              ? 'Select a word'
              : 'Build the sentence'
        : 'Hold to speak';
    final VoidCallback? onTap = checking
        ? null
        : success
        ? _next
        : exercise
        ? retry
              ? _resetGuidedExercise
              : null
        : recording
        ? _stopRecording
        : _startRecording;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPressStart: exercise || checking || success
          ? null
          : (_) => _startRecording(),
      onLongPressEnd: exercise || checking || success
          ? null
          : (_) => _stopRecording(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(color: active, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(
              success
                  ? Icons.arrow_forward_rounded
                  : retry && exercise
                  ? Icons.refresh_rounded
                  : recording
                  ? Icons.stop_rounded
                  : exercise
                  ? Icons.touch_app_rounded
                  : Icons.mic_none_rounded,
              color: Colors.black,
              size: 30,
            ),
          ),
          const SizedBox(height: 7),
          Text(label, style: _body(11, weight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _freeTalkBottomControls() {
    final recording = _state == _SpeakingStepState.recording;
    final checking = _state == _SpeakingStepState.checking;
    final success = _state == _SpeakingStepState.success;
    final enabled = !checking;
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 10, 26, 15),
      decoration: BoxDecoration(
        color: DesignTokens.nightCanvas,
        border: Border(top: BorderSide(color: DesignTokens.nightHairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _smallControl(
              icon: Icons.volume_up_outlined,
              label: 'Replay Marie',
              onTap: _playing ? null : _playPartnerLine,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: !enabled
                ? null
                : success
                ? _next
                : recording
                ? _stopRecording
                : _startRecording,
            onLongPressStart: !enabled || success
                ? null
                : (_) => _startRecording(),
            onLongPressEnd: !enabled || success
                ? null
                : (_) => _stopRecording(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: success
                        ? DesignTokens.success
                        : recording
                        ? DesignTokens.danger
                        : DesignTokens.nightAccent,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    success
                        ? Icons.arrow_forward_rounded
                        : recording
                        ? Icons.stop_rounded
                        : Icons.mic_none_rounded,
                    color: Colors.black,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  success
                      ? 'Next phrase'
                      : recording
                      ? 'Release to check'
                      : checking
                      ? 'Checking…'
                      : 'Hold to speak',
                  style: _body(11, weight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Expanded(
            child: _smallControl(
              icon: Icons.volume_up_outlined,
              label: 'Replay target',
              onTap: _playing ? null : _playPhrase,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallControl({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Icon(
          icon,
          color: onTap == null
              ? DesignTokens.nightHairline
              : DesignTokens.nightText,
        ),
      ),
    );
  }

  Widget _messageCard(String message, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(message, style: _body(12).copyWith(color: color)),
    );
  }

  TextStyle _display(double size) =>
      DesignTokens.display(size).copyWith(color: DesignTokens.nightText);

  TextStyle _body(double size, {FontWeight weight = FontWeight.w400}) =>
      DesignTokens.body(
        size,
        weight: weight,
      ).copyWith(color: DesignTokens.nightText);

  TextStyle _label(double size) => _body(
    size,
    weight: FontWeight.w800,
  ).copyWith(color: DesignTokens.nightMuted, letterSpacing: 0.4);
}

/// Converts a course target list into the controlled Speak-like drill. The
/// course currently stores target phrases as French only, so familiar phrases
/// receive an inline meaning and unknown targets stay honest rather than
/// inventing a translation in the client.
const _speakingMeanings = {
  'bonjour': 'Hello.',
  'je m’appelle…': 'My name is…',
  'je m\'appelle…': 'My name is…',
  'enchanté, je suis…': 'Nice to meet you, I am…',
  'où est… ?': 'Where is…?',
  'je voudrais…, s’il vous plaît.': 'I would like…, please.',
  'combien ça coûte ?': 'How much does it cost?',
  'il y a…': 'There is / there are…',
  'tu veux venir… ?': 'Do you want to come…?',
  'pouvez-vous répéter ?': 'Can you repeat, please?',
};

List<SpeakingPhraseStep> speakingStepsForTargets(
  Iterable<String> targets, {
  String level = 'A1',
}) {
  final cleaned = targets
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .take(5)
      .toList(growable: false);
  if (cleaned.isEmpty) {
    throw StateError('This speaking lesson has no target phrases.');
  }
  return _buildSpeakingSteps(
    cleaned,
    meanings: _speakingMeanings,
    level: level,
  );
}

/// Provides the authored first-course scripts for adaptive rows. Adaptive
/// rows intentionally store a compact competency rather than a rich lesson
/// payload, so the speaking surface must use an explicit script registry, not
/// invent a phrase or silently switch to another mode.
List<SpeakingPhraseStep> speakingStepsForLesson({
  required Iterable<String> targets,
  required String title,
  required String competency,
  required String level,
}) {
  final cleaned = targets
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .take(5)
      .toList(growable: false);
  if (cleaned.isNotEmpty) {
    return speakingStepsForTargets(cleaned, level: level);
  }
  final label = '$title $competency'.toLowerCase();
  final phrases = label.contains('introduce')
      ? const [
          'Bonjour, je m’appelle Alex.',
          'Je viens de Toronto.',
          'Enchanté de vous rencontrer.',
          'Et vous, vous habitez où ?',
        ]
      : label.contains('appointment')
      ? const [
          'Bonjour, je voudrais prendre rendez-vous.',
          'Je suis disponible mardi matin.',
          'Est-ce que dix heures vous convient ?',
          'Merci, à mardi.',
        ]
      : label.contains('clarification')
      ? const [
          'Pardon, pouvez-vous répéter ?',
          'Pouvez-vous parler plus lentement ?',
          'Je n’ai pas compris la dernière phrase.',
          'Merci, maintenant je comprends.',
        ]
      : label.contains('routine')
      ? const [
          'Je me lève à sept heures.',
          'Je travaille le matin.',
          'Le soir, je prépare le dîner.',
          'Le week-end, je me repose.',
        ]
      : label.contains('choice')
      ? const [
          'Je préfère cette option.',
          'C’est plus simple pour moi.',
          'Je choisis le billet aller-retour.',
          'Merci pour votre conseil.',
        ]
      : label.contains('plan')
      ? const [
          'Demain, je vais travailler.',
          'Je voudrais visiter le musée.',
          'Si j’ai le temps, je prendrai un café.',
          'On peut se retrouver à midi.',
        ]
      : label.contains('problem')
      ? const [
          'J’ai un petit problème.',
          'La porte ne ferme pas.',
          'Pouvez-vous m’aider, s’il vous plaît ?',
          'Merci beaucoup pour votre aide.',
        ]
      : label.contains('opinion')
      ? const [
          'À mon avis, c’est une bonne idée.',
          'Je préfère cette solution.',
          'Parce qu’elle est simple et pratique.',
          'Et vous, qu’en pensez-vous ?',
        ]
      : label.contains('direction')
      ? const [
          'Excusez-moi, où est la gare ?',
          'Allez tout droit, puis tournez à gauche.',
          'C’est loin d’ici ?',
          'Merci, je vais trouver.',
        ]
      : label.contains('preference')
      ? const [
          'J’aime le thé, mais je préfère le café.',
          'Je préfère une table près de la fenêtre.',
          'Qu’est-ce que vous aimez ?',
          'Nous avons les mêmes goûts.',
        ]
      : label.contains('request')
      ? const [
          'Pourriez-vous m’aider, s’il vous plaît ?',
          'J’aurais besoin d’une information.',
          'Est-ce que vous pouvez vérifier ?',
          'Merci pour votre temps.',
        ]
      : label.contains('past')
      ? const [
          'Hier, je suis allé au marché.',
          'J’ai acheté des légumes frais.',
          'Ensuite, je suis rentré chez moi.',
          'C’était une matinée agréable.',
        ]
      : label.contains('natural')
      ? const [
          'Les amis arrivent à huit heures.',
          'Nous allons écouter la liaison.',
          'Je parle lentement et clairement.',
          'Je recommence avec un rythme naturel.',
        ]
      : label.contains('connect')
      ? const [
          'Je voudrais sortir, mais il pleut.',
          'Je reste à la maison parce que je suis fatigué.',
          'Donc, je vais lire un livre.',
          'Après cela, je préparerai le dîner.',
        ]
      : null;
  if (phrases == null) {
    throw StateError('No speaking script is configured for "$title".');
  }
  return _buildSpeakingSteps(
    phrases,
    meanings: _speakingMeanings,
    level: level,
  );
}

List<SpeakingPhraseStep> _buildSpeakingSteps(
  Iterable<String> source, {
  required Map<String, String> meanings,
  required String level,
}) {
  final steps = <SpeakingPhraseStep>[];
  for (final phrase in source) {
    final english =
        meanings[phrase.toLowerCase()] ??
        'Listen to the tutor, then use this phrase in the lesson.';
    steps.addAll(
      _guidedStagesForPhrase(phrase, english: english, level: level),
    );
  }
  return steps;
}

/// Keeps the authored English and partner fields from the permanent Speaking
/// catalog while adding the controlled word -> sentence -> speech progression.
/// Free Talk and Roleplay intentionally do not call this helper.
List<SpeakingPhraseStep> speakingStepsForCourseLines(
  Iterable<SpeakingCourseLine> lines, {
  required String level,
}) {
  final steps = <SpeakingPhraseStep>[];
  for (final line in lines) {
    if (line.partnerFrench != null || line.openResponse) {
      steps.add(
        SpeakingPhraseStep(
          french: line.french,
          english: line.english,
          partnerFrench: line.partnerFrench,
          partnerEnglish: line.partnerEnglish,
          tip: line.tip,
          openResponse: line.openResponse,
        ),
      );
    } else {
      steps.addAll(
        _guidedStagesForPhrase(
          line.french,
          english: line.english,
          level: level,
          tip: line.tip,
        ),
      );
    }
  }
  if (steps.isEmpty) {
    throw StateError('This speaking lesson has no practice lines.');
  }
  return steps;
}

List<SpeakingPhraseStep> _guidedStagesForPhrase(
  String phrase, {
  required String english,
  required String level,
  String tip = '',
}) {
  final tokens = phrase
      .split(RegExp(r'\s+'))
      .where((token) => token.trim().isNotEmpty)
      .toList(growable: false);
  if (tokens.isEmpty) {
    throw StateError('A speaking phrase cannot be empty.');
  }
  final blank = tokens.length == 1 ? tokens.first : tokens[1];
  final choices = _guidedWordChoices(blank, level: level);
  final rhythmTip = tip.trim().isNotEmpty
      ? tip
      : level.toUpperCase() == 'A1'
      ? 'Keep the rhythm clear and unhurried.'
      : 'Keep the key words connected and natural.';
  return [
    SpeakingPhraseStep(
      french: phrase,
      english: english,
      tip: rhythmTip,
      stage: SpeakingGuidedStage.wordChoice,
      blankWord: blank,
      wordChoices: choices,
    ),
    SpeakingPhraseStep(
      french: phrase,
      english: english,
      tip: rhythmTip,
      stage: SpeakingGuidedStage.sentenceBuilder,
      sentenceTokens: tokens,
    ),
    SpeakingPhraseStep(french: phrase, english: english, tip: rhythmTip),
  ];
}

List<String> _guidedWordChoices(String answer, {required String level}) {
  final distractors = level.toUpperCase() == 'A1'
      ? const ['bonjour', 'merci', 'voudrais', 'habite', 'cherche', 'aime']
      : const [
          'pourrais',
          'préférerais',
          'souhaite',
          'devrais',
          'propose',
          'comprends',
        ];
  final answerFolded = answer.toLowerCase();
  final choices = <String>[];
  for (final choice in distractors) {
    if (choice.toLowerCase() != answerFolded) choices.add(choice);
    if (choices.length == 2) break;
  }
  choices.insert(choices.isEmpty ? 0 : 1, answer);
  return choices;
}
