import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../services/premium_access_gate.dart';
import '../../services/review_material_service.dart';
import '../../services/subscription_gate_service.dart';
import '../../widgets/v3/v3_surface.dart';
import '../exam/exam_readiness_screen.dart';
import '../labs/alphabet_lab_screen.dart';
import '../labs/connectors_lab_screen.dart';
import '../labs/grammar_lab_screen.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/liaison_lab_screen.dart';
import '../labs/vocab_lab_screen.dart';
import '../labs/writing_lab_screen.dart';
import '../reading/reading_library_screen.dart';
import '../speak/speak_review_screen.dart';
import '../speak/speaking_course_home_screen.dart';

/// Mixed-skills practice workspace. Speaking is one destination inside this
/// screen; it never replaces the Practice shell or the global Home tab.
class V3PracticeScreen extends ConsumerWidget {
  const V3PracticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ReviewMaterialService.recentSessions(
      ref.watch(storageServiceProvider),
    ).take(3).toList(growable: false);
    return V3Scaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
        children: [
          const V3Header(
            title: 'Practice',
            subtitle: 'Choose one skill, review a win, or prepare for an exam.',
          ),
          const SizedBox(height: 24),
          V3SectionLabel('Foundations'),
          const SizedBox(height: 9),
          Row(
            children: [
              _foundation(
                context,
                ref,
                Icons.abc_rounded,
                'Alphabet',
                const AlphabetLabScreen(),
                null,
              ),
              const SizedBox(width: 8),
              _foundation(
                context,
                ref,
                Icons.link_rounded,
                'Connectors',
                const ConnectorsLabScreen(),
                PremiumArea.connectors,
              ),
              const SizedBox(width: 8),
              _foundation(
                context,
                ref,
                Icons.record_voice_over_outlined,
                'Liaison',
                const LiaisonLabScreen(),
                PremiumArea.liaison,
              ),
            ],
          ),
          const SizedBox(height: 20),
          V3SectionLabel('Practice a skill'),
          const SizedBox(height: 9),
          _skill(
            context,
            ref,
            Icons.mic_none_rounded,
            'Speaking',
            'Guided conversation, roleplay, and exam speaking',
            const SpeakingCourseHomeScreen(),
            PremiumArea.speaking,
          ),
          _skill(
            context,
            ref,
            Icons.menu_book_outlined,
            'Reading',
            'Stories and real-world text',
            const ReadingLibraryScreen(),
            PremiumArea.reading,
          ),
          _skill(
            context,
            ref,
            Icons.headphones_outlined,
            'Listening',
            'Music, narration, podcast, and educational audio',
            const ListeningLabScreen(),
            PremiumArea.listening,
          ),
          _skill(
            context,
            ref,
            Icons.edit_note_rounded,
            'Writing',
            'Build useful sentences with feedback',
            const WritingLabScreen(),
            PremiumArea.writing,
          ),
          _skill(
            context,
            ref,
            Icons.auto_fix_high_outlined,
            'Grammar',
            'Learn patterns through examples',
            const GrammarLabScreen(),
            PremiumArea.grammar,
          ),
          _skill(
            context,
            ref,
            Icons.style_outlined,
            'Vocabulary',
            'Recall words with spaced practice',
            const VocabLabScreen(),
            null,
          ),
          const SizedBox(height: 20),
          V3Row(
            icon: Icons.fact_check_outlined,
            title: 'TEF & TCF readiness',
            subtitle: 'Practice the exam tasks at your current CEFR level',
            onTap: () =>
                AppRouter.push(context, (_) => const ExamReadinessScreen()),
          ),
          const SizedBox(height: 20),
          V3SectionLabel('Review'),
          const SizedBox(height: 9),
          V3Row(
            icon: Icons.replay_rounded,
            title: 'Bring it back',
            subtitle:
                'Replay recent phrases, stories, listening, and speaking.',
            onTap: () =>
                AppRouter.push(context, (_) => const SpeakReviewScreen()),
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 20),
            V3SectionLabel('Recent practice'),
            const SizedBox(height: 9),
            for (final session in recent) ...[
              V3Row(
                icon: _iconFor(session.skill),
                title: session.displayTitle,
                subtitle: '${session.skill} · Open saved review',
                onTap: () => _openRecent(context, session),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _skill(
    BuildContext context,
    WidgetRef ref,
    IconData icon,
    String title,
    String subtitle,
    Widget screen,
    PremiumArea? area,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: V3Row(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () async {
          if (area != null &&
              !await requirePremiumArea(
                context,
                ref,
                area,
                source: 'practice_$title',
              )) {
            return;
          }
          if (context.mounted) await AppRouter.push(context, (_) => screen);
        },
      ),
    );
  }

  Widget _foundation(
    BuildContext context,
    WidgetRef ref,
    IconData icon,
    String label,
    Widget screen,
    PremiumArea? area,
  ) {
    return Expanded(
      child: V3Card(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        onTap: () async {
          if (area != null &&
              !await requirePremiumArea(
                context,
                ref,
                area,
                source: 'practice_$label',
              )) {
            return;
          }
          if (context.mounted) await AppRouter.push(context, (_) => screen);
        },
        child: Column(
          children: [
            Icon(icon, color: DesignTokens.nightAccent, size: 22),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              style: DesignTokens.body(
                11,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.nightText),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String skill) => switch (skill.toLowerCase()) {
    'speaking' || 'roleplay' || 'exam speaking' => Icons.mic_none_rounded,
    'reading' => Icons.menu_book_outlined,
    'listening' => Icons.headphones_outlined,
    'writing' => Icons.edit_note_rounded,
    'grammar' => Icons.auto_fix_high_outlined,
    _ => Icons.replay_rounded,
  };

  void _openRecent(BuildContext context, ReviewSessionSummary session) {
    final speaking = switch (session.skill.toLowerCase()) {
      'speaking' || 'roleplay' || 'exam speaking' => true,
      _ => false,
    };
    AppRouter.push(
      context,
      (_) => speaking
          ? SavedSpeakingTranscriptScreen(session: session)
          : const SpeakReviewScreen(),
    );
  }
}
