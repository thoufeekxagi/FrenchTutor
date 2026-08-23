import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/exam_practice.dart';
import '../../providers/database_provider.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/writing_lab_screen.dart';
import '../mocks/mocks_screen.dart';
import '../reading/reading_library_screen.dart';
import '../speak/speak_ui.dart';
import '../../services/premium_access_gate.dart';
import '../../services/subscription_gate_service.dart';
import '../../widgets/v3/v3_surface.dart';

enum _ExamFamily { tcf, tef }

/// Free exam-readiness launcher. The selected exam and level are passed into
/// the existing live content generators so exam practice stays on the same
/// saved reading, listening, writing, and speaking paths as the rest of the
/// app.
class ExamReadinessScreen extends ConsumerStatefulWidget {
  const ExamReadinessScreen({super.key});

  @override
  ConsumerState<ExamReadinessScreen> createState() =>
      _ExamReadinessScreenState();
}

class _ExamReadinessScreenState extends ConsumerState<ExamReadinessScreen> {
  _ExamFamily _exam = _ExamFamily.tcf;
  String _level = 'A2';
  bool _prepared = false;

  String get _examName =>
      _exam == _ExamFamily.tcf ? 'TCF Canada' : 'TEF Canada';

  String get _examContext =>
      '$_examName preparation at $_level level. Generate an exam-matched '
      'French practice task with realistic timing, vocabulary, and difficulty. '
      '${_level == 'A1' || _level == 'A2' ? 'This is guided training: use short French and brief English support when needed, without revealing answers.' : 'This is assessed practice: the examiner and task content must stay in French only, with no translation or coaching.'} '
      '${_exam == _ExamFamily.tef ? 'For speaking, use TEF-style information gathering and persuasion tasks.' : 'For speaking, use TCF-style exchange, interaction, and viewpoint tasks.'}';

  void _prepare() => setState(() => _prepared = true);

  Future<bool> _allowExamPractice() async {
    return requirePremiumArea(
      context,
      ref,
      PremiumArea.exam,
      source: 'exam_readiness',
    );
  }

  Future<void> _openReading() async {
    if (!await _allowExamPractice() || !mounted) return;
    await AppRouter.push(
      context,
      (_) => ReadingLibraryScreen(
        topic: _examContext,
        examName: _examName,
        examLevel: _level,
        examMode: true,
        autoStart: true,
      ),
      fullscreenDialog: true,
    );
  }

  Future<void> _openListening() async {
    if (!await _allowExamPractice() || !mounted) return;
    await AppRouter.push(
      context,
      (_) => ListeningLabScreen(
        topic: _examContext,
        examName: _examName,
        examLevel: _level,
        examMode: true,
        autoStart: true,
      ),
      fullscreenDialog: true,
    );
  }

  Future<void> _openSpeaking() async {
    if (!await _allowExamPractice() || !mounted) return;
    final attemptId = ref
        .read(examPracticeStoreProvider)
        .startMetadata(
          examName: _examName,
          levelBand: _level,
          skill: 'speaking',
          content: {'kind': 'speaking', 'context': _examContext},
        );
    final result = await AppRouter.push<SpeakingMockResult>(
      context,
      (_) => MocksScreen(
        examName: _examName,
        levelBand: _level,
        includeReadingWarmup: false,
      ),
      fullscreenDialog: true,
    );
    if (result != null && result.completed) {
      ref
          .read(examPracticeStoreProvider)
          .complete(
            id: attemptId,
            score: result.score.round().clamp(0, 10),
            total: 10,
          );
    }
  }

  Future<void> _openWriting() async {
    if (!await _allowExamPractice() || !mounted) return;
    await AppRouter.push<bool>(
      context,
      (_) => WritingLabScreen(
        topic: _examName,
        contextPrompt: _examContext,
        examName: _examName,
        examLevel: _level,
        examMode: true,
        autoStart: true,
      ),
      fullscreenDialog: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return V3Scaffold(
      child: Column(
        children: [
          V3Header(
            title: 'Exam readiness',
            subtitle: 'Free TCF and TEF preparation',
            leading: const V3BackButton(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Text(
                  'Build a focused practice set.',
                  style: DesignTokens.display(28),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose the exam and difficulty. Each skill then opens the current live generator and saves the practice for you.',
                  style: DesignTokens.body(
                    14,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                ),
                const SizedBox(height: 24),
                Text(
                  'EXAM',
                  style: DesignTokens.label(
                    10,
                  ).copyWith(color: SpeakColors.inkSoft, letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _ChoiceCard(
                        title: 'TCF Canada',
                        subtitle: 'General French test',
                        selected: _exam == _ExamFamily.tcf,
                        onTap: () => setState(() => _exam = _ExamFamily.tcf),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ChoiceCard(
                        title: 'TEF Canada',
                        subtitle: 'French assessment test',
                        selected: _exam == _ExamFamily.tef,
                        onTap: () => setState(() => _exam = _ExamFamily.tef),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'DIFFICULTY',
                  style: DesignTokens.label(
                    10,
                  ).copyWith(color: SpeakColors.inkSoft, letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final level in const ['A1', 'A2', 'B1', 'B2'])
                      SpeakPill(
                        label: level,
                        selected: _level == level,
                        onTap: () => setState(() => _level = level),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                SpeakCard(
                  color: SpeakColors.blueSoft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.verified_outlined,
                        color: SpeakColors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Free readiness practice. Your choice is used to calibrate the live content; it does not change your course level.',
                          style: DesignTokens.body(
                            13,
                          ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _RecentExamPractice(
                  attempts: ref.read(examPracticeStoreProvider).summaries(),
                ),
                if (!_prepared)
                  SpeakPrimaryButton(
                    label: 'Generate $_examName practice',
                    icon: Icons.auto_awesome_rounded,
                    onTap: _prepare,
                  )
                else ...[
                  Text('$_examName · $_level', style: DesignTokens.display(22)),
                  const SizedBox(height: 6),
                  Text(
                    'Choose a skill to start an independent exam practice set. Your result stays here, not in the course library.',
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: SpeakColors.inkSoft),
                  ),
                  const SizedBox(height: 14),
                  _SkillLauncher(
                    icon: Icons.menu_book_outlined,
                    title: 'Reading',
                    subtitle: 'Start an exam-style reading QCM',
                    onTap: _openReading,
                  ),
                  _SkillLauncher(
                    icon: Icons.headphones_outlined,
                    title: 'Listening',
                    subtitle: 'Start a one-play exam listening QCM',
                    onTap: _openListening,
                  ),
                  _SkillLauncher(
                    icon: Icons.edit_note_rounded,
                    title: 'Writing',
                    subtitle: 'Start an exam-style writing task',
                    onTap: _openWriting,
                  ),
                  _SkillLauncher(
                    icon: Icons.mic_none_rounded,
                    title: 'Speaking',
                    subtitle: 'Start a timed live examiner session',
                    onTap: _openSpeaking,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? SpeakColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? SpeakColors.blue : SpeakColors.line,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: DesignTokens.body(
                14,
                weight: FontWeight.w700,
              ).copyWith(color: selected ? Colors.white : SpeakColors.navy),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: DesignTokens.body(11).copyWith(
                color: selected ? Colors.white70 : SpeakColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillLauncher extends StatelessWidget {
  const _SkillLauncher({
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: SpeakCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: SpeakColors.blueSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: SpeakColors.blue, size: 20),
              ),
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
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: SpeakColors.inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentExamPractice extends StatelessWidget {
  const _RecentExamPractice({required this.attempts});

  final List<ExamPracticeSummary> attempts;

  @override
  Widget build(BuildContext context) {
    if (attempts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: SpeakCard(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RECENT READINESS', style: DesignTokens.label(10)),
            const SizedBox(height: 8),
            for (final attempt in attempts.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Icon(
                      attempt.isCompleted
                          ? Icons.check_circle_outline_rounded
                          : Icons.timelapse_rounded,
                      size: 17,
                      color: attempt.isCompleted
                          ? SpeakColors.green
                          : SpeakColors.inkSoft,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${attempt.examName} · ${attempt.skill[0].toUpperCase()}${attempt.skill.substring(1)} · ${attempt.levelBand}',
                        style: DesignTokens.body(12),
                      ),
                    ),
                    if (attempt.score != null && attempt.total != null)
                      Text(
                        '${attempt.score}/${attempt.total}',
                        style: DesignTokens.body(
                          12,
                          weight: FontWeight.w700,
                        ).copyWith(color: SpeakColors.blue),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
