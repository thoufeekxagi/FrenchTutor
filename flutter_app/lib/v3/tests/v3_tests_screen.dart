import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../access/v3_access.dart';
import '../lesson/v3_lesson_player.dart';
import 'v3_exam_sets.dart';
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
class V3TestsScreen extends ConsumerStatefulWidget {
  const V3TestsScreen({super.key});

  @override
  ConsumerState<V3TestsScreen> createState() => _V3TestsScreenState();
}

class _V3TestsScreenState extends ConsumerState<V3TestsScreen> {
  String? _level;

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

  Future<void> _open(String skill) async {
    final level = _level ?? _profileLevel();
    try {
      final lesson = await V3ExamSets.load(level, skill);
      if (!mounted) return;
      await openV3Exam(
        context,
        ref,
        (_) => V3LessonPlayer(
          lesson: lesson,
          savePathProgress: false,
          completionEyebrow: 'PRACTICE COMPLETE',
          completionTitle: 'Practice complete',
        ),
        fullscreenDialog: true,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This practice could not open. Try again.'),
        ),
      );
    }
  }

  String _profileLevel() {
    final level = ref.read(learningStoreProvider).profile().level.toLowerCase();
    return V3ExamSets.levels.contains(level) ? level : 'a1';
  }

  @override
  Widget build(BuildContext context) {
    final level = _level ?? _profileLevel();
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
          const SizedBox(height: 12),
          const V3ExamFreeNote(),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final l in V3ExamSets.levels) ...[
                Expanded(
                  child: V3Pressable(
                    key: ValueKey('tests.level.$l'),
                    label: '${l.toUpperCase()} practice level',
                    selected: l == level,
                    onTap: () => setState(() => _level = l),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: l == level
                            ? DesignTokens.primary
                            : DesignTokens.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: l == level
                              ? DesignTokens.primary
                              : DesignTokens.hairline,
                        ),
                      ),
                      child: Text(
                        l.toUpperCase(),
                        style: V3Type.strong(
                          15,
                          l == level
                              ? DesignTokens.onPrimary
                              : DesignTokens.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                if (l != V3ExamSets.levels.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          for (final s in _sections) ...[
            V3Pressable(
              key: ValueKey('tests.section.${s.$1.toLowerCase()}'),
              label: '${s.$1}, ${s.$2}, ${s.$3}',
              onTap: () => unawaited(_open(s.$1.toLowerCase())),
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

/// Opens an exam screen, or the subscription screen once the 7 free days are
/// over. Used by the Tests tab and the TCF speaking practice entry.
Future<void> openV3Exam(
  BuildContext context,
  WidgetRef ref,
  WidgetBuilder builder, {
  bool fullscreenDialog = false,
}) async {
  final premium = V3Access.premium(ref);
  if (!premium) {
    final started = await V3FreeUsage.startedOn();
    if (!context.mounted) return;
    if (V3Access.examLocked(
      startedOn: started,
      now: DateTime.now(),
      premium: false,
    )) {
      final unlocked = await V3Access.openPaywall(
        context,
        ref,
        source: 'exam_locked',
      );
      if (!unlocked || !context.mounted) return;
    }
  }
  if (!context.mounted) return;
  await AppRouter.push<void>(
    context,
    builder,
    fullscreenDialog: fullscreenDialog,
  );
}

/// "Free for N more days" under the Tests heading, or the locked note.
class V3ExamFreeNote extends ConsumerWidget {
  const V3ExamFreeNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (V3Access.premium(ref)) return const SizedBox.shrink();
    return FutureBuilder<DateTime>(
      future: V3FreeUsage.startedOn(),
      builder: (context, snap) {
        final started = snap.data;
        if (started == null) return const SizedBox.shrink();
        final left = V3Access.examDaysLeft(started, DateTime.now());
        final text = left == 0
            ? 'Your free week is over. Subscribe to keep practising.'
            : left == 1
            ? 'Free for 1 more day.'
            : 'Free for $left more days.';
        return Semantics(
          label: text,
          child: Text(
            text,
            key: const ValueKey('tests.freeNote'),
            style: V3Type.strong(14, DesignTokens.primary),
          ),
        );
      },
    );
  }
}
