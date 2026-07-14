import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/session_recorder.dart';
import '../../widgets/passeport_card.dart';
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
  const PathwayWritingScreen({super.key, required this.targetWords, required this.onComplete});

  final List<VocabEntry> targetWords;
  final void Function(WritingStageResult result) onComplete;

  @override
  ConsumerState<PathwayWritingScreen> createState() => _PathwayWritingScreenState();
}

class _PathwayWritingScreenState extends ConsumerState<PathwayWritingScreen> {
  final _sessionId = const Uuid().v4();
  late final SessionRecorder _recorder;
  final _controller = TextEditingController();

  String _submission = '';
  bool _isGrading = false;
  MicroWritingFeedback? _feedback;
  String? _errorText;

  String get _prompt => 'Write one or two sentences using: ${widget.targetWords.map((e) => e.fr).join(", ")}';

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
    _recorder = SessionRecorder(storage: ref.read(storageServiceProvider), stage: 'writing', topic: 'Writing');
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
      final result = await LessonAgentService.shared.gradeMicroWriting(prompt: _prompt, targetWords: targets, submission: text);
      if (!mounted) return;
      setState(() {
        _feedback = result;
        _isGrading = false;
      });
      ref.read(learningStoreProvider).saveSubmission(taskId: 'pathway_$_sessionId', text: text, feedback: result.comment);
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
      _recorder.finish(summary: 'Scored ${feedback.scoreOutOf10.toStringAsFixed(1)}/10 on: $_prompt');
    }
    widget.onComplete(WritingStageResult(score: feedback?.scoreOutOf10));
    Navigator.of(context).pop();
  }

  void _skip() {
    widget.onComplete(WritingStageResult());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: Text('Writing', style: Passeport.display(18)),
        backgroundColor: Passeport.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: TextButton(
          onPressed: _skip,
          child: Text('Skip', style: TextStyle(color: Passeport.slateDim)),
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              children: [
                PasseportCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const KickerText('Quick writing check', color: Passeport.slateDim),
                      const SizedBox(height: 8),
                      Text(_prompt, style: Passeport.body(13.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_feedback == null) ...[
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: Passeport.card, borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.all(4),
                      child: TextField(
                        controller: _controller,
                        onChanged: (val) => setState(() => _submission = val),
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: Passeport.body(13.5),
                        cursorColor: Passeport.maroon,
                        decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PasseportPrimaryButton(
                    label: _isGrading ? 'Grading…' : 'Submit',
                    onPressed: (_isGrading || _submission.trim().isEmpty) ? null : _submit,
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(_errorText!, style: Passeport.mono(11).copyWith(color: Passeport.maroon)),
                  ],
                ] else ...[
                  PasseportCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_feedback!.scoreOutOf10.toStringAsFixed(1)} / 10',
                          style: Passeport.display(28, weight: FontWeight.w500).copyWith(color: Passeport.maroon),
                        ),
                        const SizedBox(height: 10),
                        Text(_feedback!.comment, style: Passeport.body(13.5), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  const Spacer(),
                  PasseportPrimaryButton(label: 'Finish', onPressed: _finish),
                ],
              ],
            ),
          ),
          FloatingNotetakerOverlay(state: ref.watch(notetakerStateProvider)),
        ],
      ),
    );
  }
}
