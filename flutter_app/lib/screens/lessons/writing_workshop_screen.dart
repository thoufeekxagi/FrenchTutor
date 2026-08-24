import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/learning_store.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/session_recorder.dart';
import '../../widgets/floating_notetaker.dart';
import '../../widgets/inline_call_bar.dart';
import '../../widgets/learning_card.dart';
import '../../widgets/lesson_stage_rail.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/report_problem_button.dart';
import '../../widgets/web/web_constrained_view.dart';

enum _WritingStep { brief, build, draft, review, rewrite }

typedef WritingFeedbackGrader =
    Future<WritingFeedback> Function({
      required WritingTask task,
      required String submission,
      required String levelBand,
    });

final writingFeedbackGraderProvider = Provider<WritingFeedbackGrader>((ref) {
  return ({
    required WritingTask task,
    required String submission,
    required String levelBand,
  }) => ref
      .read(lessonAgentServiceProvider)
      .gradeWriting(task: task, submission: submission, levelBand: levelBand);
});

/// A guided writing loop that moves the learner from supported construction to
/// independent production, then makes one important correction reusable.
///
/// This is intentionally separate from the legacy one-shot editor. The task
/// and grading contracts remain the same, so existing content and persistence
/// keep working, while the learner gets a better path through them.
class WritingWorkshopScreen extends ConsumerStatefulWidget {
  const WritingWorkshopScreen({super.key, required this.task});

  final WritingTask task;

  @override
  ConsumerState<WritingWorkshopScreen> createState() =>
      _WritingWorkshopScreenState();
}

class _WritingWorkshopScreenState extends ConsumerState<WritingWorkshopScreen>
    with WidgetsBindingObserver {
  _WritingStep _step = _WritingStep.brief;
  bool _showEnglish = false;
  bool _isGrading = false;
  bool _isHinting = false;
  String _draft = '';
  String _rewrite = '';
  String? _hint;
  int _hintTier = 0;
  int _hintsUsed = 0;
  WritingFeedback? _feedback;
  MicroWritingFeedback? _rewriteFeedback;
  List<String> _selectedTokens = [];
  String? _errorText;

  final _draftController = TextEditingController();
  final _rewriteController = TextEditingController();
  final DateTime _sessionStart = DateTime.now();

  late final InlineCallController _call;
  late final SessionRecorder _recorder;
  late final LearningStore _learningStore;

  WritingTask get _task => widget.task;
  bool get _isBeginner =>
      _task.levelBand.toUpperCase() == 'A1' ||
      _task.levelBand.toUpperCase() == 'A2';
  int get _minimumWords => _task.minWords;
  bool get _isConstructionTask =>
      _task.wordBank.isNotEmpty && _task.targetTokens.isNotEmpty;
  String get _displayPromptFr {
    if (!_isConstructionTask) return _task.promptFr;
    return _task.type == 'word'
        ? 'Complète la phrase.'
        : 'Construis la phrase.';
  }

  String get _displayPromptEn {
    if (!_isConstructionTask || _task.type == 'word') {
      return _task.promptEn;
    }
    return _task.promptEn.replaceFirst(RegExp(r'^Build:\s*'), '');
  }

  // A short draft is still valid input for review. The task's target length is
  // guidance for the learner, not a disabled-submit gate that strands them at
  // the keyboard or after dismissing it.
  bool get _draftReady => _draft.trim().isNotEmpty;

  int get _railIndex {
    if (!_isConstructionTask) return _WritingStep.values.indexOf(_step);
    return switch (_step) {
      _WritingStep.brief => 0,
      _WritingStep.build => 1,
      _WritingStep.review => 2,
      _WritingStep.rewrite => 2,
      _WritingStep.draft => 1,
    };
  }

  List<String> get _supportWords {
    final profile = ref.read(learningStoreProvider);
    final content = ref.read(contentServiceProvider);
    final known = content.knownVocabWords(profile.allSRSStates());
    return <String>{
      ...known.take(8),
      ..._task.targetConnectors,
    }.take(12).toList();
  }

  @override
  void initState() {
    super.initState();
    _showEnglish = _isBeginner;
    WidgetsBinding.instance.addObserver(this);
    // Resolve provider-backed dependencies while the ConsumerState is alive.
    // `ref` is invalid once dispose() starts, so teardown must use this
    // captured store instead of reading providers again.
    _learningStore = ref.read(learningStoreProvider);
    _call = InlineCallController(
      sessionType: LiveSessionType.writingGuide,
      lessonContext: () => _liveContext,
      learningStoreForProfile: _learningStore,
      openingPrompt:
          'The writing workshop has opened. Say one warm sentence explaining '
          'that you can help the learner plan or revise this draft, then wait.',
      onChanged: () {
        if (mounted) setState(() {});
      },
      onUserTranscript: (text) => _recorder.logUser(text),
      onTutorTranscript: (text) => _recorder.logTutor(text),
    );
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'writing',
      topic: _task.title,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(notetakerStateProvider).currentContext = 'Writing workshop';
    });
  }

  String get _liveContext =>
      '''
WRITING WORKSHOP
Task: ${_task.title}
Mode: ${_task.type}
French prompt: $_displayPromptFr
English prompt: $_displayPromptEn
Minimum words: ${_task.minWords}
Exam section: ${_task.examSection ?? '(none)'}
Time limit minutes: ${_task.timeLimitMinutes ?? '(none)'}
Maximum words: ${_task.maxWords ?? '(none)'}
Target answer: ${_task.targetTokens.join(' ')}
Target connectors: ${_task.targetConnectors.join(', ')}
Rubric focus: ${_task.rubricHints.join('; ')}
Current draft: ${_draft.trim().isEmpty ? '(empty)' : _draft.trim()}
${_feedback == null ? '' : 'Latest feedback: ${_feedback!.nextSteps.join('; ')}'}
Chosen tutor: ${ActiveTutor.current.displayName}
Help the learner think and write. Do not write the whole answer for them unless they explicitly ask for a translation.
''';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _call.handleAppLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LessonSpeechService.shared.stop();
    _call.dispose();
    _draftController.dispose();
    _rewriteController.dispose();
    final feedback = _feedback;
    _recorder.finish(
      summary: feedback == null
          ? 'Practised writing "${_task.title}".'
          : 'Wrote "${_task.title}" and scored ${feedback.scoreOutOf10.toStringAsFixed(1)}/10.',
      // This is a typed writing lesson, not a live conversation. The grade,
      // corrections, and next steps above are already the useful review; do
      // not launch a second ambient transcript-summary request on dispose.
      autoNote: false,
    );
    final minutes = DateTime.now().difference(_sessionStart).inMinutes;
    if (minutes > 0 && _draft.trim().isNotEmpty) {
      _learningStore.markHabit('writing', minutes: minutes);
    }
    super.dispose();
  }

  void _next() {
    if (_isConstructionTask && _step == _WritingStep.review) {
      Navigator.of(context).pop(true);
      return;
    }
    if (_step == _WritingStep.rewrite) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _step = _WritingStep.values[_step.index + 1]);
  }

  void _checkConstruction() {
    final expected = _task.targetTokens.map(_normaliseToken).join(' ');
    final actual = _selectedTokens.map(_normaliseToken).join(' ');
    final correct = actual == expected;
    setState(() {
      _errorText = correct
          ? null
          : 'Not quite. Move the words into the order shown by the prompt.';
      if (correct) _step = _WritingStep.review;
    });
  }

  String _normaliseToken(String value) => value
      .trim()
      .replaceAll(RegExp(r"\s+"), ' ')
      .replaceAll(RegExp(r"\s+([,.!?])"), r'\1')
      .toLowerCase();

  void _toggleToken(String token) {
    setState(() {
      final normalised = _normaliseToken(token);
      final selectedCount = _selectedTokens
          .map(_normaliseToken)
          .where((value) => value == normalised)
          .length;
      final targetCount = _task.targetTokens
          .map(_normaliseToken)
          .where((value) => value == normalised)
          .length;
      if (selectedCount > 0 && selectedCount >= targetCount) {
        final next = [..._selectedTokens];
        for (var index = next.length - 1; index >= 0; index--) {
          if (_normaliseToken(next[index]) == normalised) {
            next.removeAt(index);
            break;
          }
        }
        _selectedTokens = next;
      } else {
        _selectedTokens = [..._selectedTokens, token];
      }
      _errorText = null;
    });
  }

  void _back() {
    if (_step == _WritingStep.brief) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step = _WritingStep.values[_step.index - 1]);
  }

  void _insertSupportWord(String word) {
    final selection = _draftController.selection;
    final start = selection.start < 0 ? _draft.length : selection.start;
    final end = selection.end < 0 ? start : selection.end;
    final before = _draft.substring(0, start);
    final after = _draft.substring(end);
    final needsSpace = before.isNotEmpty && !before.endsWith(' ');
    final insertion = '${needsSpace ? ' ' : ''}$word ';
    final next = '$before$insertion$after';
    final cursor = (before + insertion).length;
    _draftController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
    setState(() => _draft = next);
  }

  Future<void> _getHint() async {
    if (_draft.trim().isEmpty || _isHinting) return;
    final nextTier = _hintTier >= 3 ? 3 : _hintTier + 1;
    setState(() => _isHinting = true);
    try {
      final result = await ref
          .read(lessonAgentServiceProvider)
          .getWritingHint(
            prompt: _task.promptEn,
            targetWords: [..._task.targetConnectors, ..._supportWords],
            draft: _draft,
            tier: nextTier,
          );
      if (!mounted) return;
      setState(() {
        _hint = result.message;
        _hintTier = nextTier;
        _hintsUsed = _hintsUsed < 3 ? _hintsUsed + 1 : _hintsUsed;
        _isHinting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error.toString();
        _isHinting = false;
      });
    }
  }

  Future<void> _submitDraft() async {
    final submission = _draft.trim();
    if (submission.isEmpty || _isGrading) return;
    setState(() {
      _isGrading = true;
      _errorText = null;
      _feedback = null;
      // Enter Review immediately. The learner gets a visible receipt of the
      // exact text being graded instead of seeing a second ambiguous submit
      // step while the network request is in flight.
      _draft = submission;
      _step = _WritingStep.review;
    });
    try {
      final feedback = await ref.read(writingFeedbackGraderProvider)(
        task: _task,
        submission: submission,
        // The task is the source of truth. A learner can change profile
        // controls while an already-open task is on screen; grading this
        // task against a different profile level would produce the wrong
        // rubric and an over-advanced model answer.
        levelBand: _task.levelBand,
      );
      if (!mounted) return;
      setState(() {
        // Keep the exact text that was graded. This protects the review from
        // a TextField change that happens while the network request is in
        // flight and makes the Draft -> Review handoff one atomic receipt.
        _draft = submission;
        _feedback = feedback;
        _isGrading = false;
      });
      // A local/cloud persistence failure must not hide a grade that is already
      // in memory. The learner should see feedback immediately even if sync is
      // temporarily unavailable.
      try {
        _learningStore.saveSubmission(
          taskId: _task.id,
          text: submission,
          feedback: jsonEncode(_writingFeedbackPayload(feedback)),
        );
      } catch (error, stackTrace) {
        debugPrint('Writing feedback persistence failed: $error\n$stackTrace');
      }
      unawaited(_prewarmWritingFeedbackAudio(feedback));
      _recorder.logUser(submission);
      _recorder.logTutor(
        '${feedback.scoreOutOf10.toStringAsFixed(1)}/10. ${feedback.improvedVersion}',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error.toString();
        _isGrading = false;
      });
    }
  }

  Map<String, dynamic> _writingFeedbackPayload(WritingFeedback feedback) => {
    'score_out_of_10': feedback.scoreOutOf10,
    'strengths': feedback.strengths,
    'corrections': [
      for (final correction in feedback.corrections)
        {
          'original': correction.original,
          'fixed': correction.fixed,
          'why': correction.why,
        },
    ],
    'connector_feedback': feedback.connectorFeedback,
    'improved_version': feedback.improvedVersion,
    'next_steps': feedback.nextSteps,
  };

  Future<void> _prewarmWritingFeedbackAudio(WritingFeedback feedback) async {
    final text = feedback.improvedVersion.trim();
    if (text.isEmpty) return;
    await LessonSpeechService.shared.prewarmNarration([
      SpeechItem(
        text: text,
        language: 'fr-FR',
        contentItemId: 'writing:${_task.id}:improved',
      ),
    ]);
  }

  Future<void> _submitRewrite() async {
    if (_rewrite.trim().isEmpty || _isGrading) return;
    setState(() {
      _isGrading = true;
      _errorText = null;
    });
    try {
      final corrections = _feedback?.corrections ?? const [];
      final correction = corrections.isEmpty ? null : corrections.first;
      final result = await ref
          .read(lessonAgentServiceProvider)
          .gradeMicroWriting(
            prompt: correction == null
                ? _task.promptEn
                : 'Rewrite this idea in your own French. Focus on: ${correction.why}',
            targetWords: [
              if (correction != null) correction.fixed,
              ..._task.targetConnectors,
            ],
            submission: _rewrite,
          );
      if (!mounted) return;
      setState(() {
        _rewriteFeedback = result;
        _isGrading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error.toString();
        _isGrading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        leading: IconButton(
          onPressed: _back,
          icon: const Icon(CupertinoIcons.chevron_left),
        ),
        title: Text('Writing studio', style: DesignTokens.display(18)),
        actions: [
          InlineCallActions(controller: _call),
          ReportProblemButton(sessionType: 'Writing: ${_task.title}'),
        ],
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: WebConstrainedView(
        maxWidth: 780,
        child: Stack(
          children: [
            Column(
              children: [
                if (_call.isLive || _call.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: InlineCallStatusCard(
                      controller: _call,
                      listeningLabel:
                          '${ActiveTutor.current.displayName} is ready to help with your draft.',
                      compact: true,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: LessonStageRail(
                    labels: _isConstructionTask
                        ? const ['Brief', 'Build', 'Review']
                        : const [
                            'Brief',
                            'Build',
                            'Draft',
                            'Review',
                            'Rewrite',
                          ],
                    currentIndex: _railIndex,
                  ),
                ),
                Expanded(
                  // Include the feedback phase in the key. The review body
                  // changes from a pending receipt to several result cards
                  // without changing [_step]; a step-only key can preserve a
                  // stale scroll subtree on device during that handoff.
                  child: KeyedSubtree(
                    key: ValueKey(
                      '${_step.name}:${_feedback == null ? 'pending' : 'ready'}',
                    ),
                    child: SizedBox.expand(child: _stepView()),
                  ),
                ),
                if (!keyboardVisible)
                  _Footer(
                    step: _step,
                    draftReady: _draftReady,
                    rewriteReady: _rewrite.trim().isNotEmpty,
                    isLoading: _isGrading,
                    hasFeedback: _feedback != null,
                    hasRewriteFeedback: _rewriteFeedback != null,
                    isConstruction: _isConstructionTask,
                    onNext: _next,
                    onCheckConstruction: _checkConstruction,
                    onSubmit: _submitDraft,
                    onSubmitRewrite: _submitRewrite,
                  ),
              ],
            ),
            if (keyboardVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _KeyboardAccessory(
                  onDismiss: () =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                ),
              ),
            FloatingNotetakerOverlay(state: ref.watch(notetakerStateProvider)),
          ],
        ),
      ),
    );
  }

  Widget _stepView() => switch (_step) {
    _WritingStep.brief => _briefView(),
    _WritingStep.build => _buildView(),
    _WritingStep.draft => _draftView(),
    _WritingStep.review => _reviewView(),
    _WritingStep.rewrite => _rewriteView(),
  };

  Widget _briefView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const _SectionIntro(
          kicker: '1 · THE BRIEF',
          title: 'Know what you want to say',
          body:
              'Writing gets faster when the idea is clear before the first sentence.',
        ),
        const SizedBox(height: 18),
        LearningCard(
          color: DesignTokens.primary.withValues(alpha: 0.12),
          borderColor: DesignTokens.primary.withValues(alpha: 0.45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR TASK',
                style: DesignTokens.label(
                  10,
                ).copyWith(color: DesignTokens.inkSoft, letterSpacing: 1),
              ),
              const SizedBox(height: 10),
              Text(
                _displayPromptFr,
                style: DesignTokens.display(24).copyWith(height: 1.35),
              ),
              const SizedBox(height: 10),
              if (_showEnglish)
                Text(
                  _displayPromptEn,
                  style: DesignTokens.body(16).copyWith(height: 1.4),
                )
              else
                TextButton(
                  onPressed: () => setState(() => _showEnglish = true),
                  style: TextButton.styleFrom(
                    foregroundColor: DesignTokens.ink,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Show English support'),
                ),
            ],
          ),
        ),
        if (_task.examSection != null) ...[
          const SizedBox(height: 12),
          LearningCard(
            color: DesignTokens.primarySoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.checkmark_seal,
                  color: DesignTokens.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_task.examSection} · ${_task.timeLimitMinutes ?? 60} min\n'
                    'Write at least ${_task.minWords} words${_task.maxWords == null ? '' : ' and no more than ${_task.maxWords} words'}.',
                    style: DesignTokens.body(13).copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _FocusList(items: _task.rubricHints),
        const SizedBox(height: 14),
        LearningCard(
          color: DesignTokens.infoSoft,
          child: Row(
            children: [
              Icon(CupertinoIcons.lightbulb, color: DesignTokens.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You will build a supported answer first, then write freely and improve one sentence.',
                  style: DesignTokens.body(15).copyWith(height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildView() {
    if (_isConstructionTask) return _constructionView();
    final words = _supportWords;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const _SectionIntro(
          kicker: '2 · BUILD',
          title: 'Collect your building blocks',
          body:
              'Tap a word if it helps. The goal is not to copy a model answer—it is to make your own sentence quickly.',
        ),
        const SizedBox(height: 16),
        _MiniPrompt(task: _task),
        const SizedBox(height: 14),
        if (words.isNotEmpty) ...[
          Text(
            'USEFUL WORDS',
            style: DesignTokens.label(
              10,
            ).copyWith(color: DesignTokens.mutedDim, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: words
                .map(
                  (word) => ActionChip(
                    label: Text(word),
                    onPressed: () => _insertSupportWord(word),
                    backgroundColor: DesignTokens.surface,
                    side: BorderSide(color: DesignTokens.hairline),
                    labelStyle: DesignTokens.body(
                      12.5,
                      weight: FontWeight.w600,
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
        ],
        _DraftField(
          controller: _draftController,
          label: 'Start your answer',
          text: _draft,
          minWords: _minimumWords,
          onChanged: (value) => setState(() => _draft = value),
        ),
      ],
    );
  }

  Widget _constructionView() {
    final selected = _selectedTokens;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const _SectionIntro(
          kicker: '2 · BUILD',
          title: 'Build it one word at a time',
          body:
              'Choose the French words in the right order. Tap a word again to remove it.',
        ),
        const SizedBox(height: 16),
        _MiniPrompt(task: _task),
        const SizedBox(height: 14),
        LearningCard(
          color: DesignTokens.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selected.isEmpty ? 'YOUR SENTENCE' : selected.join(' '),
                style: DesignTokens.display(22).copyWith(height: 1.35),
              ),
              const SizedBox(height: 8),
              Text(
                '${selected.length}/${_task.targetTokens.length} words selected',
                style: DesignTokens.body(
                  12,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'WORD BANK',
          style: DesignTokens.label(
            10,
          ).copyWith(color: DesignTokens.primary, letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _task.wordBank.map((word) {
            final active = selected.contains(word);
            return ActionChip(
              label: Text(word),
              onPressed: () => _toggleToken(word),
              backgroundColor: active
                  ? DesignTokens.primarySoft
                  : DesignTokens.surface,
              side: BorderSide(
                color: active ? DesignTokens.primary : DesignTokens.hairline,
              ),
              labelStyle: DesignTokens.body(13, weight: FontWeight.w600),
            );
          }).toList(),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 14),
          _ErrorText(text: _errorText!),
        ],
      ],
    );
  }

  Widget _draftView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const _SectionIntro(
          kicker: '3 · WRITE',
          title: 'Now write without training wheels',
          body:
              'Use your own words. If you pause, ask for one hint instead of revealing the whole answer.',
        ),
        const SizedBox(height: 16),
        _MiniPrompt(task: _task),
        const SizedBox(height: 12),
        _DraftField(
          controller: _draftController,
          label: 'Your French draft',
          text: _draft,
          minWords: _minimumWords,
          onChanged: (value) => setState(() {
            _draft = value;
            _hint = null;
          }),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: _isHinting ? null : _getHint,
              icon: Icon(
                _isHinting
                    ? CupertinoIcons.arrow_2_circlepath
                    : CupertinoIcons.lightbulb,
              ),
              label: Text(_hintTier >= 3 ? 'Ask again' : 'Give me a hint'),
            ),
            const Spacer(),
            Text(
              _hintTier == 0 ? 'Hints stay Socratic' : 'Hint $_hintTier of 3',
              style: DesignTokens.body(
                11,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
          ],
        ),
        if (_hint != null) ...[
          const SizedBox(height: 4),
          LearningCard(
            color: DesignTokens.infoSoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.lightbulb,
                  color: DesignTokens.info,
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _hint!,
                    style: DesignTokens.body(13.5).copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_errorText != null) _ErrorText(text: _errorText!),
      ],
    );
  }

  Widget _reviewView() {
    if (_isConstructionTask) return _constructionReviewView();
    final feedback = _feedback;
    if (feedback == null) {
      return _FeedbackPendingBody(
        draft: _draft,
        isLoading: _isGrading,
        errorText: _errorText,
        onRetry: () {
          setState(() {
            _errorText = null;
          });
          unawaited(_submitDraft());
        },
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _SectionIntro(
          kicker: '4 · COACH',
          title: 'Turn feedback into progress',
          body:
              'Your score is only a snapshot. The useful part is the one change you can reuse next time.',
        ),
        const SizedBox(height: 16),
        _WritingResultCard(task: _task, draft: _draft),
        const SizedBox(height: 12),
        _SubmissionTextCard(draft: _draft),
        const SizedBox(height: 12),
        _WritingScoreCard(task: _task, feedback: feedback),
        if (feedback.strengths.isNotEmpty) ...[
          const SizedBox(height: 12),
          _BulletCard(
            label: 'What worked',
            items: feedback.strengths,
            icon: CupertinoIcons.checkmark_circle_fill,
            color: DesignTokens.success,
          ),
        ],
        if (feedback.connectorFeedback.isNotEmpty) ...[
          const SizedBox(height: 12),
          LearningCard(
            color: DesignTokens.infoSoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COACH\'S NOTE',
                  style: DesignTokens.label(
                    10,
                  ).copyWith(color: DesignTokens.info, letterSpacing: 0.8),
                ),
                const SizedBox(height: 8),
                Text(
                  feedback.connectorFeedback,
                  style: DesignTokens.body(13.5).copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
        if (feedback.corrections.isEmpty) ...[
          const SizedBox(height: 12),
          LearningCard(
            color: DesignTokens.successSoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: DesignTokens.success,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No major corrections were detected for this task. Keep the same structure and practise adding one more detail next time.',
                    style: DesignTokens.body(13.5).copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        for (final correction in feedback.corrections) ...[
          const SizedBox(height: 12),
          _CorrectionCard(correction: correction),
        ],
        if (feedback.nextSteps.isNotEmpty) ...[
          const SizedBox(height: 12),
          _BulletCard(
            label: 'Next move',
            items: feedback.nextSteps,
            icon: CupertinoIcons.arrow_up_right_circle_fill,
            color: DesignTokens.primary,
          ),
        ],
        if (feedback.improvedVersion.isNotEmpty) ...[
          const SizedBox(height: 12),
          LearningCard(
            color: DesignTokens.infoSoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'MODEL ANSWER · ${_task.levelBand.toUpperCase()}',
                      style: DesignTokens.label(
                        10,
                      ).copyWith(color: DesignTokens.info, letterSpacing: 0.8),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => LessonSpeechService.shared.speak(
                        items: LessonSpeechService.speechItemsFromText(
                          feedback.improvedVersion,
                        ),
                      ),
                      icon: const Icon(CupertinoIcons.volume_up, size: 18),
                      color: DesignTokens.info,
                      tooltip: 'Hear the improved version',
                    ),
                  ],
                ),
                Text(
                  feedback.improvedVersion,
                  style: DesignTokens.body(16).copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _rewriteView() {
    final corrections = _feedback?.corrections ?? const [];
    final correction = corrections.isEmpty ? null : corrections.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const _SectionIntro(
          kicker: '5 · REWRITE',
          title: 'Use the correction yourself',
          body:
              'Rewrite the important idea in your own French. This short retrieval step is what turns feedback into faster writing next time.',
        ),
        const SizedBox(height: 16),
        if (correction != null) _CorrectionCard(correction: correction),
        const SizedBox(height: 12),
        _DraftField(
          controller: _rewriteController,
          label: 'Your improved sentence',
          text: _rewrite,
          minWords: 1,
          onChanged: (value) => setState(() {
            _rewrite = value;
            _rewriteFeedback = null;
          }),
        ),
        if (_rewriteFeedback != null) ...[
          const SizedBox(height: 12),
          LearningCard(
            color: DesignTokens.successSoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: DesignTokens.success,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_rewriteFeedback!.scoreOutOf10.toStringAsFixed(1)}/10 · ${_rewriteFeedback!.comment}',
                    style: DesignTokens.body(13.5).copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_errorText != null) _ErrorText(text: _errorText!),
      ],
    );
  }

  Widget _constructionReviewView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const _SectionIntro(
          kicker: '3 · CHECK',
          title: 'That order is correct',
          body:
              'You built the sentence exactly. Keep this pattern ready for the next task.',
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.successSoft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: DesignTokens.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _task.targetTokens.join(' '),
                  style: DesignTokens.display(21).copyWith(height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LearningCard(
          color: DesignTokens.surface,
          child: Text(
            _task.promptEn,
            style: DesignTokens.body(
              15,
            ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.step,
    required this.draftReady,
    required this.rewriteReady,
    required this.isLoading,
    required this.hasFeedback,
    required this.hasRewriteFeedback,
    required this.isConstruction,
    required this.onNext,
    required this.onCheckConstruction,
    required this.onSubmit,
    required this.onSubmitRewrite,
  });

  final _WritingStep step;
  final bool draftReady;
  final bool rewriteReady;
  final bool isLoading;
  final bool hasFeedback;
  final bool hasRewriteFeedback;
  final bool isConstruction;
  final VoidCallback onNext;
  final VoidCallback onCheckConstruction;
  final VoidCallback onSubmit;
  final VoidCallback onSubmitRewrite;

  @override
  Widget build(BuildContext context) {
    final isDraft = step == _WritingStep.draft;
    final isRewrite = step == _WritingStep.rewrite;
    final isConstructionBuild = isConstruction && step == _WritingStep.build;
    final isConstructionReview = isConstruction && step == _WritingStep.review;
    final label = switch (step) {
      _WritingStep.brief => 'Build my answer',
      _WritingStep.build =>
        isConstructionBuild ? 'Check answer' : 'Write freely',
      _WritingStep.draft => 'Submit for feedback',
      _WritingStep.review =>
        isConstructionReview
            ? 'Finish lesson'
            : hasFeedback
            ? 'Rewrite one idea'
            : 'Get feedback',
      _WritingStep.rewrite =>
        hasRewriteFeedback ? 'Finish workshop' : 'Check my rewrite',
    };
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        decoration: BoxDecoration(
          color: DesignTokens.canvas,
          border: Border(top: BorderSide(color: DesignTokens.hairline)),
        ),
        child: PrimaryActionButton(
          label: label,
          isLoading: isLoading,
          loadingLabel: isDraft || (step == _WritingStep.review && !hasFeedback)
              ? 'Grading your writing…'
              : 'Checking your rewrite…',
          onPressed: isConstructionBuild
              ? onCheckConstruction
              : isConstructionReview
              ? onNext
              : isDraft
              ? (draftReady ? onSubmit : null)
              : isRewrite
              ? (hasRewriteFeedback
                    ? onNext
                    : (rewriteReady ? onSubmitRewrite : null))
              : step == _WritingStep.review && !hasFeedback
              ? (draftReady ? onSubmit : null)
              : onNext,
          icon: isConstructionBuild
              ? CupertinoIcons.checkmark
              : isRewrite && hasRewriteFeedback
              ? CupertinoIcons.checkmark
              : CupertinoIcons.arrow_right,
        ),
      ),
    );
  }
}

/// The iOS keyboard can consume the fixed writing footer while a learner is
/// entering a draft. Keep one calm, explicit escape hatch above the keyboard;
/// dismissing focus brings the real submit footer back immediately.
class _KeyboardAccessory extends StatelessWidget {
  const _KeyboardAccessory({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
        decoration: BoxDecoration(
          color: DesignTokens.canvas,
          border: Border(top: BorderSide(color: DesignTokens.hairline)),
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: onDismiss,
            icon: const Icon(CupertinoIcons.keyboard_chevron_compact_down),
            label: const Text('Hide keyboard'),
          ),
        ),
      ),
    );
  }
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({
    required this.kicker,
    required this.title,
    required this.body,
  });

  final String kicker;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker,
          style: DesignTokens.label(
            10,
          ).copyWith(color: DesignTokens.primary, letterSpacing: 1),
        ),
        const SizedBox(height: 7),
        Text(title, style: DesignTokens.display(27)),
        const SizedBox(height: 7),
        Text(
          body,
          style: DesignTokens.body(
            15,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.45),
        ),
      ],
    );
  }
}

class _WritingResultCard extends StatelessWidget {
  const _WritingResultCard({required this.task, required this.draft});

  final WritingTask task;
  final String draft;

  @override
  Widget build(BuildContext context) {
    return LearningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR WRITING CARD',
            style: DesignTokens.label(
              10,
            ).copyWith(color: DesignTokens.primary, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          Text(task.displayTitle, style: DesignTokens.display(18)),
          const SizedBox(height: 7),
          Text(
            draft.trim(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// The learner's exact submission is the authoritative review record.
class _SubmissionTextCard extends StatelessWidget {
  const _SubmissionTextCard({required this.draft});

  final String draft;

  @override
  Widget build(BuildContext context) {
    return LearningCard(
      color: DesignTokens.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR SUBMISSION',
            style: DesignTokens.label(
              10,
            ).copyWith(color: DesignTokens.primary, letterSpacing: 0.8),
          ),
          const SizedBox(height: 9),
          SelectableText(
            draft.trim().isEmpty ? 'No text was submitted.' : draft.trim(),
            style: DesignTokens.body(
              16,
            ).copyWith(color: DesignTokens.ink, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _WritingScoreCard extends StatelessWidget {
  const _WritingScoreCard({required this.task, required this.feedback});

  final WritingTask task;
  final WritingFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final breakdown = feedback.scoreBreakdown;
    return LearningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WRITING SCORE',
                      style: DesignTokens.label(10).copyWith(
                        color: DesignTokens.mutedDim,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Level-calibrated review · ${task.levelBand.toUpperCase()}',
                      style: DesignTokens.body(
                        13,
                      ).copyWith(color: DesignTokens.inkSoft),
                    ),
                  ],
                ),
              ),
              Text(
                '${feedback.scoreOutOf10.toStringAsFixed(1)} / 10',
                style: DesignTokens.display(
                  24,
                ).copyWith(color: DesignTokens.primary),
              ),
            ],
          ),
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final item in const [
              ('Task completion', 'task_completion'),
              ('Grammar', 'grammar'),
              ('Vocabulary', 'vocabulary'),
              ('Coherence', 'coherence'),
            ])
              if (breakdown.containsKey(item.$2)) ...[
                _ScoreRow(label: item.$1, score: breakdown[item.$2]!),
                const SizedBox(height: 9),
              ],
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Detailed rubric marks were not returned for this review, but the score and corrections below are still valid.',
              style: DesignTokens.body(
                12.5,
              ).copyWith(color: DesignTokens.mutedDim, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.label, required this.score});

  final String label;
  final double score;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 116,
          child: Text(label, style: DesignTokens.body(12.5)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (score / 10).clamp(0, 1),
              minHeight: 7,
              backgroundColor: DesignTokens.hairline,
              color: DesignTokens.primary,
            ),
          ),
        ),
        const SizedBox(width: 9),
        SizedBox(
          width: 30,
          child: Text(
            score.toStringAsFixed(1),
            textAlign: TextAlign.right,
            style: DesignTokens.body(
              12.5,
              weight: FontWeight.w700,
            ).copyWith(color: DesignTokens.primary),
          ),
        ),
      ],
    );
  }
}

class _MiniPrompt extends StatelessWidget {
  const _MiniPrompt({required this.task});

  final WritingTask task;

  @override
  Widget build(BuildContext context) {
    final isConstruction =
        task.wordBank.isNotEmpty && task.targetTokens.isNotEmpty;
    final isWord = task.type == 'word';
    final promptFr = isConstruction
        ? (isWord ? 'Complète la phrase.' : 'Construis la phrase.')
        : task.promptFr;
    final promptEn = isConstruction && !isWord
        ? task.promptEn.replaceFirst(RegExp(r'^Build:\s*'), '')
        : task.promptEn;
    return LearningCard(
      color: isConstruction
          ? DesignTokens.primary.withValues(alpha: 0.08)
          : null,
      borderColor: isConstruction
          ? DesignTokens.primary.withValues(alpha: 0.3)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isConstruction
                ? (isWord ? 'COMPLETE THE PHRASE' : 'BUILD THE SENTENCE')
                : 'WRITE ABOUT THIS',
            style: DesignTokens.label(
              11,
            ).copyWith(color: DesignTokens.mutedDim, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          Text(
            promptFr,
            style: DesignTokens.display(20).copyWith(height: 1.35),
          ),
          const SizedBox(height: 5),
          Text(
            promptEn,
            style: DesignTokens.body(
              15,
            ).copyWith(color: DesignTokens.mutedDim, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _DraftField extends StatelessWidget {
  const _DraftField({
    required this.controller,
    required this.label,
    required this.text,
    required this.minWords,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String text;
  final int minWords;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final count = text.trim().isEmpty
        ? 0
        : text.trim().split(RegExp(r'\s+')).length;
    return LearningCard(
      padding: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: DesignTokens.label(
                  11,
                ).copyWith(color: DesignTokens.mutedDim, letterSpacing: 0.8),
              ),
              const Spacer(),
              Text(
                '$count / $minWords words',
                style: DesignTokens.body(13, weight: FontWeight.w600).copyWith(
                  color: count >= minWords
                      ? DesignTokens.success
                      : DesignTokens.mutedDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(minHeight: 230),
            decoration: BoxDecoration(
              color: DesignTokens.canvasDim.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DesignTokens.hairline),
            ),
            child: TextField(
              controller: controller,
              maxLines: null,
              minLines: 9,
              onChanged: onChanged,
              style: DesignTokens.body(19).copyWith(height: 1.55),
              cursorColor: DesignTokens.primary,
              decoration: InputDecoration(
                hintText: 'Écris en français…',
                hintStyle: DesignTokens.body(
                  19,
                ).copyWith(color: DesignTokens.muted, height: 1.55),
                contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusList extends StatelessWidget {
  const _FocusList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LearningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A SMALL FOCUS',
            style: DesignTokens.label(
              11,
            ).copyWith(color: DesignTokens.mutedDim, letterSpacing: 0.8),
          ),
          const SizedBox(height: 10),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    CupertinoIcons.checkmark,
                    size: 15,
                    color: DesignTokens.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: DesignTokens.body(15).copyWith(height: 1.4),
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

class _CorrectionCard extends StatelessWidget {
  const _CorrectionCard({required this.correction});

  final ({String original, String fixed, String why}) correction;

  @override
  Widget build(BuildContext context) {
    return LearningCard(
      color: DesignTokens.warningSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ONE USEFUL CORRECTION',
            style: DesignTokens.label(
              10,
            ).copyWith(color: DesignTokens.warning, letterSpacing: 0.8),
          ),
          const SizedBox(height: 10),
          Text(
            correction.original,
            style: DesignTokens.body(14).copyWith(
              decoration: TextDecoration.lineThrough,
              color: DesignTokens.primary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.arrow_down_right,
                size: 17,
                color: DesignTokens.warning,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  correction.fixed,
                  style: DesignTokens.body(15, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (correction.why.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              correction.why,
              style: DesignTokens.body(
                12.5,
              ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _BulletCard extends StatelessWidget {
  const _BulletCard({
    required this.label,
    required this.items,
    required this.icon,
    required this.color,
  });

  final String label;
  final List<String> items;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LearningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: DesignTokens.label(
              10,
            ).copyWith(color: color, letterSpacing: 0.8),
          ),
          const SizedBox(height: 9),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: DesignTokens.body(13.5).copyWith(height: 1.35),
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

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: DesignTokens.body(12).copyWith(color: DesignTokens.danger),
      ),
    );
  }
}

class _FeedbackPendingBody extends StatelessWidget {
  const _FeedbackPendingBody({
    required this.draft,
    required this.isLoading,
    required this.errorText,
    required this.onRetry,
  });

  final String draft;
  final bool isLoading;
  final String? errorText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const _SectionIntro(
          kicker: '4 · COACH',
          title: 'Preparing your feedback',
          body:
              'Your writing was submitted. We are turning it into a score, corrections, and one clear next step.',
        ),
        const SizedBox(height: 18),
        _SubmissionTextCard(draft: draft),
        const SizedBox(height: 12),
        LearningCard(
          color: DesignTokens.infoSoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isLoading)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      CupertinoIcons.exclamationmark_circle,
                      color: DesignTokens.info,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isLoading
                          ? 'The coach is reviewing your draft…'
                          : 'The feedback did not load yet.',
                      style: DesignTokens.body(15, weight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              if (errorText != null && errorText!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  errorText!,
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
                ),
              ],
              if (!isLoading) ...[
                const SizedBox(height: 14),
                PrimaryActionButton(
                  label: 'Try feedback again',
                  icon: CupertinoIcons.arrow_clockwise,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
