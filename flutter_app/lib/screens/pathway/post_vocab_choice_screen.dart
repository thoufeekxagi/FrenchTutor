import '../../widgets/adaptive/adaptive.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../data/content_service.dart';
import '../../models/content_models.dart';
import '../../services/lesson_agent_service.dart';
import '../../widgets/passeport_primary_button.dart';
import 'agent_led_vocab_screen.dart' show VocabStageResult;

/// Shown right after the vocab stage ends, before Reading & Listening starts. The student
/// picks what the next stage's passage is built from — the words they just practiced (one LLM
/// call, fired here and only here, then treated as fixed pre-authored content for the rest of
/// the flow), or today's existing pre-authored lab passage. Whichever option is picked, the
/// listening gate screen itself never calls out to a model to invent content.
/// Ported from PostVocabChoiceView.swift.
/// The typed result this screen pops with. A null [passage] means a real
/// empty state (nothing to read today) — distinct from backing out, which
/// pops null at the route level and leaves the stage pending.
class PostVocabChoice {
  const PostVocabChoice(this.passage);
  final ReadingPassage? passage;
}

class PostVocabChoiceScreen extends StatefulWidget {
  const PostVocabChoiceScreen({
    super.key,
    this.vocabResult,
    this.fallbackExercise,
  });

  final VocabStageResult? vocabResult;
  final ListeningExercise? fallbackExercise;

  @override
  State<PostVocabChoiceScreen> createState() => _PostVocabChoiceScreenState();
}

class _PostVocabChoiceScreenState extends State<PostVocabChoiceScreen> {
  bool _isBuilding = false;
  String _buildingLabel = '';

  bool get _hasPracticedWords =>
      widget.vocabResult?.wordsCovered.isNotEmpty ?? false;

  @override
  Widget build(BuildContext context) {
    final practicedCount = widget.vocabResult?.wordsCovered.length ?? 0;
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.contentMaxWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.all(DesignTokens.screenMargin),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: DesignTokens.infoSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.book_fill,
                      size: 25,
                      color: DesignTokens.info,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.space5),
                  Text(
                    'Choose the listening passage',
                    style: DesignTokens.display(28),
                  ),
                  const SizedBox(height: DesignTokens.space3),
                  Text(
                    _hasPracticedWords
                        ? 'Use the $practicedCount words you just practiced, or continue with today’s prepared lesson.'
                        : 'No practiced words were captured. Continue with today’s prepared lesson.',
                    style: DesignTokens.body(
                      16,
                    ).copyWith(color: DesignTokens.slateDim, height: 1.45),
                  ),
                  if (_isBuilding) ...[
                    const SizedBox(height: DesignTokens.space6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(DesignTokens.space4),
                      decoration: BoxDecoration(
                        color: DesignTokens.infoSoft,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusCard,
                        ),
                      ),
                      child: Row(
                        children: [
                          const PSProgressIndicator(),
                          const SizedBox(width: DesignTokens.space3),
                          Expanded(
                            child: Text(
                              _buildingLabel,
                              style: DesignTokens.body(
                                14,
                                weight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  PasseportPrimaryButton(
                    label: _hasPracticedWords
                        ? 'Use my practiced words'
                        : 'Use today’s lesson',
                    icon: _hasPracticedWords
                        ? CupertinoIcons.sparkles
                        : CupertinoIcons.book_fill,
                    onPressed: _isBuilding
                        ? null
                        : (_hasPracticedWords
                              ? _chooseFromPracticedWords
                              : _chooseFromTodaysLesson),
                  ),
                  if (_hasPracticedWords) ...[
                    const SizedBox(height: DesignTokens.space2),
                    SizedBox(
                      width: double.infinity,
                      height: DesignTokens.minTapTarget,
                      child: TextButton(
                        onPressed: _isBuilding ? null : _chooseFromTodaysLesson,
                        child: Text(
                          'Use today’s lesson instead',
                          style: DesignTokens.body(
                            14,
                            weight: FontWeight.w600,
                          ).copyWith(color: DesignTokens.inkSoft),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _chooseFromTodaysLesson() {
    final exercise = widget.fallbackExercise;
    if (exercise == null) {
      Navigator.of(context).pop(const PostVocabChoice(null));
      return;
    }
    Navigator.of(context).pop(
      PostVocabChoice(
        ContentService.shared.readingPassage(fromListening: exercise),
      ),
    );
  }

  /// Fires exactly one LLM call (never repeated, never called again during teaching), raced
  /// against a timeout the same way VocabPickerScreen races planVocabSession — on failure or
  /// timeout, fall back to the pre-authored lab content so the student is never blocked
  /// waiting on a model.
  Future<void> _chooseFromPracticedWords() async {
    final words = widget.vocabResult?.wordsCovered;
    if (words == null || words.isEmpty) {
      _chooseFromTodaysLesson();
      return;
    }
    setState(() {
      _isBuilding = true;
      _buildingLabel = "Building today's passage…";
    });
    ReadingPassage? passage;
    try {
      passage = await LessonAgentService.shared
          .buildReadingPassageFromVocab(words: words)
          .timeout(const Duration(seconds: 14));
    } catch (_) {
      passage = null;
    }
    if (!mounted) return;
    setState(() => _isBuilding = false);
    if (passage != null) {
      Navigator.of(context).pop(PostVocabChoice(passage));
    } else {
      _chooseFromTodaysLesson();
    }
  }
}
