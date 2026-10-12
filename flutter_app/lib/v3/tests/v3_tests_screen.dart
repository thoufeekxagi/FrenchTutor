import 'package:flutter/material.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../screens/exam/exam_readiness_screen.dart';
import '../ui/v3_ui.dart';

/// Tests tab. Screen contract:
///
/// User arrived to: practise under real exam conditions.
/// They must understand: the exact TCF Canada format (counts and minutes).
/// Primary action: open the exam practice.
/// Must not contain: invented scores or estimates. A level estimate appears
/// only after a real attempt, and is labelled an estimate.
///
/// The format numbers are the published TCF Canada format. Practice opens the
/// existing exam-readiness flow until the dedicated mock engine replaces it.
class V3TestsScreen extends StatelessWidget {
  const V3TestsScreen({super.key});

  static const _sections = [
    ('Listening', '39 questions', '35 min', 'One play. No going back.'),
    ('Reading', '39 questions', '60 min', 'Move freely between questions.'),
    (
      'Writing',
      '3 tasks',
      '60 min',
      '60 to 120, 120 to 150, 120 to 180 words.',
    ),
    (
      'Speaking',
      '3 tasks',
      '12 min',
      'Face to face, 2 minutes to prepare task 2.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        children: [
          Text('TCF CANADA', style: V3Type.eyebrow()),
          const SizedBox(height: 6),
          Text('Tests', style: V3Type.hero(44)),
          const SizedBox(height: 10),
          Text(
            'Four tests, 2 hours 47 minutes in total. Practise each one the way it is taken.',
            style: V3Type.body(16),
          ),
          const SizedBox(height: 24),
          for (final s in _sections) ...[
            V3Pressable(
              key: ValueKey('tests.section.${s.$1.toLowerCase()}'),
              label: '${s.$1}, ${s.$2}, ${s.$3}',
              onTap: () =>
                  AppRouter.push(context, (_) => const ExamReadinessScreen()),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: DesignTokens.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: DesignTokens.hairline),
                  boxShadow: DesignTokens.surfaceShadow,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.$1, style: V3Type.title(24)),
                          const SizedBox(height: 6),
                          Text(s.$4, style: V3Type.body(14)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          s.$3,
                          style: V3Type.strong(16, DesignTokens.primary),
                        ),
                        const SizedBox(height: 3),
                        Text(s.$2, style: V3Type.body(12.5)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
