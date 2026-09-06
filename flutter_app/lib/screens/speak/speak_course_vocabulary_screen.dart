import 'package:flutter/material.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../labs/vocabulary_flashcards_screen.dart';
import 'speak_ui.dart';

/// Opens one already-prepared Course vocabulary artifact.
///
/// Generation deliberately does not exist on this screen. The five words and
/// their five connected sentence beats must be persisted before Course makes
/// the owning session available.
class SpeakCourseVocabularyScreen extends StatefulWidget {
  const SpeakCourseVocabularyScreen({
    super.key,
    required this.vocabularySet,
    required this.contentKey,
  });

  final GeneratedVocabularySet vocabularySet;
  final String contentKey;

  @override
  State<SpeakCourseVocabularyScreen> createState() =>
      _SpeakCourseVocabularyScreenState();
}

class _SpeakCourseVocabularyScreenState
    extends State<SpeakCourseVocabularyScreen> {
  GeneratedVocabularySet get set => widget.vocabularySet;

  bool get _isReady =>
      set.entries.length == 5 &&
      set.entries.every((entry) => set.storyExamples.containsKey(entry.id));

  Future<void> _open(VocabularyStudyDepth depth) async {
    if (!_isReady) return;
    final completed = await AppRouter.push<bool>(
      context,
      (_) => VocabularyFlashcardsScreen(
        title: set.title,
        entries: set.entries,
        source: 'course',
        topic: set.topic,
        levelBand: set.levelBand,
        studyDepth: depth,
        storyExamples: set.storyExamples,
        coverUrl: set.coverUrl,
        prefetchAudio: false,
        preparedContentOnly: true,
      ),
      fullscreenDialog: true,
    );
    if (completed == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SpeakScaffold(
      child: Column(
        children: [
          SpeakHeader(
            title: 'Vocabulary',
            subtitle: '${set.title} · ${set.levelBand}',
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: Icon(Icons.close_rounded, color: SpeakColors.inkSoft),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              children: [
                Text(
                  'Five words. One useful context.',
                  style: DesignTokens.display(29),
                ),
                const SizedBox(height: 8),
                Text(
                  _isReady
                      ? 'Choose how you want to practise this prepared set.'
                      : 'This lesson is not ready yet.',
                  style: DesignTokens.body(
                    15,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                ),
                const SizedBox(height: 22),
                if (_isReady) ...[
                  _ModeCard(
                    icon: Icons.style_outlined,
                    title: 'Words only',
                    subtitle: 'Learn the five words one at a time.',
                    onTap: () => _open(VocabularyStudyDepth.wordsOnly),
                  ),
                  const SizedBox(height: 12),
                  _ModeCard(
                    icon: Icons.auto_stories_outlined,
                    title: 'Words + context',
                    subtitle:
                        'Use the five prepared sentences as one connected mini-story.',
                    onTap: () => _open(VocabularyStudyDepth.wordsAndSentences),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    set.entries.map((entry) => entry.fr).join('  ·  '),
                    textAlign: TextAlign.center,
                    style: DesignTokens.body(
                      14,
                      weight: FontWeight.w700,
                    ).copyWith(color: SpeakColors.accent, height: 1.45),
                  ),
                ] else
                  SpeakCard(
                    color: SpeakColors.accentSoft,
                    child: Text(
                      'Course will make this card available after all five words and sentences have been saved.',
                      style: DesignTokens.body(14).copyWith(height: 1.4),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SpeakCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: SpeakColors.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: SpeakColors.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: DesignTokens.display(19)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: DesignTokens.body(
                        13,
                      ).copyWith(color: SpeakColors.inkSoft, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward_rounded, color: SpeakColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}
