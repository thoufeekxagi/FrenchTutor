import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../design/app_router.dart';
import '../../providers/database_provider.dart';
import '../../models/tutor_persona.dart';
import '../../services/subscription_gate_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/web/web_layout.dart';
import '../../widgets/web/web_practice_grid.dart';
import '../../services/premium_access_gate.dart';
import '../pathway/vocab_picker_screen.dart';
import 'alphabet_lab_screen.dart';
import 'connectors_lab_screen.dart';
import 'grammar_lab_screen.dart';
import 'liaison_lab_screen.dart';
import 'listening_lab_screen.dart';
import 'vocab_lab_screen.dart';
import 'writing_lab_screen.dart';
import '../mocks/mocks_screen.dart';
import '../speak/speaking_practice_screen.dart';

class LabsScreen extends ConsumerWidget {
  const LabsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Must be watch, not read — this decides every lock badge on this
    // screen, and a purchase invalidates this provider precisely so this
    // rebuilds with fresh lock state instead of showing what was true when
    // the tab was first opened.
    final gate = ref.watch(subscriptionGateServiceProvider);
    if (MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded) {
      return _webPracticePage(context, ref, gate);
    }
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: PSContentColumn(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text('Practice', style: DesignTokens.display(30)),
                const SizedBox(height: 4),
                Text(
                  'Choose one skill. Leave with evidence.',
                  style: DesignTokens.body(
                    14,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView(
                    children: [
                      _RecommendedPractice(
                        onTap: () => _open(
                          context,
                          ref: ref,
                          labId: 'vocabulary',
                          builder: (_) => const VocabPickerScreen(),
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space5),
                      _LabTile(
                        icon: CupertinoIcons.textformat_abc,
                        title: 'Learn the Alphabet',
                        subtitle:
                            'Start here if you\'re brand new: how each letter really sounds, about 40 to 50 minutes',
                        locked: gate.isLabLocked('alphabet'),
                        onTap: () => _open(
                          context,
                          ref: ref,
                          labId: 'alphabet',
                          builder: (_) => const AlphabetLabScreen(),
                        ),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.stopwatch_fill,
                        title: 'Speaking mock',
                        subtitle:
                            'Timed TEF / TCF practice with rubric feedback',
                        locked: gate.isLabLocked('speaking_mock'),
                        onTap: () => _open(
                          context,
                          ref: ref,
                          labId: 'speaking_mock',
                          builder: (_) => const MocksScreen(),
                        ),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.mic_fill,
                        title: 'Vocabulary',
                        subtitle:
                            'Auto-pick or choose words, practice live with ${ActiveTutor.current.displayName}',
                        locked: gate.isLabLocked('vocabulary'),
                        onTap: () => _open(
                          context,
                          ref: ref,
                          labId: 'vocabulary',
                          builder: (_) => const VocabPickerScreen(),
                        ),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.square_stack_3d_up,
                        title: 'Flashcards',
                        subtitle: 'Browse by category, spaced repetition',
                        locked: gate.isLabLocked('flashcards'),
                        onTap: () => _open(
                          context,
                          ref: ref,
                          labId: 'flashcards',
                          builder: (_) => const VocabLabScreen(),
                        ),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.book,
                        title: 'Grammar',
                        subtitle: 'Lessons & drills',
                        locked: gate.isLabLocked('grammar'),
                        onTap: () => _open(
                          context,
                          ref: ref,
                          labId: 'grammar',
                          builder: (_) => const GrammarLabScreen(),
                        ),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.waveform,
                        title: 'Liaison',
                        subtitle: 'How French words link together when spoken',
                        locked: gate.isLabLocked('liaison'),
                        onTap: () => _open(
                          context,
                          ref: ref,
                          labId: 'liaison',
                          builder: (_) => const LiaisonLabScreen(),
                        ),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.link,
                        title: 'Connectors',
                        subtitle: 'The logic words that hold French together',
                        locked: gate.isLabLocked('connectors'),
                        onTap: () => _open(
                          context,
                          ref: ref,
                          labId: 'connectors',
                          builder: (_) => const ConnectorsLabScreen(),
                        ),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.headphones,
                        title: 'Listening',
                        subtitle: 'Comprehension passages',
                        locked: gate.isLabLocked('listening'),
                        onTap: () => _open(
                          context,
                          ref: ref,
                          labId: 'listening',
                          builder: (_) => const ListeningLabScreen(),
                        ),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.bubble_left_bubble_right,
                        title: 'Roleplay',
                        subtitle:
                            'Live scenes: café, travel, directions & more',
                        locked: gate.isLabLocked('roleplay'),
                        onTap: () => _open(
                          context,
                          ref: ref,
                          labId: 'roleplay',
                          builder: (_) => const SpeakingPracticeScreen(
                            request: SpeakingPracticeRequest(
                              mode: SpeakingMode.roleplay,
                              topic: 'Surprise me',
                              goal: 'Fluency',
                            ),
                          ),
                        ),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.pencil,
                        title: 'Writing',
                        subtitle: 'Essays with graded feedback',
                        locked: gate.isLabLocked('writing'),
                        onTap: () => _open(
                          context,
                          ref: ref,
                          labId: 'writing',
                          builder: (_) => const WritingLabScreen(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _webPracticePage(
    BuildContext context,
    WidgetRef ref,
    SubscriptionGateService gate,
  ) {
    final items = <WebPracticeShortcut>[
      WebPracticeShortcut(
        icon: CupertinoIcons.textformat_abc,
        label: 'Alphabet',
        locked: gate.isLabLocked('alphabet'),
        onTap: () => _open(
          context,
          ref: ref,
          labId: 'alphabet',
          builder: (_) => const AlphabetLabScreen(),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.stopwatch_fill,
        label: 'Speaking mock',
        locked: gate.isLabLocked('speaking_mock'),
        onTap: () => _open(
          context,
          ref: ref,
          labId: 'speaking_mock',
          builder: (_) => const MocksScreen(),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.mic_fill,
        label: 'Vocabulary',
        locked: gate.isLabLocked('vocabulary'),
        onTap: () => _open(
          context,
          ref: ref,
          labId: 'vocabulary',
          builder: (_) => const VocabPickerScreen(),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.square_stack_3d_up,
        label: 'Flashcards',
        locked: gate.isLabLocked('flashcards'),
        onTap: () => _open(
          context,
          ref: ref,
          labId: 'flashcards',
          builder: (_) => const VocabLabScreen(),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.book,
        label: 'Grammar',
        locked: gate.isLabLocked('grammar'),
        onTap: () => _open(
          context,
          ref: ref,
          labId: 'grammar',
          builder: (_) => const GrammarLabScreen(),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.waveform,
        label: 'Liaison',
        locked: gate.isLabLocked('liaison'),
        onTap: () => _open(
          context,
          ref: ref,
          labId: 'liaison',
          builder: (_) => const LiaisonLabScreen(),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.link,
        label: 'Connectors',
        locked: gate.isLabLocked('connectors'),
        onTap: () => _open(
          context,
          ref: ref,
          labId: 'connectors',
          builder: (_) => const ConnectorsLabScreen(),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.headphones,
        label: 'Listening',
        locked: gate.isLabLocked('listening'),
        onTap: () => _open(
          context,
          ref: ref,
          labId: 'listening',
          builder: (_) => const ListeningLabScreen(),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.bubble_left_bubble_right,
        label: 'Roleplay',
        locked: gate.isLabLocked('roleplay'),
        onTap: () => _open(
          context,
          ref: ref,
          labId: 'roleplay',
          builder: (_) => const SpeakingPracticeScreen(
            request: SpeakingPracticeRequest(
              mode: SpeakingMode.roleplay,
              topic: 'Surprise me',
              goal: 'Fluency',
            ),
          ),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.pencil,
        label: 'Writing',
        locked: gate.isLabLocked('writing'),
        onTap: () => _open(
          context,
          ref: ref,
          labId: 'writing',
          builder: (_) => const WritingLabScreen(),
        ),
      ),
    ];
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: WebPage(
          header: const WebPageHeader(
            title: 'Practice',
            subtitle: 'Choose a focused way to build your French.',
          ),
          children: [
            WebPracticeGrid(
              heading: 'PRACTICE LIBRARY',
              description:
                  'Short, focused ways to practise one skill at a time.',
              items: items,
            ),
          ],
        ),
      ),
    );
  }
}

void _open(
  BuildContext context, {
  required WidgetRef ref,
  required String labId,
  required WidgetBuilder builder,
}) async {
  final area = PremiumAreaMapping.fromLabId(labId);
  if (area != null &&
      !await requirePremiumArea(context, ref, area, source: 'labs_$labId')) {
    return;
  }
  if (context.mounted) await AppRouter.push(context, builder);
}

class _RecommendedPractice extends StatelessWidget {
  const _RecommendedPractice({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Review six words from yesterday',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(DesignTokens.space4),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            border: Border.all(color: DesignTokens.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DesignTokens.primarySoft,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
                ),
                child: const Icon(
                  CupertinoIcons.arrow_counterclockwise,
                  color: DesignTokens.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: DesignTokens.space3),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recommended for you',
                      style: TextStyle(
                        color: DesignTokens.mutedDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Review 6 words from yesterday',
                      style: TextStyle(
                        color: DesignTokens.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Spaced repetition · 8 min',
                      style: TextStyle(
                        color: DesignTokens.mutedDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_right,
                color: DesignTokens.mutedDim,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabTile extends StatelessWidget {
  const _LabTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.locked = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        PSHaptics.light();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DesignTokens.hairline, width: 1),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: locked
                        ? DesignTokens.canvasDim
                        : DesignTokens.info.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: locked ? DesignTokens.muted : DesignTokens.info,
                    size: 20,
                  ),
                ),
                if (locked)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: DesignTokens.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: DesignTokens.ink.withValues(alpha: 0.1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: Icon(
                        CupertinoIcons.lock_fill,
                        size: 10,
                        color: DesignTokens.mutedDim,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DesignTokens.body(15, weight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ],
              ),
            ),
            Icon(
              locked ? CupertinoIcons.lock_fill : CupertinoIcons.chevron_right,
              color: DesignTokens.muted,
              size: locked ? 14 : 16,
            ),
          ],
        ),
      ),
    );
  }
}
