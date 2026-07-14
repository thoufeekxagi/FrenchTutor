import '../../widgets/adaptive/adaptive.dart';
import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../config/api_keys.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/lesson_qa_overlay.dart';
import '../../widgets/marie_toolbar_button.dart';
import '../session/session_screen.dart';

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

  String get _lessonContext => ref.read(contentServiceProvider).writingTaskContext(task);

  int get _wordCount {
    if (_content.trim().isEmpty) return 0;
    return _content.trim().split(RegExp(r'\s+')).length;
  }

  List<Connector> get _targetConnectorObjects {
    final pack = ref.read(contentServiceProvider).connectors();
    if (pack == null) return [];
    return pack.connectors.where((c) => task.targetConnectors.contains(c.id)).toList();
  }

  bool _connectorUsed(Connector connector) {
    final stem = connector.fr.toLowerCase().split('...').first;
    return _content.toLowerCase().contains(stem);
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
      final result = await ref.read(lessonAgentServiceProvider).gradeWriting(
            task: task,
            submission: submittedText,
          );
      if (!mounted) return;
      setState(() {
        _feedback = result;
        _isGrading = false;
      });
      ref.read(learningStoreProvider).saveSubmission(
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
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: Text(task.title, style: Passeport.display(18)),
        backgroundColor: Passeport.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: () => LessonQAOverlay.show(context, lessonContext: _lessonContext),
            icon: const Icon(CupertinoIcons.mic_fill, color: Passeport.brass),
          ),
          MarieToolbarButton(lessonContext: _lessonContext),
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
              style: Passeport.mono(11).copyWith(color: Passeport.maroon),
            ),
          ],
          const SizedBox(height: 16),
          PasseportPrimaryButton(
            label: _feedback == null ? 'Submit for grading' : 'Re-submit',
            onPressed: (_isGrading || _wordCount < 5) ? null : _submit,
          ),
          if (_feedback != null) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  LessonSpeechService.shared.deactivate();
                  Navigator.of(context).push(
                    AppRouter.route(fullscreenDialog: true, builder: (_) => SessionScreen(
                        apiKey: ApiKeys.geminiKey,
                        lessonContext: _lessonContext,
                      ),
                    ),
                  );
                },
                icon: const Icon(CupertinoIcons.phone_fill, size: 16, color: Passeport.maroon),
                label: Text(
                  'Discuss feedback with Marie',
                  style: Passeport.mono(11, weight: FontWeight.w500).copyWith(color: Passeport.maroon),
                ),
              ),
            ),
          ],
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
              const KickerText('Feedback', color: Passeport.slateDim),
              const Spacer(),
              Text(
                '${feedback.scoreOutOf10.toStringAsFixed(1)} / 10',
                style: Passeport.display(16, weight: FontWeight.w500).copyWith(color: Passeport.maroon),
              ),
            ],
          ),
          if (feedback.strengths.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Strengths', style: Passeport.body(12, weight: FontWeight.w500)),
            const SizedBox(height: 4),
            for (final s in feedback.strengths)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(CupertinoIcons.checkmark, size: 12, color: Passeport.brass),
                    const SizedBox(width: 6),
                    Expanded(child: Text(s, style: Passeport.body(12).copyWith(color: Passeport.slateDim))),
                  ],
                ),
              ),
          ],
          if (feedback.corrections.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Corrections', style: Passeport.body(12, weight: FontWeight.w500)),
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
                          style: Passeport.body(11.5).copyWith(
                            color: Passeport.maroon,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(CupertinoIcons.arrow_right, size: 9, color: Passeport.slate),
                        const SizedBox(width: 6),
                        Text(
                          c.fixed,
                          style: Passeport.body(11.5, weight: FontWeight.w500).copyWith(color: Passeport.brass),
                        ),
                      ],
                    ),
                    if (c.why.isNotEmpty)
                      Text(c.why, style: Passeport.mono(10).copyWith(color: Passeport.slateDim)),
                  ],
                ),
              ),
          ],
          if (feedback.connectorFeedback.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Connectors', style: Passeport.body(12, weight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(feedback.connectorFeedback, style: Passeport.body(12).copyWith(color: Passeport.slateDim)),
          ],
          if (feedback.improvedVersion.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Improved version', style: Passeport.body(12, weight: FontWeight.w500)),
                const Spacer(),
                IconButton(
                  icon: const Icon(CupertinoIcons.speaker_2_fill, size: 16, color: Passeport.brass),
                  onPressed: () => LessonSpeechService.shared.speak(
                    items: LessonSpeechService.speechItemsFromText(feedback.improvedVersion),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
            Text(feedback.improvedVersion, style: Passeport.body(12.5).copyWith(color: Passeport.slateDim)),
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
          const KickerText('Prompt', color: Passeport.slateDim),
          const SizedBox(height: 8),
          Text(
            task.promptFr,
            style: Passeport.body(14),
          ),
          const SizedBox(height: 6),
          if (_showEnglish)
            Text(
              task.promptEn,
              style: Passeport.body(12.5).copyWith(color: Passeport.slateDim),
            )
          else
            TextButton(
              onPressed: () => setState(() => _showEnglish = true),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                'Show English',
                style: Passeport.mono(10.5, weight: FontWeight.w500).copyWith(color: Passeport.maroon),
              ),
            ),
          if (task.rubricHints.isNotEmpty) ...[
            const SizedBox(height: 6),
            Divider(color: Passeport.hairline, height: 1),
            const SizedBox(height: 8),
            for (final hint in task.rubricHints)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: Passeport.brass, fontSize: 13)),
                    Expanded(
                      child: Text(
                        hint,
                        style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim),
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
          const KickerText('Target connectors', color: Passeport.slateDim),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: connectors.map((c) {
              final used = _connectorUsed(c);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: used ? Passeport.brass : Passeport.maroon.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  c.fr,
                  style: Passeport.mono(10.5, weight: FontWeight.w500).copyWith(
                    color: used ? Colors.white : Passeport.maroon,
                  ),
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
              const KickerText('Your response', color: Passeport.slateDim),
              const Spacer(),
              Text(
                '$_wordCount / ${task.minWords} words',
                style: Passeport.mono(10.5).copyWith(
                  color: _wordCount >= task.minWords ? Passeport.brass : Passeport.slateDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 180),
            decoration: BoxDecoration(
              color: Passeport.parchmentDim,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _textController,
              onChanged: (val) => setState(() => _content = val),
              maxLines: null,
              minLines: 8,
              style: Passeport.body(13.5),
              cursorColor: Passeport.maroon,
              decoration: InputDecoration(
                hintText: 'Write your response here...',
                hintStyle: Passeport.body(13.5).copyWith(color: Passeport.slate),
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
