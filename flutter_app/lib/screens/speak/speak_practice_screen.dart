import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../services/app_tour.dart';
import '../../services/premium_access_gate.dart';
import '../../services/review_material_service.dart';
import '../../services/subscription_gate_service.dart';
import '../labs/alphabet_lab_screen.dart';
import '../labs/connectors_lab_screen.dart';
import '../labs/grammar_lab_screen.dart';
import '../labs/liaison_lab_screen.dart';
import '../labs/listening_lab_screen.dart';
import '../reading/reading_library_screen.dart';
import '../labs/vocab_lab_screen.dart';
import '../labs/writing_lab_screen.dart';
import '../exam/exam_readiness_screen.dart';
import 'speak_review_screen.dart';
import 'speak_roadmap_screen.dart';
import 'speaking_flow_screen.dart';
import 'speak_ui.dart';

/// The open practice workspace. Course sessions provide progression; this
/// surface provides repetition, free conversation, and targeted refreshers.
class SpeakPracticeScreen extends ConsumerWidget {
  const SpeakPracticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentSpeaking =
        ReviewMaterialService.recentSessions(ref.watch(storageServiceProvider))
            .where(
              (session) => const {
                'Speaking',
                'Roleplay',
                'Exam speaking',
              }.contains(session.skill),
            )
            .take(3)
            .toList(growable: false);
    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          const SpeakHeader(
            title: 'Practice',
            subtitle: 'Strengthen anything you have learned so far.',
          ),
          const SizedBox(height: 22),
          _workspaceTabs(context),
          const SizedBox(height: 24),
          const SpeakSectionTitle(title: 'Review'),
          const SizedBox(height: 10),
          KeyedSubtree(
            key: AppTour.practiceReviewKey,
            child: Semantics(
              button: true,
              label: 'Open review from recent practice sessions',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    AppRouter.push(context, (_) => const SpeakReviewScreen()),
                child: SpeakCard(
                  child: Row(
                    children: [
                      _icon(Icons.replay_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Bring back what you learned in recent speaking, listening, reading, writing, or roleplay sessions.',
                          style: DesignTokens.body(
                            13,
                          ).copyWith(color: SpeakColors.inkSoft, height: 1.3),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: SpeakColors.inkSoft,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const SpeakSectionTitle(title: 'Practice a skill'),
          const SizedBox(height: 10),
          _skillRow(
            context,
            ref: ref,
            icon: Icons.mic_none_rounded,
            title: 'Speaking',
            subtitle: 'Interactive conversation practice',
            screen: const SpeakingHubScreen(),
            area: PremiumArea.speaking,
          ),
          _skillRow(
            context,
            ref: ref,
            icon: Icons.menu_book_outlined,
            title: 'Reading',
            subtitle: 'Stories and real-world text',
            screen: const ReadingLibraryScreen(),
            area: PremiumArea.reading,
            tourKey: AppTour.practiceReadingKey,
          ),
          _skillRow(
            context,
            ref: ref,
            icon: Icons.headphones_outlined,
            title: 'Listening',
            subtitle: 'Understand spoken French',
            screen: const ListeningLabScreen(),
            area: PremiumArea.listening,
            tourKey: AppTour.practiceListeningKey,
          ),
          _skillRow(
            context,
            ref: ref,
            icon: Icons.edit_note_rounded,
            title: 'Writing',
            subtitle: 'Create your own useful sentences',
            screen: const WritingLabScreen(),
            area: PremiumArea.writing,
            tourKey: AppTour.practiceWritingKey,
          ),
          _skillRow(
            context,
            ref: ref,
            icon: Icons.auto_fix_high_outlined,
            title: 'Grammar',
            subtitle: 'Learn patterns through stories',
            screen: const GrammarLabScreen(),
            area: PremiumArea.grammar,
            tourKey: AppTour.practiceGrammarKey,
          ),
          _skillRow(
            context,
            ref: ref,
            icon: Icons.style_outlined,
            title: 'Vocabulary',
            subtitle: 'Recall words with spaced practice',
            screen: const VocabLabScreen(),
            area: null,
            tourKey: AppTour.practiceVocabularyKey,
          ),
          if (recentSpeaking.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SpeakSectionTitle(title: 'Recent speaking'),
            const SizedBox(height: 10),
            SpeakCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var index = 0; index < recentSpeaking.length; index++)
                    _recentSpeakingRow(
                      context,
                      recentSpeaking[index],
                      showDivider: index > 0,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SpeakSectionTitle(title: 'Foundations', action: 'Refresh anytime'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _foundation(
                  context,
                  ref,
                  Icons.abc_rounded,
                  'Alphabet',
                  const AlphabetLabScreen(),
                  area: null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _foundation(
                  context,
                  ref,
                  Icons.link_rounded,
                  'Connectors',
                  const ConnectorsLabScreen(),
                  area: PremiumArea.connectors,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _foundation(
                  context,
                  ref,
                  Icons.record_voice_over_outlined,
                  'Liaison',
                  const LiaisonLabScreen(),
                  area: PremiumArea.liaison,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          GestureDetector(
            onTap: () =>
                AppRouter.push(context, (_) => const ExamReadinessScreen()),
            child: KeyedSubtree(
              key: AppTour.practiceExamKey,
              child: SpeakCard(
                color: SpeakColors.accentSoft,
                child: Row(
                  children: [
                    _icon(Icons.fact_check_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Exam readiness',
                            style: DesignTokens.body(
                              14,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Free TCF and TEF practice at the level you choose',
                            style: DesignTokens.body(
                              11,
                            ).copyWith(color: SpeakColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 15,
                      color: SpeakColors.inkSoft,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _workspaceTabs(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: SpeakColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SpeakColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _workspaceTab(
              label: 'Course',
              selected: false,
              onTap: () =>
                  AppRouter.push(context, (_) => const SpeakRoadmapScreen()),
            ),
          ),
          Expanded(
            child: _workspaceTab(
              label: 'Practice',
              selected: true,
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _workspaceTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? SpeakColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: DesignTokens.body(13, weight: FontWeight.w700).copyWith(
              color: selected ? SpeakColors.accent : SpeakColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }

  Widget _recentSpeakingRow(
    BuildContext context,
    ReviewSessionSummary session, {
    required bool showDivider,
  }) {
    return Column(
      children: [
        if (showDivider) Divider(height: 1, color: SpeakColors.line),
        Semantics(
          button: true,
          label: 'Open saved transcript for ${session.displayTitle}',
          child: InkWell(
            onTap: () => AppRouter.push(
              context,
              (_) => SavedSpeakingTranscriptScreen(session: session),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: SpeakColors.accentSoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.forum_outlined,
                      color: SpeakColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesignTokens.body(14, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${session.skill} · Open saved transcript',
                          style: DesignTokens.body(
                            11,
                          ).copyWith(color: SpeakColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 15,
                    color: SpeakColors.inkSoft,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _skillRow(
    BuildContext context, {
    required WidgetRef ref,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget screen,
    required PremiumArea? area,
    GlobalKey? tourKey,
  }) {
    final child = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
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
          if (context.mounted) {
            await AppRouter.push(context, (_) => screen);
          }
        },
        child: SpeakCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: DesignTokens.body(14, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: SpeakColors.inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
    return tourKey == null ? child : KeyedSubtree(key: tourKey, child: child);
  }

  Widget _foundation(
    BuildContext context,
    WidgetRef ref,
    IconData icon,
    String label,
    Widget screen, {
    required PremiumArea? area,
  }) {
    return GestureDetector(
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
        if (context.mounted) {
          await AppRouter.push(context, (_) => screen);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: SpeakColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SpeakColors.line),
        ),
        child: Column(
          children: [
            Icon(icon, color: SpeakColors.accent, size: 22),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              style: DesignTokens.body(11, weight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _icon(IconData icon) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: SpeakColors.accentSoft,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, color: SpeakColors.accent, size: 20),
  );
}
