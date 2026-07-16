import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter/cupertino.dart' show CupertinoIcons;

import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/session_recorder.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/floating_notetaker.dart';

class WritingStageResult {
  WritingStageResult({this.score});
  final double? score;
}

/// Daily Pathway stage 4 — plain typed micro-writing, no live call. Writing needs typed
/// accuracy (spelling, connectors), not voice, so this deliberately has none of the
/// audio-session complexity the other stages do. Ported from PathwayWritingView.swift.
class PathwayWritingScreen extends ConsumerStatefulWidget {
  const PathwayWritingScreen({super.key, required this.targetWords});

  final List<VocabEntry> targetWords;

  @override
  ConsumerState<PathwayWritingScreen> createState() =>
      _PathwayWritingScreenState();
}

class _PathwayWritingScreenState extends ConsumerState<PathwayWritingScreen> {
  final _sessionId = const Uuid().v4();
  late final SessionRecorder _recorder;
  final _controller = TextEditingController();

  String _submission = '';
  bool _isGrading = false;
  MicroWritingFeedback? _feedback;
  String? _errorText;

  String get _prompt =>
      'Write one or two sentences using: ${widget.targetWords.map((e) => e.fr).join(", ")}';

  @override
  void initState() {
    super.initState();
    // Deferred to after this frame — setting currentContext synchronously here notifies
    // FloatingNotetakerOverlay listeners (mounted elsewhere, e.g. the tab-bar root) while
    // THIS screen is still in its own initial build, which Flutter disallows
    // ("setState() or markNeedsBuild() called during build").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Writing';
    });
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'writing',
      topic: 'Writing',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isGrading = true;
      _errorText = null;
    });
    final targets = widget.targetWords.map((e) => e.fr).toList();
    final text = _submission;
    try {
      final result = await LessonAgentService.shared.gradeMicroWriting(
        prompt: _prompt,
        targetWords: targets,
        submission: text,
      );
      if (!mounted) return;
      setState(() {
        _feedback = result;
        _isGrading = false;
      });
      ref
          .read(learningStoreProvider)
          .saveSubmission(
            taskId: 'pathway_$_sessionId',
            text: text,
            feedback: result.comment,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = '$e';
        _isGrading = false;
      });
    }
  }

  void _finish() {
    final feedback = _feedback;
    if (feedback != null) {
      _recorder.logUser(_submission);
      _recorder.logTutor(feedback.comment);
      _recorder.finish(
        summary:
            'Scored ${feedback.scoreOutOf10.toStringAsFixed(1)}/10 on: $_prompt',
      );
    }
    // Completed only when something was actually submitted and graded.
    final outcome = feedback != null
        ? StageOutcome.completed(
            WritingStageResult(score: feedback.scoreOutOf10),
          )
        : const StageOutcome<WritingStageResult>.paused(reason: 'cancelled');
    Navigator.of(context).pop(outcome);
  }

  void _skip() {
    Navigator.of(context).pop(const StageOutcome<WritingStageResult>.skipped());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text('Writing', style: DesignTokens.display(18)),
        backgroundColor: DesignTokens.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 72,
        leading: TextButton(
          onPressed: _skip,
          child: Text(
            'Skip',
            style: DesignTokens.body(14).copyWith(color: DesignTokens.slateDim),
          ),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignTokens.contentMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.screenMargin,
                    DesignTokens.space3,
                    DesignTokens.screenMargin,
                    DesignTokens.space5,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const KickerText(
                        'Writing evidence',
                        color: DesignTokens.info,
                      ),
                      const SizedBox(height: DesignTokens.space2),
                      Text(
                        'Use today’s words in context',
                        style: DesignTokens.display(24),
                      ),
                      const SizedBox(height: DesignTokens.space2),
                      Text(
                        _prompt,
                        style: DesignTokens.body(
                          15,
                        ).copyWith(color: DesignTokens.slateDim, height: 1.4),
                      ),
                      const SizedBox(height: DesignTokens.space5),
                      if (_feedback == null) ...[
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(minHeight: 160),
                            decoration: BoxDecoration(
                              color: DesignTokens.surface,
                              borderRadius: BorderRadius.circular(
                                DesignTokens.radiusCard,
                              ),
                              border: Border.all(color: DesignTokens.hairline),
                            ),
                            child: TextField(
                              controller: _controller,
                              onChanged: (value) =>
                                  setState(() => _submission = value),
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              style: DesignTokens.body(
                                16,
                              ).copyWith(height: 1.45),
                              cursorColor: DesignTokens.primary,
                              decoration: InputDecoration(
                                hintText:
                                    'Write one or two sentences in French…',
                                hintStyle: DesignTokens.body(
                                  15,
                                ).copyWith(color: DesignTokens.slate),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(
                                  DesignTokens.space4,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_errorText != null) ...[
                          const SizedBox(height: DesignTokens.space3),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(DesignTokens.space3),
                            decoration: BoxDecoration(
                              color: DesignTokens.primarySoft,
                              borderRadius: BorderRadius.circular(
                                DesignTokens.radiusMedium,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  CupertinoIcons.exclamationmark_circle_fill,
                                  color: DesignTokens.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: DesignTokens.space2),
                                Expanded(
                                  child: Text(
                                    _errorText!,
                                    style: DesignTokens.body(13).copyWith(
                                      color: DesignTokens.inkSoft,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: DesignTokens.space3),
                        PasseportPrimaryButton(
                          label: _isGrading
                              ? 'Checking your writing…'
                              : 'Check writing',
                          icon: _isGrading
                              ? null
                              : CupertinoIcons.paperplane_fill,
                          onPressed: (_isGrading || _submission.trim().isEmpty)
                              ? null
                              : _submit,
                        ),
                      ] else ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(DesignTokens.space5),
                          decoration: BoxDecoration(
                            color: DesignTokens.successSoft,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusCard,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                CupertinoIcons.checkmark_circle_fill,
                                color: DesignTokens.success,
                                size: 28,
                              ),
                              const SizedBox(height: DesignTokens.space3),
                              Text(
                                'Feedback ready',
                                style: DesignTokens.display(22),
                              ),
                              const SizedBox(height: DesignTokens.space2),
                              Text(
                                '${_feedback!.scoreOutOf10.toStringAsFixed(1)} / 10',
                                style: DesignTokens.display(
                                  28,
                                ).copyWith(color: DesignTokens.success),
                              ),
                              const SizedBox(height: DesignTokens.space3),
                              Text(
                                _feedback!.comment,
                                style: DesignTokens.body(
                                  15,
                                ).copyWith(height: 1.45),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        PasseportPrimaryButton(
                          label: 'Finish writing',
                          icon: CupertinoIcons.checkmark,
                          onPressed: _finish,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          FloatingNotetakerOverlay(state: ref.watch(notetakerStateProvider)),
        ],
      ),
    );
  }
}
