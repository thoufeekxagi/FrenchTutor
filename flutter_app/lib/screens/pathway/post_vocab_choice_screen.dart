import 'package:flutter/material.dart';

import '../../config/theme.dart';
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

  bool get _hasPracticedWords => widget.vocabResult?.wordsCovered.isNotEmpty ?? false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.menu_book, size: 30, color: Passeport.brass),
                  const SizedBox(height: 8),
                  Text('Reading & Listening', style: Passeport.display(20, weight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'Want a short passage built from the words you just practiced, or from today\'s lesson?',
                    style: Passeport.body(13).copyWith(color: Passeport.slateDim),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  Column(
                    children: [
                      PasseportPrimaryButton(
                        label: _hasPracticedWords
                            ? 'From the words I just practiced (${widget.vocabResult?.wordsCovered.length ?? 0})'
                            : 'From the words I just practiced',
                        onPressed: (!_hasPracticedWords || _isBuilding) ? null : _chooseFromPracticedWords,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _isBuilding ? null : _chooseFromTodaysLesson,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Passeport.hairline),
                          foregroundColor: Passeport.text,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text("From today's lesson", style: Passeport.body(13, weight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isBuilding)
            Container(
              color: Colors.black.withValues(alpha: 0.15),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Passeport.card, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Passeport.maroon),
                      const SizedBox(height: 10),
                      Text(_buildingLabel, style: Passeport.mono(11).copyWith(color: Passeport.slateDim)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _chooseFromTodaysLesson() {
    final exercise = widget.fallbackExercise;
    if (exercise == null) {
      Navigator.of(context).pop(const PostVocabChoice(null));
      return;
    }
    Navigator.of(context)
        .pop(PostVocabChoice(ContentService.shared.readingPassage(fromListening: exercise)));
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
      passage = await LessonAgentService.shared.buildReadingPassageFromVocab(words: words).timeout(const Duration(seconds: 14));
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
