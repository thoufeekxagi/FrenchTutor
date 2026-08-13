import 'dart:async';

import '../../widgets/adaptive/adaptive.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/content_models.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/session_recorder.dart';
import '../../widgets/floating_notetaker.dart';
import '../../widgets/inline_call_bar.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/web/web_constrained_view.dart';

/// Popped by this screen's `_finish()` — a plain score/hints carrier.
class WritingStageResult {
  WritingStageResult({this.score, this.hintsUsed = 0});
  final double? score;
  final int hintsUsed;
}

class WritingTaskScreen extends ConsumerStatefulWidget {
  const WritingTaskScreen({
    super.key,
    required this.task,
    this.showFinishButton = false,
  });

  final WritingTask task;

  /// True when this screen is a step in a larger flow (a mission) that needs
  /// the learner to explicitly finish and hand back a graded result — adds a
  /// "Skip" leading button and, once feedback exists, a "Finish" button that
  /// pops a `StageOutcome<WritingStageResult>`. False (the default, used by
  /// the standalone Writing lab) shows neither; the learner just backs out
  /// whenever they're done. Both modes are otherwise the exact same screen —
  /// same prompt/rubric card, connectors, editor, live call, feedback — so a
  /// mission's writing step never looks or behaves differently from the lab.
  final bool showFinishButton;

  @override
  ConsumerState<WritingTaskScreen> createState() => _WritingTaskScreenState();
}

class _WritingTaskScreenState extends ConsumerState<WritingTaskScreen>
    with WidgetsBindingObserver {
  bool _showEnglish = false;
  String _content = '';
  final _textController = TextEditingController();
  bool _isGrading = false;
  WritingFeedback? _feedback;
  String? _errorText;
  final DateTime _sessionStart = DateTime.now();

  // Talk-with-Marie call — inline, not a modal: the editor stays visible and
  // editable the whole time the call is live, so the learner can keep
  // writing while she talks them through it, instead of a sheet blocking the
  // draft behind a grey scrim. Same InlineCallController every other
  // reading/exercise screen with a live-call button now uses.
  late final InlineCallController _call;

  // The initial connect message only ever carries a one-time snapshot of
  // the draft — without this, Marie has no idea what's been typed since the
  // call started, so asking her "can you see what I wrote?" got a made-up
  // answer. Resent only when the draft actually changed, so a student who
  // stops typing doesn't get silently re-sent the same text forever.
  Timer? _draftSyncTimer;
  String _lastSyncedContent = '';

  late final SessionRecorder _recorder;

  WritingTask get task => widget.task;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _call = InlineCallController(
      sessionType: LiveSessionType.writingGuide,
      lessonContext: _buildLiveLessonContext,
      learningStoreForProfile: ref.read(learningStoreProvider),
      onChanged: () {
        if (!mounted) return;
        setState(() {});
        if (_call.active && _draftSyncTimer == null) {
          _lastSyncedContent = _content;
          _draftSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) {
            _syncDraftIfChanged();
          });
        } else if (!_call.active && _draftSyncTimer != null) {
          _draftSyncTimer?.cancel();
          _draftSyncTimer = null;
        }
      },
      // Without this, "Talk with Marie" here counted for nothing — the
      // call's conversation was displayed live but never logged, so it
      // never contributed to this session's auto-generated review note.
      // Wrapped in closures (not direct tear-offs) since `_recorder` isn't
      // assigned yet at this point in initState — safe because these only
      // ever run later, once a call is actually connected.
      onUserTranscript: (text) => _recorder.logUser(text),
      onTutorTranscript: (text) => _recorder.logTutor(text),
    );
    // Deferred to after this frame — setting currentContext synchronously
    // here notifies FloatingNotetakerOverlay listeners mounted elsewhere
    // (e.g. the tab-bar root) while this screen is still in its own initial
    // build, which Flutter disallows.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Writing';
    });
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'writing',
      topic: task.title,
    );
  }

  /// P0.4 — locking the phone or backgrounding the app mid-call previously
  /// left the mic streaming into a pocket, and the call had no auto-reconnect
  /// at all, so a socket drop while backgrounded just silently ended the
  /// call — the "it turns off in pocket" bug. Same contract as every other
  /// live screen now, via the shared controller.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _call.handleAppLifecycle(state);
  }

  String get _lessonContext =>
      ref.read(contentServiceProvider).writingTaskContext(task);

  int get _wordCount {
    if (_content.trim().isEmpty) return 0;
    return _content.trim().split(RegExp(r'\s+')).length;
  }

  List<Connector> get _targetConnectorObjects {
    final pack = ref.read(contentServiceProvider).connectors();
    if (pack == null) return [];
    return pack.connectors
        .where((c) => task.targetConnectors.contains(c.id))
        .toList();
  }

  bool _connectorUsed(Connector connector) {
    final stem = connector.fr.toLowerCase().split('...').first;
    return _content.toLowerCase().contains(stem);
  }

  /// Marie's live-call context is rebuilt fresh on every connect — unlike a
  /// static lesson context, this one has to carry the CURRENT draft and any
  /// existing feedback, both of which change while the screen is open.
  String _buildLiveLessonContext() {
    final buf = StringBuffer(_lessonContext);
    buf.writeln();
    buf.writeln(
      _content.trim().isEmpty
          ? "STUDENT'S CURRENT DRAFT: (nothing written yet)"
          : "STUDENT'S CURRENT DRAFT:\n${_content.trim()}",
    );
    if (_feedback != null) {
      buf.writeln('EXISTING GRADED FEEDBACK: ${_feedback!.improvedVersion}');
    }
    return buf.toString();
  }

  /// Silent context update, not a real conversational turn — Marie should
  /// absorb the latest draft without commenting on it or replying to this
  /// specific message, same "app note, not the student" convention used for
  /// call kickoffs elsewhere (see session_screen.dart). Only fires when the
  /// draft actually changed since the last send.
  void _syncDraftIfChanged() {
    if (_content == _lastSyncedContent) return;
    _lastSyncedContent = _content;
    _call.gemini?.sendText(
      '(Note from the app, not the student: this is a silent background '
      "update of the student's current draft, automatically sent while they "
      'type. It is NOT a message from the student and does not need a '
      'reply. Do not comment on it or acknowledge it in any way unless the '
      'student explicitly asks you to read, check, or comment on their '
      "draft. If they do ask, answer only what they asked, nothing extra.\n\n"
      "STUDENT'S CURRENT DRAFT:\n${_content.trim().isEmpty ? '(nothing written yet)' : _content.trim()})",
      // The API-level fix: without this, Gemini Live treated every 8-second
      // sync as a completed user turn and answered it regardless of what
      // this text said — this is what made Marie "keep talking" unprompted.
      expectReply: false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logMinutes();
    // Only if grading never happened — a graded submission already finished
    // the session the moment `_submit()` succeeded, see there for why.
    if (!_sessionFinished) _finishSession();
    _textController.dispose();
    _draftSyncTimer?.cancel();
    _call.dispose();
    super.dispose();
  }

  void _logMinutes() {
    final minutes = DateTime.now().difference(_sessionStart).inMinutes;
    if (minutes <= 0 || _content.isEmpty) return;
    ref.read(learningStoreProvider).markHabit('writing', minutes: minutes);
  }

  void _finishSession() {
    _sessionFinished = true;
    if (_content.trim().isEmpty) return;
    final feedback = _feedback;
    _recorder.finish(
      summary: feedback != null
          ? 'Wrote "${task.title}", scored ${feedback.scoreOutOf10.toStringAsFixed(1)}/10.'
          : 'Drafted "${task.title}" without submitting for grading.',
    );
  }

  Future<void> _submit() async {
    setState(() {
      _isGrading = true;
      _errorText = null;
    });
    final submittedText = _content;
    try {
      final level = ref.read(learningStoreProvider).profile().level;
      final result = await ref
          .read(lessonAgentServiceProvider)
          .gradeWriting(
            task: task,
            submission: submittedText,
            levelBand: level,
          );
      if (!mounted) return;
      setState(() {
        _feedback = result;
        _isGrading = false;
      });
      ref
          .read(learningStoreProvider)
          .saveSubmission(
            taskId: task.id,
            text: submittedText,
            feedback: result.improvedVersion,
          );
      _recorder.logUser(submittedText);
      _recorder.logTutor(
        '${result.scoreOutOf10.toStringAsFixed(1)}/10. ${result.improvedVersion}',
      );
      // Grading IS completion — submitting marks the writing mission done
      // right here, not only once the learner later taps "Done"/leaves the
      // screen. A call left running mid-submit is over too: Marie's job was
      // coaching toward this submission, and it just happened.
      if (_call.isLive) unawaited(_call.end());
      _finishSession();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.toString();
        _isGrading = false;
      });
    }
  }

  /// Once grading succeeds the writing mission is already complete (see
  /// `_submit()`) — this only guards `dispose()` from double-logging a
  /// second session-finish for the same screen visit.
  bool _sessionFinished = false;

  /// Standalone-lab mode's post-feedback completion — was "Try a new prompt"
  /// before, which silently chained straight into another task with no clear
  /// "you're done" moment, reading as confusing rather than a finish step.
  /// Just closes this session out cleanly; "New writing practice" back on
  /// the lab screen is already the way to start another one.
  void _doneInLab() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.parchmentDim,
      appBar: AppBar(
        title: Text(task.title, style: DesignTokens.display(18)),
        backgroundColor: DesignTokens.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: widget.showFinishButton ? 72 : null,
        leading: widget.showFinishButton
            ? TextButton(
                onPressed: _skip,
                child: Text(
                  'Skip',
                  style: DesignTokens.body(
                    14,
                  ).copyWith(color: DesignTokens.slateDim),
                ),
              )
            : null,
        actions: [InlineCallActions(controller: _call)],
      ),
      body: WebConstrainedView(
        maxWidth: 920,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              children: [
                if (_call.isLive || _call.error != null) ...[
                  InlineCallStatusCard(
                    controller: _call,
                    listeningLabel:
                        'Listening. Keep writing, she can hear you.',
                  ),
                  const SizedBox(height: 16),
                ],
                _promptCard(),
                const SizedBox(height: 16),
                _connectorsCard(),
                const SizedBox(height: 16),
                _editorCard(),
                if (_isGrading) ...[
                  const SizedBox(height: 16),
                  const Center(child: PSProgressIndicator()),
                ],
                if (_feedback != null) ...[
                  const SizedBox(height: 16),
                  _feedbackCard(_feedback!),
                ],
                if (_errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorText!,
                    style: DesignTokens.mono(
                      11,
                    ).copyWith(color: DesignTokens.primary),
                  ),
                ],
                const SizedBox(height: 16),
                if (_feedback == null)
                  PasseportPrimaryButton(
                    label: 'Submit for grading',
                    onPressed: (_isGrading || _wordCount < 5) ? null : _submit,
                  )
                else
                  PasseportPrimaryButton(
                    label: 'Done',
                    icon: CupertinoIcons.checkmark,
                    onPressed: widget.showFinishButton ? _finish : _doneInLab,
                  ),
                const SizedBox(height: 24),
              ],
            ),
            FloatingNotetakerOverlay(state: ref.watch(notetakerStateProvider)),
          ],
        ),
      ),
    );
  }

  void _finish() {
    final feedback = _feedback;
    if (feedback == null) return;
    Navigator.of(context).pop(
      StageOutcome.completed(WritingStageResult(score: feedback.scoreOutOf10)),
    );
  }

  void _skip() {
    Navigator.of(context).pop(const StageOutcome<WritingStageResult>.skipped());
  }

  // -- Feedback card --

  Widget _feedbackCard(WritingFeedback feedback) {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const KickerText('Feedback', color: DesignTokens.slateDim),
              const Spacer(),
              Text(
                '${feedback.scoreOutOf10.toStringAsFixed(1)} / 10',
                style: DesignTokens.display(
                  20,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.primary),
              ),
            ],
          ),
          if (feedback.strengths.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Strengths',
              style: DesignTokens.body(14, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final s in feedback.strengths)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      CupertinoIcons.checkmark,
                      size: 14,
                      color: DesignTokens.success,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        s,
                        style: DesignTokens.body(
                          14,
                        ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (feedback.corrections.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Corrections',
              style: DesignTokens.body(14, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final c in feedback.corrections)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          c.original,
                          style: DesignTokens.body(13.5).copyWith(
                            color: DesignTokens.primary,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          CupertinoIcons.arrow_right,
                          size: 11,
                          color: DesignTokens.slate,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          c.fixed,
                          style: DesignTokens.body(
                            13.5,
                            weight: FontWeight.w600,
                          ).copyWith(color: DesignTokens.info),
                        ),
                      ],
                    ),
                    if (c.why.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          c.why,
                          style: DesignTokens.body(12.5).copyWith(
                            color: DesignTokens.slateDim,
                            height: 1.35,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
          if (feedback.connectorFeedback.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Connectors',
              style: DesignTokens.body(14, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              feedback.connectorFeedback,
              style: DesignTokens.body(
                14,
              ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
            ),
          ],
          if (feedback.nextSteps.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Next steps',
              style: DesignTokens.body(14, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final step in feedback.nextSteps)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      CupertinoIcons.arrow_up_right_circle_fill,
                      size: 14,
                      color: DesignTokens.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        step,
                        style: DesignTokens.body(
                          14,
                        ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (feedback.improvedVersion.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Improved version',
                  style: DesignTokens.body(14, weight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    CupertinoIcons.speaker_2_fill,
                    size: 18,
                    color: DesignTokens.primary,
                  ),
                  onPressed: () => LessonSpeechService.shared.speak(
                    items: LessonSpeechService.speechItemsFromText(
                      feedback.improvedVersion,
                    ),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                ),
              ],
            ),
            Text(
              feedback.improvedVersion,
              style: DesignTokens.body(
                15,
              ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  // -- Prompt card --

  Widget _promptCard() {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KickerText('Prompt', color: DesignTokens.slateDim),
          const SizedBox(height: 8),
          Text(task.promptFr, style: DesignTokens.body(14)),
          const SizedBox(height: 6),
          if (_showEnglish)
            Text(
              task.promptEn,
              style: DesignTokens.body(
                12.5,
              ).copyWith(color: DesignTokens.slateDim),
            )
          else
            TextButton(
              onPressed: () => setState(() => _showEnglish = true),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                'Show English',
                style: DesignTokens.mono(
                  10.5,
                  weight: FontWeight.w500,
                ).copyWith(color: DesignTokens.primary),
              ),
            ),
          if (task.rubricHints.isNotEmpty) ...[
            const SizedBox(height: 6),
            Divider(color: DesignTokens.hairline, height: 1),
            const SizedBox(height: 8),
            for (final hint in task.rubricHints)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(color: DesignTokens.info, fontSize: 13),
                    ),
                    Expanded(
                      child: Text(
                        hint,
                        style: DesignTokens.mono(
                          10.5,
                        ).copyWith(color: DesignTokens.slateDim),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // -- Connectors card --

  Widget _connectorsCard() {
    final connectors = _targetConnectorObjects;
    if (connectors.isEmpty) return const SizedBox.shrink();

    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KickerText('Target connectors', color: DesignTokens.slateDim),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: connectors.map((c) {
              final used = _connectorUsed(c);
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: used
                      ? DesignTokens.info
                      : DesignTokens.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  c.fr,
                  style: DesignTokens.mono(
                    10.5,
                    weight: FontWeight.w500,
                  ).copyWith(color: used ? Colors.white : DesignTokens.primary),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // -- Editor card --

  Widget _editorCard() {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const KickerText('Your response', color: DesignTokens.slateDim),
              const Spacer(),
              Text(
                '$_wordCount / ${task.minWords} words',
                style: DesignTokens.mono(10.5).copyWith(
                  color: _wordCount >= task.minWords
                      ? DesignTokens.info
                      : DesignTokens.slateDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 180),
            decoration: BoxDecoration(
              color: DesignTokens.parchmentDim,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _textController,
              onChanged: (val) => setState(() => _content = val),
              maxLines: null,
              minLines: 8,
              style: DesignTokens.body(13.5),
              cursorColor: DesignTokens.primary,
              decoration: InputDecoration(
                hintText: 'Write your response here...',
                hintStyle: DesignTokens.body(
                  13.5,
                ).copyWith(color: DesignTokens.slate),
                contentPadding: const EdgeInsets.all(12),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
