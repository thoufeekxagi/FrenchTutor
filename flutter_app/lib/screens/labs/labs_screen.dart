import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../design/app_router.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../subscription/paywall_screen.dart';
import '../pathway/vocab_picker_screen.dart';
import 'alphabet_lab_screen.dart';
import 'connectors_lab_screen.dart';
import 'grammar_lab_screen.dart';
import 'liaison_lab_screen.dart';
import 'listening_lab_screen.dart';
import 'roleplay_lab_screen.dart';
import 'vocab_lab_screen.dart';
import 'writing_lab_screen.dart';
import '../mocks/mocks_screen.dart';

class LabsScreen extends ConsumerWidget {
  const LabsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Must be watch, not read — this decides every lock badge on this
    // screen, and a purchase invalidates this provider precisely so this
    // rebuilds with fresh lock state instead of showing what was true when
    // the tab was first opened.
    final gate = ref.watch(subscriptionGateServiceProvider);
    return Scaffold(
      backgroundColor: DesignTokens.parchment,
      body: SafeArea(
        child: PSContentColumn(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text('Practice', style: DesignTokens.display(24)),
                const SizedBox(height: 4),
                Text(
                  'Go deeper on one skill at a time',
                  style: DesignTokens.body(
                    14,
                  ).copyWith(color: DesignTokens.slateDim),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView(
                    children: [
                      _LabTile(
                        icon: CupertinoIcons.textformat_abc,
                        title: 'Learn the Alphabet',
                        subtitle:
                            'Start here if you\'re brand new: how each letter really sounds, about 40 to 50 minutes',
                        locked: gate.isLabLocked('alphabet'),
                        onTap: () => _open(
                          context,
                          locked: gate.isLabLocked('alphabet'),
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
                          locked: gate.isLabLocked('speaking_mock'),
                          builder: (_) => const MocksScreen(),
                        ),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.mic_fill,
                        title: 'Vocabulary',
                        subtitle: 'Auto-pick or choose words, practice live with Marie',
                        locked: gate.isLabLocked('vocabulary'),
                        onTap: () => _open(
                          context,
                          locked: gate.isLabLocked('vocabulary'),
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
                          locked: gate.isLabLocked('flashcards'),
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
                          locked: gate.isLabLocked('grammar'),
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
                          locked: gate.isLabLocked('liaison'),
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
                          locked: gate.isLabLocked('connectors'),
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
                          locked: gate.isLabLocked('listening'),
                          builder: (_) => const ListeningLabScreen(),
                        ),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.bubble_left_bubble_right,
                        title: 'Roleplay',
                        subtitle: 'Live scenes: café, travel, directions & more',
                        locked: gate.isLabLocked('roleplay'),
                        onTap: () => _open(
                          context,
                          locked: gate.isLabLocked('roleplay'),
                          builder: (_) => const RoleplayLabScreen(),
                        ),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.pencil,
                        title: 'Writing',
                        subtitle: 'Essays with graded feedback',
                        locked: gate.isLabLocked('writing'),
                        onTap: () => _open(
                          context,
                          locked: gate.isLabLocked('writing'),
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
}

void _open(
  BuildContext context, {
  required bool locked,
  required WidgetBuilder builder,
}) {
  if (locked) {
    AppRouter.push(
      context,
      (_) => const PaywallScreen(),
      fullscreenDialog: true,
    );
    return;
  }
  AppRouter.push(context, builder);
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
          color: DesignTokens.card,
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
                      decoration: const BoxDecoration(
                        color: DesignTokens.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0x1A000000), blurRadius: 3),
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
                    ).copyWith(color: DesignTokens.slateDim),
                  ),
                ],
              ),
            ),
            Icon(
              locked ? CupertinoIcons.lock_fill : CupertinoIcons.chevron_right,
              color: DesignTokens.slate,
              size: locked ? 14 : 16,
            ),
          ],
        ),
      ),
    );
  }
}
