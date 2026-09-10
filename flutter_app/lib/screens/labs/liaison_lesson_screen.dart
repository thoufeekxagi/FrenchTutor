import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/liaison_curriculum_catalog.dart';
import '../../design/tokens.dart';
import '../../models/agent_tool.dart';
import '../../models/content_models.dart';
import '../../models/session.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../providers/tutor_helper_provider.dart';
import '../../services/audio_streaming_service.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/tutor_helper_settings.dart';
import '../../services/word_meaning_resolver.dart';
import '../../widgets/bilingual_word_text.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../../widgets/word_meaning_overlay.dart';
import '../speak/speak_ui.dart';

class LiaisonLessonScreen extends ConsumerStatefulWidget {
  const LiaisonLessonScreen({super.key, required this.lesson});

  final LiaisonCurriculumLesson lesson;

  @override
  ConsumerState<LiaisonLessonScreen> createState() =>
      _LiaisonLessonScreenState();
}

class _LiaisonLessonScreenState extends ConsumerState<LiaisonLessonScreen>
    with WidgetsBindingObserver {
  late int _step;
  bool _showTranslation = false;
  bool _isPlaying = false;
  bool _isRecording = false;
  bool _isChecking = false;
  bool? _hearChoice;
  bool? _hearCorrect;
  LiaisonAttemptAssessment? _assessment;
  String? _error;
  VocabEntry? _pairMeaning;
  VocabEntry? _selectedWordMeaning;
  int? _selectedWordIndex;
  bool _meaningLoading = false;
  int _meaningRequest = 0;
  String _sentence = '';
  String _sentenceEnglish = '';
  String _passage = '';
  String _passageEnglish = '';
  String _lastTranscript = '';
  int _playbackGeneration = 0;
  int _attemptGeneration = 0;
  Timer? _attemptTimeout;
  late final InlineCallController _call;
  late final AudioStreamingService _liveNarrationAudio;
  final Set<int> _passedSteps = {};

  LiaisonCurriculumLesson get lesson => widget.lesson;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _step = 0;
    _sentence = lesson.sentence;
    _sentenceEnglish = lesson.sentenceEnglish;
    _passage = _cleanPassage(lesson.passage);
    _passageEnglish = _cleanPassage(lesson.passageEnglish);
    _liveNarrationAudio = AudioStreamingService();
    _call = InlineCallController(
      sessionType: LiveSessionType.liaisonStage,
      lessonContext: () => _lessonContext,
      levelOverride: lesson.level,
      learningStoreForProfile: ref.read(learningStoreProvider),
      compactGuidedContext: true,
      manualLearnerTurns: true,
      tools: AgentTool.liaisonPalette,
      openingPrompt:
          'APP_SCREEN_CHANGED: Briefly orient the learner to the current Liaison screen. Explain the small goal, what is visible, and one action to take now. Use at most two short sentences, then wait.',
      onChanged: () {
        if (mounted) setState(() {});
      },
      onUserTranscript: (text) {
        if (mounted) setState(() => _lastTranscript = text);
      },
      onToolCall: _handleLiveToolCall,
    );
    ref
        .read(learningStoreProvider)
        .setLessonStatus(lesson.progressId, 'in_progress');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = ref.read(tutorHelperSettingsProvider);
      unawaited(() async {
        await settings.load();
        if (!mounted || !settings.isEnabled(TutorHelperSurface.speaking)) {
          return;
        }
        await _call.start(context, sendOpeningPrompt: true);
      }());
      unawaited(_repairMissingExample());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attemptTimeout?.cancel();
    ++_playbackGeneration;
    _call.dispose();
    unawaited(_liveNarrationAudio.stopPlayback(hardStop: true));
    unawaited(_liveNarrationAudio.dispose());
    unawaited(LessonSpeechService.shared.deactivate());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _call.handleAppLifecycle(state);
  }

  String get _lessonContext =>
      '''
LIAISON PRACTICE
LEVEL: ${lesson.level}
CURRENT STEP: $_step
PAIR: ${lesson.firstWord} ${lesson.secondWord}
RULE: ${lesson.ruleType.name}
EXPECTED LINK SOUND: ${lesson.linkSound}
DISPLAY: ${lesson.linkedDisplay}
CURRENT TARGET: ${_targetText.trim()}
CURRENT MEANING: ${_targetEnglish.trim()}
CURRENT SCREEN STAGE: $_stageLabel
LEARNER TASK NOW: $_learnerTask
TUTOR GUIDANCE: $_tutorGuidance
The app owns the step order and pass/fail state. Use only this current target.
Explain the goal and current task briefly when the app announces a new screen.
Repeat the exact current target once when asked, answer only a brief question
about this liaison, and otherwise wait for the learner.
''';

  String get _stageLabel => switch (_step) {
    0 => 'See the link: notice the two words and the possible linking sound',
    1 => 'Hear the link: listen and decide whether the words connect',
    2 => 'Say the link: pronounce the pair with the approved liaison',
    3 => 'Use it in a sentence: say the full sentence clearly',
    4 => 'Read it in context: say the short passage without breaking the link',
    _ => 'Review: the Liaison lesson is complete',
  };

  String get _learnerTask => switch (_step) {
    0 =>
      'Look at the pair, notice the final and initial sounds, then tap Continue',
    1 => 'Play the example, choose whether the words link, then tap Continue',
    2 => 'Tap Replay if needed, tap Record, say the pair, then tap Stop',
    3 => 'Tap Replay if needed, tap Record, say the sentence, then tap Stop',
    4 => 'Tap Replay if needed, tap Record, read the passage, then tap Stop',
    _ => 'Review the linked form and finish the lesson',
  };

  String get _tutorGuidance => switch (_step) {
    0 =>
      'Explain the sound connection in plain language; do not test pronunciation yet',
    1 =>
      'Help the learner notice the sound and choose the matching answer; do not reveal it first',
    2 || 3 || 4 =>
      'Model only when asked, listen to the complete attempt, then explain one useful correction',
    _ => 'Congratulate briefly and do not start a new exercise',
  };

  bool get _tutorPreferenceEnabled => ref
      .read(tutorHelperSettingsProvider)
      .isEnabled(TutorHelperSurface.speaking);

  bool get _tutorEnabled => _tutorPreferenceEnabled && _call.isLive;

  String _cleanPassage(String value) => value
      .replaceAll(
        RegExp(
          r'\s*Répétez la phrase une fois,? sans faire de pause\.?',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'\s*Repeat the sentence once without pausing\.?',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  Future<void> _repairMissingExample() async {
    final hasUsableExamples =
        _sentence.trim().isNotEmpty &&
        _sentenceEnglish.trim().isNotEmpty &&
        _passage.trim().isNotEmpty &&
        _passageEnglish.trim().isNotEmpty &&
        lesson.passage == _cleanPassage(lesson.passage);
    if (hasUsableExamples) return;
    if (!mounted) return;

    try {
      final generated = await ref
          .read(lessonAgentServiceProvider)
          .generateLiaisonPracticeExample(
            levelBand: lesson.level,
            firstWord: lesson.firstWord,
            secondWord: lesson.secondWord,
            ruleType: lesson.ruleType.name,
            linkSound: lesson.linkSound,
          );
      if (!mounted) return;
      setState(() {
        _sentence = generated.sentence;
        _sentenceEnglish = generated.sentenceEnglish;
        _passage = generated.passage;
        _passageEnglish = generated.passageEnglish;
      });
      _call.updateLessonContext();
    } catch (_) {}
  }

  void _toggleMeaning() {
    final next = !_showTranslation;
    setState(() => _showTranslation = next);
    if (next && _step == 2 && _pairMeaning == null) {
      unawaited(_resolvePairMeaning());
    }
  }

  Future<void> _resolvePairMeaning() async {
    if (_pairMeaning != null || _meaningLoading) return;
    setState(() => _meaningLoading = true);
    try {
      final result = await WordMeaningResolver.resolve(
        word: lesson.phrase,
        sentence: lesson.phrase,
        sentenceTranslation: '',
        levelBand: lesson.level,
      );
      if (!mounted) return;
      setState(() {
        _pairMeaning = result.entry;
        _meaningLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _meaningLoading = false);
    }
  }

  void _selectWord(int index) {
    final words = _wordParts(_targetText);
    if (index < 0 || index >= words.length) return;
    final same = _selectedWordIndex == index;
    final request = ++_meaningRequest;
    setState(() {
      _selectedWordIndex = same ? null : index;
      _selectedWordMeaning = null;
      _meaningLoading = !same;
      _showTranslation = !same;
    });
    if (!same) unawaited(_resolveWordMeaning(words[index], request));
  }

  Future<void> _resolveWordMeaning(String rawWord, int request) async {
    final word = _cleanWord(rawWord);
    if (word.isEmpty) return;
    try {
      final result = await WordMeaningResolver.resolve(
        word: word,
        sentence: _targetText,
        sentenceTranslation: _step == 2
            ? (_pairMeaning?.en ?? '')
            : _targetEnglish,
        levelBand: lesson.level,
      );
      if (!mounted || request != _meaningRequest) return;
      setState(() {
        _selectedWordMeaning = result.entry;
        _meaningLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _meaningRequest) return;
      setState(() => _meaningLoading = false);
    }
  }

  List<String> _wordParts(String text) => text
      .split(RegExp(r'\s+'))
      .where((word) => word.trim().isNotEmpty)
      .toList(growable: false);

  String _cleanWord(String word) => word
      .replaceAll(RegExp(r'^[.,!?;:«»"“”¿¡()\[\]]+'), '')
      .replaceAll(RegExp(r'[.,!?;:«»"“”¿¡()\[\]]+$'), '')
      .trim();

  String get _title => switch (_step) {
    0 => 'See the link',
    1 => 'Hear the link',
    2 => 'Say the link',
    3 => 'Use it in a sentence',
    4 => 'Read it in context',
    _ => 'Liaison complete',
  };

  String get _targetText => switch (_step) {
    2 => lesson.phrase,
    3 => _sentence,
    4 => _passage,
    _ => lesson.phrase,
  };

  String get _targetEnglish => switch (_step) {
    2 => _pairMeaning?.en ?? '',
    3 => _sentenceEnglish,
    4 => _passageEnglish,
    _ => lesson.subtitle,
  };

  Future<bool> _ensureLiveReady() async {
    if (!_tutorPreferenceEnabled) {
      if (mounted) {
        setState(
          () => _error =
              '${ActiveTutor.current.displayName} help is off. Tap the phone to turn it on.',
        );
      }
      return false;
    }
    if (!_call.isLive) {
      await _call.start(context, sendOpeningPrompt: false);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (mounted &&
        !_call.isReadyForLearnerTurn &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return _call.isReadyForLearnerTurn;
  }

  Future<void> _setTutorEnabled(bool enabled) async {
    final settings = ref.read(tutorHelperSettingsProvider);
    if (!enabled) {
      _attemptTimeout?.cancel();
      await _call.end();
      await settings.setEnabled(TutorHelperSurface.speaking, false);
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isChecking = false;
        _error = null;
      });
      return;
    }

    await settings.setEnabled(TutorHelperSurface.speaking, true);
    if (!mounted) return;
    setState(() => _error = null);
    await _call.start(context, sendOpeningPrompt: true);
    if (!mounted) return;
    if (!_call.isLive) {
      await settings.setEnabled(TutorHelperSurface.speaking, false);
      setState(
        () => _error =
            _call.error ??
            '${ActiveTutor.current.displayName} could not connect.',
      );
    }
    setState(() {});
  }

  Future<void> _play(String text) async {
    if (_isPlaying || _isRecording || _isChecking) return;
    if (!await _ensureLiveReady()) {
      if (mounted && _error == null) {
        setState(() => _error = 'Marie is not connected yet. Try again.');
      }
      return;
    }
    final generation = ++_playbackGeneration;
    setState(() {
      _isPlaying = true;
      _error = null;
    });
    var audioFeedTail = Future<void>.value();
    var audioFeedFailed = false;
    try {
      await _call.beginExternalPlayback();
      await _call.narrateExternalText(
        instruction:
            'APP_NARRATION liaison_step=$_step AUDIO_REQUIRED. Say only this exact French target once and stop. Do not translate, explain, or add words: $text',
        onAudioChunk: (bytes) {
          if (!mounted || generation != _playbackGeneration) return;
          audioFeedTail = audioFeedTail.then((_) async {
            try {
              await _liveNarrationAudio.playAudioChunk(bytes);
            } catch (_) {
              audioFeedFailed = true;
            }
          });
        },
        onTranscriptDelta: (_) {},
      );
      await audioFeedTail;
      if (audioFeedFailed) throw StateError('Audio could not be queued');
      await _liveNarrationAudio.waitForPlaybackDrained();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Audio failed: $error');
    } finally {
      await _liveNarrationAudio.stopPlayback(hardStop: true);
      // Keep the compact Liaison socket warm for the next example or learner
      // turn. Closing it here would make every speaker tap pay connection
      // latency again.
      await _call.endExternalPlayback();
      if (mounted && generation == _playbackGeneration) {
        setState(() => _isPlaying = false);
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_isChecking || _isPlaying) return;
    if (_isRecording) {
      setState(() {
        _isRecording = false;
        _isChecking = true;
      });
      await _call.endLearnerTurn();
      final generation = ++_attemptGeneration;
      _attemptTimeout?.cancel();
      _attemptTimeout = Timer(const Duration(seconds: 8), () {
        if (!mounted || generation != _attemptGeneration || !_isChecking) {
          return;
        }
        setState(() {
          _isRecording = false;
          _isChecking = false;
          _error = 'Marie could not verify that attempt. Please try again.';
        });
      });
      return;
    }
    if (!await _ensureLiveReady()) {
      if (mounted && _error == null) {
        setState(() => _error = 'Marie is not connected yet. Try again.');
      }
      return;
    }
    if (!await _call.startLearnerTurn()) {
      if (mounted) {
        setState(() => _error = 'Microphone is not ready. Try again.');
      }
      return;
    }
    setState(() {
      _isRecording = true;
      _assessment = null;
      _lastTranscript = '';
      _error = null;
    });
  }

  void _handleLiveToolCall(
    String name,
    Map<String, dynamic> args,
    String callId,
  ) {
    if (name != 'grade_liaison_attempt' || !_isChecking) return;
    final step = (args['step_index'] as num?)?.toInt() ?? _step;
    final audioClear = args['audio_clear'] == true;
    final wordsMatch = args['words_match'] == true;
    final liaisonMatch = args['liaison_match'] == true;
    final confidence = ((args['confidence'] as num?)?.toDouble() ?? 0).clamp(
      0.0,
      1.0,
    );
    final heard = args['heard']?.toString().trim() ?? _lastTranscript;
    final feedback =
        args['feedback']?.toString().trim() ?? 'Try that line once more.';
    final result = LiaisonAttemptAssessment(
      transcript: heard,
      audioClear: audioClear,
      wordsMatch: wordsMatch,
      liaisonMatch: liaisonMatch,
      confidence: confidence,
      feedback: feedback,
    );
    final passed =
        audioClear && wordsMatch && liaisonMatch && confidence >= 0.6;
    _attemptTimeout?.cancel();
    _call.sendToolResponse(
      callId: callId,
      name: name,
      result: {'accepted': passed, 'step_index': step},
    );
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isChecking = false;
      _assessment = result;
      if (passed && step == _step) _passedSteps.add(_step);
    });
  }

  bool get _canContinue => switch (_step) {
    0 => true,
    1 => _hearCorrect == true,
    // Once Live has returned a grading result, the learner can choose either
    // to practise this target again or move on, matching Speaking Guided.
    2 || 3 || 4 => _assessment != null,
    _ => true,
  };

  void _next() {
    if (!_canContinue) return;
    if (_step >= 5) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _step++;
      _showTranslation = false;
      _hearChoice = null;
      _hearCorrect = null;
      _assessment = null;
      _error = null;
      _selectedWordIndex = null;
      _selectedWordMeaning = null;
      _meaningLoading = false;
      ++_meaningRequest;
    });
    _call.updateLessonContext();
    if (_call.isLive && _step < 5) {
      _call.promptTutor(
        'APP_SCREEN_CHANGED: The learner just opened the current Liaison step. '
        'Briefly explain the goal, what is visible, and exactly one action to '
        'take now using the latest screen context. Use at most two short '
        'sentences, then stop and wait.',
      );
    }
    if (_step == 5) _finish();
  }

  void _finish() {
    const expectedChecks = 4;
    const firstExpectedStep = 1;
    final passedChecks = _passedSteps
        .where((step) => step >= firstExpectedStep && step <= 4)
        .length;
    final score = passedChecks / expectedChecks;
    ref
        .read(learningStoreProvider)
        .setLessonStatus(
          lesson.progressId,
          'completed',
          score: score.clamp(0, 1),
        );
    final now = DateTime.now().toUtc();
    ref
        .read(storageServiceProvider)
        .saveSession(
          Session(
            id: 'liaison_${now.microsecondsSinceEpoch}',
            startedAt: now.toIso8601String(),
            endedAt: now.toIso8601String(),
            topic: lesson.title,
            contentKey: lesson.progressId,
            stage: 'liaison',
            summary:
                'Completed ${lesson.title} (${lesson.level}) liaison practice.',
          ),
        );
  }

  void _answerHear(bool links) {
    final expected = lesson.ruleType == LiaisonRuleType.optional
        ? true
        : links == lesson.expectsLink;
    setState(() {
      _hearChoice = links;
      _hearCorrect = expected;
      if (expected) _passedSteps.add(1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = ((_step + 1) / 6).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: SpeakColors.background,
      body: SafeArea(
        child: WebConstrainedView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(CupertinoIcons.xmark),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
                          backgroundColor: SpeakColors.line,
                          valueColor: AlwaysStoppedAnimation(
                            SpeakColors.accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_step + 1} of 6',
                      style: DesignTokens.label(
                        11,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: [
                    Text(
                      lesson.level,
                      style: DesignTokens.label(
                        12,
                      ).copyWith(color: SpeakColors.accent),
                    ),
                    const SizedBox(height: 8),
                    Text(_title, style: DesignTokens.display(30)),
                    const SizedBox(height: 8),
                    Text(
                      lesson.title,
                      style: DesignTokens.body(
                        14,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                    const SizedBox(height: 18),
                    _buildTutorHelpCard(),
                    const SizedBox(height: 24),
                    if (_step == 0) _buildExplanation(),
                    if (_step == 1) _buildHear(),
                    if (_step >= 2 && _step <= 4) _buildSpeaking(),
                    if (_step == 5) _buildReview(),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _MessageCard(
                        text: _error!,
                        color: DesignTokens.danger,
                        icon: CupertinoIcons.exclamationmark_triangle,
                      ),
                    ],
                  ],
                ),
              ),
              if (_step >= 2 && _step <= 4)
                _buildSpeakingBottomControls()
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                  child: SpeakPrimaryButton(
                    label: _step == 5 ? 'Finish lesson' : 'Continue',
                    icon: CupertinoIcons.arrow_right,
                    onTap: _canContinue ? _next : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTutorHelpCard() {
    final tutor = ActiveTutor.current;
    final status = _call.connecting
        ? 'Connecting for extra guidance…'
        : _tutorEnabled
        ? _isRecording
              ? 'Live · listening to this answer'
              : 'Live · follows this liaison'
        : _tutorPreferenceEnabled
        ? 'On · tap the phone to reconnect'
        : 'Off · tap the phone for live guidance';
    final phoneColor = _tutorEnabled
        ? DesignTokens.success
        : _tutorPreferenceEnabled
        ? SpeakColors.accent
        : SpeakColors.inkSoft;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      decoration: BoxDecoration(
        color: SpeakColors.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: SpeakColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: SpeakColors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(CupertinoIcons.phone_fill, size: 20, color: phoneColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tutor.displayName} help',
                  style: DesignTokens.body(13, weight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.body(
                    11,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _tutorEnabled
                ? 'Turn off extra tutor guidance'
                : 'Turn on extra tutor guidance',
            onPressed: _call.connecting
                ? null
                : () => unawaited(_setTutorEnabled(!_tutorEnabled)),
            icon: _call.connecting
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: SpeakColors.accent,
                    ),
                  )
                : Icon(CupertinoIcons.phone_fill, color: phoneColor),
          ),
        ],
      ),
    );
  }

  Widget _buildExplanation() {
    return SpeakCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(lesson.firstWord, style: DesignTokens.display(25)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  lesson.expectsLink ? '‿${lesson.linkSound}‿' : ' · ',
                  style: DesignTokens.display(
                    23,
                  ).copyWith(color: SpeakColors.accent),
                ),
              ),
              Flexible(
                child: Text(
                  lesson.secondWord,
                  style: DesignTokens.display(25),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            lesson.soundHint,
            textAlign: TextAlign.center,
            style: DesignTokens.body(15, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            lesson.explanation,
            textAlign: TextAlign.center,
            style: DesignTokens.body(
              13,
            ).copyWith(color: SpeakColors.inkSoft, height: 1.45),
          ),
          const SizedBox(height: 18),
          _AudioButton(onTap: () => _play(lesson.phrase), playing: _isPlaying),
        ],
      ),
    );
  }

  Widget _buildHear() {
    final optional = lesson.ruleType == LiaisonRuleType.optional;
    return Column(
      children: [
        SpeakCard(
          child: Column(
            children: [
              Text(
                'Listen first. What happens between the words?',
                textAlign: TextAlign.center,
                style: DesignTokens.body(16, weight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              _AudioButton(
                onTap: () => _play(lesson.sentence),
                playing: _isPlaying,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ChoiceButton(
          label: optional ? 'I hear a link (optional)' : 'The words link',
          selected: _hearChoice == true,
          onTap: () => _answerHear(true),
        ),
        const SizedBox(height: 10),
        _ChoiceButton(
          label: optional ? 'They may stay separate' : 'They stay separate',
          selected: _hearChoice == false,
          onTap: () => _answerHear(false),
        ),
        if (_hearCorrect == false) ...[
          const SizedBox(height: 12),
          _MessageCard(
            text: lesson.soundHint,
            color: DesignTokens.danger,
            icon: CupertinoIcons.refresh,
          ),
        ],
      ],
    );
  }

  Widget _buildSpeaking() {
    final assessment = _assessment;
    final passed = _passedSteps.contains(_step);
    return Column(
      children: [
        SpeakCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: BilingualWordText(
                      source: _targetText,
                      translation: _targetEnglish,
                      sourceStyle: DesignTokens.display(
                        _step == 2 ? 27 : 21,
                      ).copyWith(height: 1.15),
                      translationStyle: DesignTokens.body(
                        14,
                      ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                      keywords: const [],
                      selectedSourceWord: _selectedWordIndex,
                      onSourceWordTap: _selectWord,
                      accentColor: SpeakColors.accent,
                      showTranslation:
                          _showTranslation && _targetEnglish.trim().isNotEmpty,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _play(_targetText),
                    icon: Icon(
                      _isPlaying
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.speaker_2_fill,
                      color: SpeakColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _toggleMeaning,
                  icon: const Icon(CupertinoIcons.textformat_alt, size: 17),
                  label: Text(
                    _showTranslation ? 'Hide meaning' : 'Show meaning',
                  ),
                ),
              ),
              if (_showTranslation && _meaningLoading)
                Text(
                  'Looking up meaning…',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
              if (_selectedWordMeaning != null) ...[
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: SpeakColors.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: WordMeaningOverlay(
                      word: _selectedWordMeaning!,
                      accent: SpeakColors.accent,
                      darkMode: true,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (assessment != null) ...[
          const SizedBox(height: 14),
          _MessageCard(
            text: assessment.feedback,
            color: passed ? DesignTokens.success : DesignTokens.danger,
            icon: passed
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.arrow_counterclockwise,
            detail: assessment.transcript.isEmpty
                ? null
                : 'Heard: ${assessment.transcript}',
          ),
        ],
      ],
    );
  }

  Widget _buildSpeakingBottomControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 10, 26, 15),
      decoration: BoxDecoration(
        color: SpeakColors.background,
        border: Border(top: BorderSide(color: SpeakColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _liaisonSmallControl(
              icon: _showTranslation
                  ? CupertinoIcons.textformat_alt
                  : CupertinoIcons.textformat_alt,
              label: _showTranslation ? 'Meaning on' : 'Meaning',
              selected: _showTranslation,
              onTap: _toggleMeaning,
            ),
          ),
          _liaisonRoundAction(),
          Expanded(
            child: _liaisonSmallControl(
              icon: CupertinoIcons.speaker_2,
              label: 'Replay',
              onTap: (_isPlaying || _isRecording || _isChecking)
                  ? null
                  : () => _play(_targetText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liaisonRoundAction() {
    if (_assessment != null && !_isRecording && !_isChecking) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _liaisonCompactAction(
            icon: CupertinoIcons.refresh,
            label: 'Practice more',
            onTap: _practiceMore,
          ),
          const SizedBox(width: 10),
          _liaisonCompactAction(
            icon: CupertinoIcons.arrow_right,
            label: 'Next phrase',
            onTap: _next,
          ),
        ],
      );
    }

    final checking = _isChecking;
    final recording = _isRecording;
    final label = checking
        ? 'Checking…'
        : recording
        ? 'Stop'
        : 'Record';
    final icon = checking
        ? CupertinoIcons.hourglass
        : recording
        ? CupertinoIcons.stop_fill
        : CupertinoIcons.mic_fill;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: checking ? null : _toggleRecording,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: checking ? SpeakColors.line : SpeakColors.accent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: SpeakColors.onAccent, size: 29),
          ),
          const SizedBox(height: 7),
          Text(label, style: DesignTokens.body(11, weight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _liaisonSmallControl({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool selected = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: selected ? SpeakColors.accent : DesignTokens.ink,
            size: 25,
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: DesignTokens.body(10, weight: FontWeight.w800).copyWith(
              color: selected ? SpeakColors.accent : SpeakColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }

  Widget _liaisonCompactAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: SpeakColors.accent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: SpeakColors.onAccent, size: 25),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: DesignTokens.body(
              9,
              weight: FontWeight.w800,
            ).copyWith(color: DesignTokens.ink),
          ),
        ],
      ),
    );
  }

  void _practiceMore() {
    if (_isRecording || _isChecking || _isPlaying) return;
    _attemptTimeout?.cancel();
    _passedSteps.remove(_step);
    setState(() {
      _assessment = null;
      _lastTranscript = '';
      _error = null;
    });
  }

  Widget _buildReview() {
    return SpeakCard(
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DesignTokens.successSoft,
            ),
            child: Icon(
              CupertinoIcons.check_mark,
              color: DesignTokens.success,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text('You connected it.', style: DesignTokens.display(24)),
          const SizedBox(height: 8),
          Text(
            lesson.linkedDisplay,
            style: DesignTokens.body(
              17,
              weight: FontWeight.w700,
            ).copyWith(color: SpeakColors.accent),
          ),
          const SizedBox(height: 8),
          Text(
            lesson.explanation,
            textAlign: TextAlign.center,
            style: DesignTokens.body(
              13,
            ).copyWith(color: SpeakColors.inkSoft, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _AudioButton extends StatelessWidget {
  const _AudioButton({required this.onTap, required this.playing});

  final VoidCallback onTap;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: SpeakColors.accent,
        foregroundColor: SpeakColors.onAccent,
        minimumSize: const Size(58, 58),
      ),
      icon: Icon(
        playing ? CupertinoIcons.pause_fill : CupertinoIcons.speaker_2_fill,
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        decoration: BoxDecoration(
          color: SpeakColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? DesignTokens.success : SpeakColors.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: DesignTokens.body(14, weight: FontWeight.w600),
              ),
            ),
            if (selected)
              Icon(CupertinoIcons.check_mark, color: DesignTokens.success),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.text,
    required this.color,
    required this.icon,
    this.detail,
  });

  final String text;
  final String? detail;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: DesignTokens.body(13, weight: FontWeight.w600),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    detail!,
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: SpeakColors.inkSoft),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
