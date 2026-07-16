import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../providers/database_provider.dart';
import '../lessons/flashcard_session_screen.dart';

class VocabLabScreen extends ConsumerWidget {
  const VocabLabScreen({super.key});

  static const _phaseLabels = {
    1: 'Phase 1 · Foundations',
    2: 'Phase 2 · Expansion',
    3: 'Phase 3 · Refinement',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentServiceProvider);
    final srs = ref.watch(srsServiceProvider);
    final phases = content.vocabPhases;

    return Scaffold(
      backgroundColor: DesignTokens.parchment,
      appBar: AppBar(
        title: Text('Vocabulary', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.parchment,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: phases.length,
        itemBuilder: (context, phaseIndex) {
          final phase = phases[phaseIndex];
          return _PhaseSection(
            label: _phaseLabels[phase.phase] ?? 'Phase ${phase.phase}',
            phase: phase,
            srs: srs,
          );
        },
      ),
    );
  }
}

class _PhaseSection extends StatelessWidget {
  const _PhaseSection({
    required this.label,
    required this.phase,
    required this.srs,
  });

  final String label;
  final dynamic phase; // VocabPhase
  final dynamic srs; // SRSService

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        KickerText(label),
        const SizedBox(height: 10),
        PasseportCard(
          padding: 0,
          child: Column(
            children: [
              for (int i = 0; i < phase.themes.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: DesignTokens.hairline,
                    indent: 16,
                    endIndent: 16,
                  ),
                _ThemeTile(
                  theme: phase.themes[i],
                  phaseNumber: phase.phase,
                  srs: srs,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.theme,
    required this.phaseNumber,
    required this.srs,
  });

  final dynamic theme; // VocabTheme
  final int phaseNumber;
  final dynamic srs; // SRSService

  @override
  Widget build(BuildContext context) {
    final counts = srs.counts(phase: phaseNumber, themeId: theme.id);
    final total = theme.entries.length as int;
    final allKnown = counts.due == 0 && counts.unseen == 0 && total > 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        theme.title,
        style: DesignTokens.body(15, weight: FontWeight.w500),
      ),
      subtitle: Row(
        children: [
          if (counts.due > 0) ...[
            _CountBadge(
              label: '${counts.due} due',
              color: DesignTokens.primary,
            ),
            const SizedBox(width: 6),
          ],
          if (counts.unseen > 0)
            _CountBadge(
              label: '${counts.unseen} unseen',
              color: DesignTokens.info,
            ),
          if (allKnown)
            _CountBadge(label: '$total mastered', color: DesignTokens.mastery),
        ],
      ),
      trailing: allKnown
          ? const Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: DesignTokens.mastery,
              size: 22,
            )
          : Icon(
              CupertinoIcons.chevron_right,
              color: DesignTokens.slate,
              size: 20,
            ),
      onTap: () {
        AppRouter.push(
          context,
          (_) => FlashcardSessionScreen(phase: phaseNumber, theme: theme),
        );
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: DesignTokens.mono(
          10,
          weight: FontWeight.w500,
        ).copyWith(color: color),
      ),
    );
  }
}
