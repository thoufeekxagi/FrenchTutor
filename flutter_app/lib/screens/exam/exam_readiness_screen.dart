import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/writing_lab_screen.dart';
import '../reading/reading_library_screen.dart';
import '../session/session_screen.dart';
import '../speak/speak_ui.dart';

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
      'French practice task with realistic timing, vocabulary, and difficulty.';

  void _prepare() => setState(() => _prepared = true);

  Future<void> _openSpeaking() async {
    final allowed = await ensureAiSessionQuota(
      context,
      ref.read(pilotAccessServiceProvider),
    );
    if (!allowed || !mounted) return;
    await AppRouter.push(
      context,
      (_) => SessionScreen(
        apiKey: ApiKeys.geminiKey,
        sessionTopic: '$_examName speaking readiness',
        contentKey: 'exam-readiness-${_exam.name}-$_level-speaking',
        stage: 'speaking_exam',
        lessonContext: _examContext,
        examMode: true,
      ),
      fullscreenDialog: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SpeakScaffold(
      child: Column(
        children: [
          SpeakHeader(
            title: 'Exam readiness',
            subtitle: 'Free TCF and TEF preparation',
            leading: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: const Icon(
                Icons.close_rounded,
                color: SpeakColors.inkSoft,
              ),
            ),
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
                    'Choose a skill to generate the next exam-matched task.',
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: SpeakColors.inkSoft),
                  ),
                  const SizedBox(height: 14),
                  _SkillLauncher(
                    icon: Icons.menu_book_outlined,
                    title: 'Reading',
                    subtitle: 'Generate an exam-style reading story',
                    onTap: () => AppRouter.push(
                      context,
                      (_) => ReadingLibraryScreen(topic: _examContext),
                    ),
                  ),
                  _SkillLauncher(
                    icon: Icons.headphones_outlined,
                    title: 'Listening',
                    subtitle: 'Generate an exam-style listening task',
                    onTap: () => AppRouter.push(
                      context,
                      (_) => ListeningLabScreen(topic: _examContext),
                    ),
                  ),
                  _SkillLauncher(
                    icon: Icons.edit_note_rounded,
                    title: 'Writing',
                    subtitle: 'Generate an exam-style writing prompt',
                    onTap: () => AppRouter.push(
                      context,
                      (_) => WritingLabScreen(
                        topic: _examName,
                        contextPrompt: _examContext,
                      ),
                    ),
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
