import '../../widgets/adaptive/adaptive.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/writing_guide_overlay.dart';

class WritingTaskScreen extends ConsumerStatefulWidget {
  const WritingTaskScreen({super.key, required this.task});

  final WritingTask task;

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

  WritingTask get task => widget.task;

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

  void _openGuide() {
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
    WritingGuideOverlay.show(context, lessonContext: buf.toString());
  }

  @override
  void dispose() {
    _logMinutes();
    _textController.dispose();
    super.dispose();
  }

  void _logMinutes() {
    final minutes = DateTime.now().difference(_sessionStart).inMinutes;
    if (minutes <= 0 || _content.isEmpty) return;
    ref.read(learningStoreProvider).markHabit('writing', minutes: minutes);
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
        actions: [
          IconButton(
            tooltip: 'Talk with Marie',
            onPressed: _openGuide,
            icon: const Icon(CupertinoIcons.phone_fill, color: DesignTokens.primary),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        children: [
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
          const SizedBox(height: 24),
        ],
      ),
    );
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
                  16,
                  weight: FontWeight.w500,
                ).copyWith(color: DesignTokens.primary),
              ),
            ],
          ),
          if (feedback.strengths.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Strengths',
              style: DesignTokens.body(12, weight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            for (final s in feedback.strengths)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      CupertinoIcons.checkmark,
                      size: 12,
                      color: DesignTokens.success,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        s,
                        style: DesignTokens.body(
                          12,
                        ).copyWith(color: DesignTokens.slateDim),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (feedback.corrections.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Corrections',
              style: DesignTokens.body(12, weight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            for (final c in feedback.corrections)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          c.original,
                          style: DesignTokens.body(11.5).copyWith(
                            color: DesignTokens.primary,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          CupertinoIcons.arrow_right,
                          size: 9,
                          color: DesignTokens.slate,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          c.fixed,
                          style: DesignTokens.body(
                            11.5,
                            weight: FontWeight.w500,
                          ).copyWith(color: DesignTokens.info),
                        ),
                      ],
                    ),
                    if (c.why.isNotEmpty)
                      Text(
                        c.why,
                        style: DesignTokens.mono(
                          10,
                        ).copyWith(color: DesignTokens.slateDim),
                      ),
                  ],
                ),
              ),
          ],
          if (feedback.connectorFeedback.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Connectors',
              style: DesignTokens.body(12, weight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              feedback.connectorFeedback,
              style: DesignTokens.body(
                12,
              ).copyWith(color: DesignTokens.slateDim),
            ),
          ],
          if (feedback.improvedVersion.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Improved version',
                  style: DesignTokens.body(12, weight: FontWeight.w500),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    CupertinoIcons.speaker_2_fill,
                    size: 16,
                    color: DesignTokens.info,
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
                12.5,
              ).copyWith(color: DesignTokens.slateDim),
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
