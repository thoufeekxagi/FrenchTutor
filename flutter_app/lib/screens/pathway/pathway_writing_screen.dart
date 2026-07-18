import 'dart:async';

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
  WritingStageResult({this.score, this.hintsUsed = 0});
  final double? score;
  final int hintsUsed;
}

/// How long a pause in typing has to last before we treat it as "the learner
/// finished a thought" and it's worth spending a hint call — not every
/// keystroke. Long enough that normal typing rhythm never fires it, short
/// enough that it still feels responsive once they actually stop.
const _hintDebounceDelay = Duration(milliseconds: 1400);

/// Below this many words a hint would have nothing real to react to — the
/// draft is still just a word or two, not a checkable thought.
const _minWordsForHint = 3;

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

  Timer? _hintDebounce;
  String _textAtLastHintCheck = '';
  int _hintTier = 0;
  int _hintsUsed = 0;
  WritingHint? _hint;
  bool _isFetchingHint = false;

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
    _hintDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onDraftChanged(String value) {
    setState(() => _submission = value);
    _hintDebounce?.cancel();
    if (_feedback != null) return; // already verified — stop coaching
    _hintDebounce = Timer(_hintDebounceDelay, _maybeOfferHint);
  }

  Future<void> _maybeOfferHint() async {
    if (!mounted || _feedback != null || _isFetchingHint) return;
    final trimmed = _submission.trim();
    final wordCount = trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length;
    if (wordCount < _minWordsForHint) {
      if (_hint != null) setState(() => _hint = null);
      return;
    }
    if (trimmed == _textAtLastHintCheck) return; // nothing changed since last look

    setState(() {
      _isFetchingHint = true;
      _hintTier = 1; // a fresh pause always starts back at the gentlest rung
    });
    await _requestHint();
    _textAtLastHintCheck = trimmed;
  }

  Future<void> _requestNextHintTier() async {
    if (_isFetchingHint || _hintTier >= 3) return;
    setState(() {
      _isFetchingHint = true;
      _hintTier += 1;
    });
    await _requestHint();
  }

  Future<void> _requestHint() async {
    try {
      final hint = await LessonAgentService.shared.getWritingHint(
        prompt: _prompt,
        targetWords: widget.targetWords.map((e) => e.fr).toList(),
        draft: _submission,
        tier: _hintTier,
      );
      if (!mounted) return;
      setState(() {
        _hint = hint;
        _hintsUsed += 1;
        _isFetchingHint = false;
      });
    } catch (_) {
      // A hint is a nice-to-have coaching aid, not the graded path — a
      // failure here should never block or interrupt writing.
      if (!mounted) return;
      setState(() => _isFetchingHint = false);
    }
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
            WritingStageResult(
              score: feedback.scoreOutOf10,
              hintsUsed: _hintsUsed,
            ),
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
                              onChanged: _onDraftChanged,
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
                        if (_isFetchingHint || _hint != null) ...[
                          const SizedBox(height: DesignTokens.space3),
                          _HintCard(
                            hint: _hint,
                            isLoading: _isFetchingHint,
                            canAskForMore: _hintTier < 3,
                            onAskForMore: _requestNextHintTier,
                          ),
                        ],
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
                          label: _isGrading ? 'Verifying…' : 'Verify',
                          icon: _isGrading
                              ? null
                              : CupertinoIcons.checkmark_seal,
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
                              if (_hintsUsed > 0) ...[
                                const SizedBox(height: DesignTokens.space2),
                                Text(
                                  _hintsUsed == 1
                                      ? 'Used 1 hint — counted as guided, not unaided.'
                                      : 'Used $_hintsUsed hints — counted as guided, not unaided.',
                                  style: DesignTokens.body(12).copyWith(
                                    color: DesignTokens.slateDim,
                                  ),
                                ),
                              ],
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

/// A single rung of Socratic coaching, shown after a typing pause. Never
/// states the fix — only a nudge, escalating one rung per tap. Distinct from
/// [_feedback] below it: this is ambient and ungraded, Verify is explicit
/// and scored.
class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.hint,
    required this.isLoading,
    required this.canAskForMore,
    required this.onAskForMore,
  });

  final WritingHint? hint;
  final bool isLoading;
  final bool canAskForMore;
  final VoidCallback onAskForMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignTokens.space3),
      decoration: BoxDecoration(
        color: DesignTokens.infoSoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            CupertinoIcons.lightbulb_fill,
            color: DesignTokens.info,
            size: 18,
          ),
          const SizedBox(width: DesignTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoading || hint == null
                      ? 'Marie is taking a look…'
                      : hint!.message,
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
                ),
                if (!isLoading && hint != null && canAskForMore) ...[
                  const SizedBox(height: DesignTokens.space1),
                  GestureDetector(
                    onTap: onAskForMore,
                    child: Text(
                      'Give me another clue',
                      style: DesignTokens.body(
                        12,
                        weight: FontWeight.w600,
                      ).copyWith(color: DesignTokens.info),
                    ),
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
