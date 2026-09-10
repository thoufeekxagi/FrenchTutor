import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../models/writing_course.dart';
import '../../services/review_material_service.dart';
import 'speak_ui.dart';

/// One prepared, sequential Smart Review lesson.
///
/// The parent prepares the child artifacts once. This screen only advances
/// through those artifacts, so repeated taps cannot create duplicate stories,
/// listening books, or writing lessons.
class SmartReviewLessonScreen extends StatefulWidget {
  const SmartReviewLessonScreen({
    super.key,
    required this.blueprint,
    required this.reading,
    required this.listening,
    required this.writing,
    required this.onSpeaking,
    required this.onReading,
    required this.onListening,
    required this.onWriting,
  });

  final ReviewBlueprint blueprint;
  final GeneratedStory reading;
  final GeneratedStory listening;
  final WritingCourseLesson writing;
  final Future<bool> Function() onSpeaking;
  final Future<bool> Function() onReading;
  final Future<bool> Function() onListening;
  final Future<bool> Function() onWriting;

  @override
  State<SmartReviewLessonScreen> createState() =>
      _SmartReviewLessonScreenState();
}

class _SmartReviewLessonScreenState extends State<SmartReviewLessonScreen> {
  static const _stageCount = 4;

  /// Vocabulary and grammar are already represented in the shared blueprint
  /// and stay visible while these four interactive Course stages run.
  int _completedStages = 0;
  bool _started = false;
  bool _running = false;
  String? _error;

  bool get _finished => _completedStages >= _stageCount;

  Future<void> _startOrResume() async {
    if (_running || _finished) return;
    _error = null;
    if (mounted) setState(() => _started = true);
    await _runCurrentStage();
  }

  Future<void> _runCurrentStage() async {
    if (_running || _finished || !mounted) return;
    final stage = _completedStages;
    setState(() {
      _running = true;
      _error = null;
    });

    try {
      final completed = switch (stage) {
        0 => await widget.onSpeaking(),
        1 => await widget.onReading(),
        2 => await widget.onListening(),
        3 => await widget.onWriting(),
        _ => false,
      };
      if (!mounted) return;
      if (!completed) {
        setState(() => _running = false);
        return;
      }
      setState(() {
        _completedStages = stage + 1;
        _running = false;
      });
      if (!_finished) {
        // The child artifacts were prepared before this screen was shown.
        // This short handoff frame is visual only; it never generates content.
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (mounted) unawaited(_runCurrentStage());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = 'This step could not be opened. You can try it again.';
      });
      debugPrint('Smart Review stage failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
        children: [
          SpeakHeader(
            leading: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _running ? null : () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: SpeakColors.inkSoft,
                  size: 25,
                ),
              ),
            ),
            title: 'Smart Review',
            subtitle: 'One prepared lesson across the language you need most.',
          ),
          const SizedBox(height: 22),
          _introCard(),
          const SizedBox(height: 22),
          _sectionLabel('WHAT YOU WILL REVIEW'),
          const SizedBox(height: 9),
          Text(
            widget.blueprint.title.isEmpty
                ? 'Review what matters'
                : widget.blueprint.title,
            style: DesignTokens.display(25),
          ),
          if (widget.blueprint.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.blueprint.summary,
              style: DesignTokens.body(14).copyWith(
                color: SpeakColors.inkSoft,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (widget.blueprint.vocabulary.isNotEmpty)
            _contentCard(
              icon: Icons.style_outlined,
              title: 'Vocabulary recall',
              content: widget.blueprint.vocabulary,
            ),
          if (widget.blueprint.grammar.isNotEmpty)
            _contentCard(
              icon: Icons.spellcheck_rounded,
              title: 'Grammar repair',
              content: widget.blueprint.grammar,
            ),
          if (widget.blueprint.steps.isNotEmpty)
            _contentCard(
              icon: Icons.route_rounded,
              title: 'Lesson sequence',
              content: widget.blueprint.steps,
            ),
          const SizedBox(height: 10),
          _sectionLabel('ONE REVIEW FLOW'),
          const SizedBox(height: 9),
          for (var index = 0; index < _stageCount; index++)
            _stageCard(index),
          if (_error != null) ...[
            const SizedBox(height: 5),
            Text(
              _error!,
              style: DesignTokens.body(13).copyWith(color: SpeakColors.orange),
            ),
          ],
          const SizedBox(height: 13),
          if (!_started)
            SpeakPrimaryButton(
              label: 'Start guided review',
              icon: Icons.arrow_forward_rounded,
              onTap: _startOrResume,
            )
          else if (_finished)
            _finishedCard()
          else
            SpeakPrimaryButton(
              label: _running ? 'Opening next step…' : 'Continue review',
              icon: _running
                  ? Icons.hourglass_top_rounded
                  : Icons.arrow_forward_rounded,
              onTap: _running ? null : _startOrResume,
            ),
        ],
      ),
    );
  }

  Widget _introCard() {
    return Container(
      decoration: BoxDecoration(
        color: SpeakColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SpeakColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: SpeakColors.accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: SpeakColors.accent),
                    const SizedBox(height: 8),
                    Text(
                      'Prepared once, practised in order',
                      style: DesignTokens.body(17, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Your vocabulary and grammar focus stays visible while the same context moves through guided speaking, reading, listening, and writing. No tap creates a second lesson.',
                      style: DesignTokens.body(14).copyWith(
                        color: SpeakColors.inkSoft,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: DesignTokens.body(
        11,
        weight: FontWeight.w800,
      ).copyWith(color: SpeakColors.accent, letterSpacing: 1.5),
    );
  }

  Widget _contentCard({
    required IconData icon,
    required String title,
    required List<String> content,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SpeakCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: SpeakColors.accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: DesignTokens.body(16, weight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 9),
            for (final item in content.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• $item',
                  style: DesignTokens.body(14).copyWith(
                    color: SpeakColors.inkSoft,
                    height: 1.45,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stageCard(int index) {
    final completed = index < _completedStages;
    final active = index == _completedStages && !_finished;
    final stage = switch (index) {
      0 => (
          Icons.mic_none_rounded,
          'Guided speaking',
          'Hear, say, and check the reviewed phrases.',
        ),
      1 => (
          Icons.menu_book_outlined,
          'Reading retrieval',
          'Read the prepared story and complete its checks.',
        ),
      2 => (
          Icons.headphones_outlined,
          'Listening retrieval',
          'Listen to the prepared lesson and complete its checks.',
        ),
      _ => (
          Icons.edit_note_rounded,
          'Writing transfer',
          'Use the same vocabulary and grammar in Course Writing.',
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        decoration: BoxDecoration(
          color: SpeakColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? SpeakColors.accent : SpeakColors.line,
            width: active ? 1.2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                color: active || completed
                    ? SpeakColors.accent
                    : SpeakColors.line,
              ),
              Expanded(
                child: ListTile(
                  leading: Icon(
                    stage.$1,
                    color: completed || active
                        ? SpeakColors.accent
                        : SpeakColors.inkSoft,
                  ),
                  title: Text(
                    stage.$2,
                    style: DesignTokens.body(16, weight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    completed ? 'Completed' : active ? stage.$3 : 'Coming next',
                    style: DesignTokens.body(13).copyWith(
                      color: SpeakColors.inkSoft,
                      height: 1.35,
                    ),
                  ),
                  trailing: completed
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: SpeakColors.accent,
                        )
                      : active
                          ? Icon(
                              _running
                                  ? Icons.hourglass_top_rounded
                                  : Icons.arrow_forward_ios_rounded,
                              size: 17,
                              color: SpeakColors.inkSoft,
                            )
                          : Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                              color: SpeakColors.inkSoft,
                            ),
                  onTap: active && !_running ? _startOrResume : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _finishedCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpeakColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SpeakColors.accent),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: SpeakColors.accent,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Smart Review complete. Your results are saved with this review.',
              style: DesignTokens.body(14, weight: FontWeight.w700).copyWith(
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
