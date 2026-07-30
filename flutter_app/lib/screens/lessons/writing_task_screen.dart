import 'dart:async';

import '../../widgets/adaptive/adaptive.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_keys.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/content_models.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/audio_streaming_service.dart';
import '../../services/gemini_live_service.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/session_recorder.dart';
import '../../widgets/ai_voice_disclosure.dart';
import '../../widgets/floating_notetaker.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../pathway/pathway_writing_screen.dart' show WritingStageResult;

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

class _WritingTaskScreenState extends ConsumerState<WritingTaskScreen> {
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
  // draft behind a grey scrim.
  GeminiLiveService? _gemini;
  AudioStreamingService? _audio;
  bool _callConnecting = false;
  bool _callActive = false;
  bool _callMuted = false;
  bool _tutorSpeaking = false;
  String? _callError;
  String? _lastTutorLine;

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

  Future<void> _toggleCall() async {
    if (_callActive || _callConnecting) {
      _endCall();
      return;
    }
    final accepted = await AiVoiceDisclosure.ensureAccepted(context);
    if (!mounted || !accepted) return;
    LessonSpeechService.shared.deactivate();
    setState(() {
      _callConnecting = true;
      _callError = null;
      _lastTutorLine = null;
    });
    final connected = await _connectLive();
    if (!mounted) return;
    if (!connected) {
      setState(() {
        _callConnecting = false;
        _callError = "Couldn't connect. Check your connection and try again.";
      });
      return;
    }
    final granted = await _audio!.requestPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _callConnecting = false;
        _callError = 'Microphone permission denied';
      });
      _gemini?.disconnect();
      _gemini = null;
      return;
    }
    await _audio!.startStreaming(onChunk: _gemini!.sendAudioChunk);
    if (!mounted) return;
    setState(() {
      _callConnecting = false;
      _callActive = true;
    });
    _lastSyncedContent = _content;
    _draftSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _syncDraftIfChanged();
    });
  }

  /// Silent context update, not a real conversational turn — Marie should
  /// absorb the latest draft without commenting on it or replying to this
  /// specific message, same "app note, not the student" convention used for
  /// call kickoffs elsewhere (see session_screen.dart). Only fires when the
  /// draft actually changed since the last send.
  void _syncDraftIfChanged() {
    if (_content == _lastSyncedContent) return;
    _lastSyncedContent = _content;
    _gemini?.sendText(
      '(Note from the app, not the student: this is a silent background '
      "update of the student's current draft, automatically sent while they "
      'type — it is NOT a message from the student and does not need a '
      'reply. Do not comment on it or acknowledge it in any way unless the '
      'student explicitly asks you to read, check, or comment on their '
      "draft — if they do ask, answer only what they asked, nothing extra.\n\n"
      "STUDENT'S CURRENT DRAFT:\n${_content.trim().isEmpty ? '(nothing written yet)' : _content.trim()})",
    );
  }

  Future<bool> _connectLive() async {
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
    final completer = Completer<bool>();
    final audio = AudioStreamingService();
    final gemini = GeminiLiveService(
      apiKey: ApiKeys.geminiKey,
      sessionType: LiveSessionType.writingGuide,
      lessonContext: buf.toString(),
      autoReconnect: false,
    );
    _audio = audio;
    _gemini = gemini;

    gemini.onConnected = () {
      if (!completer.isCompleted) completer.complete(true);
    };
    gemini.onError = (msg) {
      if (!completer.isCompleted) {
        completer.complete(false);
        return;
      }
      if (mounted) setState(() => _callError = msg);
    };
    gemini.onDisconnected = () {
      if (!completer.isCompleted) {
        completer.complete(false);
        return;
      }
      if (mounted) setState(() => _callActive = false);
    };
    gemini.onUserTranscript = (text) {};
    gemini.onTutorTranscript = (text) {
      if (!mounted) return;
      setState(() => _lastTutorLine = text);
    };
    gemini.onAudioChunk = (bytes) {
      audio.isOutputActive = true;
      _tutorSpeaking = true;
      audio.playAudioChunk(bytes);
    };
    gemini.onTurnComplete = () {
      audio.isOutputActive = false;
      if (mounted) setState(() => _tutorSpeaking = false);
    };

    gemini.connect();
    final connected = await completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => false,
    );
    if (!connected) {
      gemini.disconnect();
      await audio.dispose();
      _gemini = null;
      _audio = null;
    }
    return connected;
  }

  Future<void> _toggleMute() async {
    if (_audio == null) return;
    if (_callMuted) {
      setState(() => _callMuted = false);
      await _audio!.startStreaming(onChunk: _gemini!.sendAudioChunk);
    } else {
      await _audio!.stopStreaming();
      if (mounted) setState(() => _callMuted = true);
    }
  }

  void _endCall() {
    _draftSyncTimer?.cancel();
    _draftSyncTimer = null;
    _audio?.stopStreaming();
    _audio?.dispose();
    _gemini?.disconnect();
    _audio = null;
    _gemini = null;
    setState(() {
      _callActive = false;
      _callConnecting = false;
      _callMuted = false;
      _tutorSpeaking = false;
    });
  }

  @override
  void dispose() {
    _logMinutes();
    _finishSession();
    _textController.dispose();
    _draftSyncTimer?.cancel();
    _audio?.stopStreaming();
    _audio?.dispose();
    _gemini?.disconnect();
    super.dispose();
  }

  void _logMinutes() {
    final minutes = DateTime.now().difference(_sessionStart).inMinutes;
    if (minutes <= 0 || _content.isEmpty) return;
    ref.read(learningStoreProvider).markHabit('writing', minutes: minutes);
  }

  void _finishSession() {
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.toString();
        _isGrading = false;
      });
    }
  }

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
        actions: [
          if (_callActive) ...[
            IconButton(
              tooltip: _callMuted ? 'Unmute' : 'Mute',
              onPressed: _toggleMute,
              icon: Icon(
                _callMuted ? CupertinoIcons.mic_slash_fill : CupertinoIcons.mic_fill,
                color: DesignTokens.slateDim,
              ),
            ),
          ],
          IconButton(
            tooltip: _callActive
                ? 'End call'
                : _callConnecting
                ? 'Connecting…'
                : 'Talk with Marie',
            onPressed: _callConnecting ? null : _toggleCall,
            icon: _callConnecting
                ? const SizedBox.square(
                    dimension: 20,
                    child: PSProgressIndicator(),
                  )
                : Icon(
                    CupertinoIcons.phone_fill,
                    color: _callActive ? DesignTokens.success : DesignTokens.primary,
                  ),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            children: [
              if (_callActive || _callConnecting || _callError != null) ...[
                _callStatusCard(),
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
              PasseportPrimaryButton(
                label: _feedback == null ? 'Submit for grading' : 'Re-submit',
                onPressed: (_isGrading || _wordCount < 5) ? null : _submit,
              ),
              if (widget.showFinishButton && _feedback != null) ...[
                const SizedBox(height: 12),
                PasseportPrimaryButton(
                  label: 'Finish',
                  icon: CupertinoIcons.checkmark,
                  onPressed: _finish,
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
          FloatingNotetakerOverlay(state: ref.watch(notetakerStateProvider)),
        ],
      ),
    );
  }

  void _finish() {
    final feedback = _feedback;
    if (feedback == null) return;
    Navigator.of(context).pop(
      StageOutcome.completed(
        WritingStageResult(score: feedback.scoreOutOf10),
      ),
    );
  }

  void _skip() {
    Navigator.of(
      context,
    ).pop(const StageOutcome<WritingStageResult>.skipped());
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
                          style: DesignTokens.body(
                            12.5,
                          ).copyWith(color: DesignTokens.slateDim, height: 1.35),
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

  // -- Call status (inline, non-blocking) --

  Widget _callStatusCard() {
    return PasseportCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.phone_fill,
            size: 18,
            color: _callError != null ? DesignTokens.primary : DesignTokens.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _callError != null
                      ? _callError!
                      : _callConnecting
                      ? 'Connecting to Marie…'
                      : _tutorSpeaking
                      ? 'Marie is speaking…'
                      : 'Listening. Keep writing, she can hear you.',
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w500,
                  ).copyWith(color: DesignTokens.inkSoft),
                ),
                if (_lastTutorLine != null && _callError == null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _lastTutorLine!,
                    style: DesignTokens.body(
                      12.5,
                    ).copyWith(color: DesignTokens.slateDim, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
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
