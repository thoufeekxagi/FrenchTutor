import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../design/app_router.dart';
import '../../widgets/adaptive/adaptive.dart';
import 'connectors_lab_screen.dart';
import 'grammar_lab_screen.dart';
import 'listening_lab_screen.dart';
import 'vocab_lab_screen.dart';
import 'writing_lab_screen.dart';

class LabsScreen extends StatelessWidget {
  const LabsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchment,
      body: SafeArea(
        child: PSContentColumn(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text('Practice', style: Passeport.display(24)),
                const SizedBox(height: 4),
                Text('Go deeper on one skill at a time',
                    style: Passeport.body(14).copyWith(color: Passeport.slateDim)),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView(
                    children: [
                      _LabTile(
                        icon: CupertinoIcons.square_stack_3d_up,
                        title: 'Vocabulary',
                        subtitle: 'Flashcards & spaced repetition',
                        onTap: () => AppRouter.push(context, (_) => const VocabLabScreen()),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.book,
                        title: 'Grammar',
                        subtitle: 'Lessons & drills',
                        onTap: () => AppRouter.push(context, (_) => const GrammarLabScreen()),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.link,
                        title: 'Connectors',
                        subtitle: 'The logic words that hold French together',
                        onTap: () => AppRouter.push(context, (_) => const ConnectorsLabScreen()),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.headphones,
                        title: 'Listening',
                        subtitle: 'Comprehension passages',
                        onTap: () => AppRouter.push(context, (_) => const ListeningLabScreen()),
                      ),
                      _LabTile(
                        icon: CupertinoIcons.pencil,
                        title: 'Writing',
                        subtitle: 'Essays with graded feedback',
                        onTap: () => AppRouter.push(context, (_) => const WritingLabScreen()),
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

class _LabTile extends StatelessWidget {
  const _LabTile({
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
    return GestureDetector(
      onTap: () {
        PSHaptics.light();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Passeport.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Passeport.hairline, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Passeport.brass.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Passeport.brass, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Passeport.body(15, weight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Passeport.body(12).copyWith(color: Passeport.slateDim)),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right, color: Passeport.slate, size: 16),
          ],
        ),
      ),
    );
  }
}
