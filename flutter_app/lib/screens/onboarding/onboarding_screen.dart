import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../models/profile.dart';
import '../../models/tutor_persona.dart';
import '../../services/tutor_voice_preview.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/passeport_primary_button.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  /// Called after the profile is saved. The hosting [AuthGate] re-evaluates
  /// and shows the next gate (sign-in for a fresh learner, home if already
  /// signed in) — onboarding never navigates on its own, so the gate always
  /// stays mounted and in control.
  final VoidCallback onFinished;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;
  String? _goal;
  String? _level;
  String _sessionLength = 'standard';
  TutorPersona? _tutorChoice;
  late final TutorVoicePreviewer _previewer = TutorVoicePreviewer()
    ..addListener(() {
      if (mounted) setState(() {});
    });

  @override
  void dispose() {
    _previewer.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    _previewer.stop();
    PSHaptics.selection();
    _pageController.nextPage(
      duration: DesignTokens.durationMedium,
      curve: DesignTokens.curveStandard,
    );
  }

  void _finish() {
    final store = ref.read(learningStoreProvider);
    final Profile profile = store.profile()
      ..goal = _goal ?? 'unsure'
      ..level = _level ?? 'unsure'
      ..sessionLength = _sessionLength
      ..onboardedAt = DateTime.now();
    store.saveProfile(profile);
    ActiveTutor.set(_tutorChoice ?? TutorPersona.marie);
    // The English/French mix is derived from level instead of being its own
    // question (A1/A2 gentle, B1 balanced, B2 immersion) — adjustable anytime
    // in Settings.
    TutorTuning.saveLanguageMix(
      LearnerLevel.defaultLanguageMix(_level ?? 'a1'),
    );
    _previewer.stop();
    PSHaptics.success();
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchment,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  Text(
                    'PARLESPRINT',
                    style: Passeport.body(
                      11,
                      weight: FontWeight.w800,
                    ).copyWith(color: Passeport.maroon, letterSpacing: 1.2),
                  ),
                  const Spacer(),
                  Text(
                    '${_page + 1} of 4',
                    style: Passeport.body(
                      12,
                      weight: FontWeight.w600,
                    ).copyWith(color: Passeport.slateDim),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: List.generate(4, (index) {
                  return Expanded(
                    child: AnimatedContainer(
                      duration: DesignTokens.durationFast,
                      height: 4,
                      margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
                      decoration: BoxDecoration(
                        color: index <= _page
                            ? Passeport.maroon
                            : Passeport.parchmentDim,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _page = index),
                children: [_goalStep(), _levelStep(), _tutorStep(), _firstSessionStep()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step({
    required String eyebrow,
    required String title,
    required String subtitle,
    required List<Widget> children,
    required Widget footer,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 24, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Passeport.infoSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_stepIcon, color: Passeport.sky, size: 22),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    eyebrow.toUpperCase(),
                    style: Passeport.body(
                      10.5,
                      weight: FontWeight.w800,
                    ).copyWith(color: Passeport.sky, letterSpacing: 1),
                  ),
                  const SizedBox(height: 7),
                  Text(title, style: Passeport.display(30)),
                  const SizedBox(height: 9),
                  Text(
                    subtitle,
                    style: Passeport.body(
                      15,
                    ).copyWith(color: Passeport.slateDim, height: 1.45),
                  ),
                  const SizedBox(height: 26),
                  ...children,
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          footer,
        ],
      ),
    );
  }

  IconData get _stepIcon => switch (_page) {
    0 => CupertinoIcons.scope,
    1 => CupertinoIcons.slider_horizontal_3,
    2 => CupertinoIcons.person_2_fill,
    _ => CupertinoIcons.sparkles,
  };

  Widget _choice({
    required String label,
    required String detail,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          PSHaptics.selection();
          onTap();
        },
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            // Primary (palette blue) for selection — matches the app's action
            // color everywhere else instead of the old near-black.
            color: selected ? Passeport.primary : Passeport.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? Passeport.primary : Passeport.hairline,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Passeport.body(15, weight: FontWeight.w700)
                          .copyWith(
                            color: selected ? Colors.white : Passeport.ink,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: Passeport.body(12.5).copyWith(
                        color: selected ? Colors.white70 : Passeport.slateDim,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[trailing, const SizedBox(width: 10)],
              Icon(
                selected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                color: selected ? Colors.white : Passeport.slate,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goalStep() {
    return _step(
      eyebrow: 'Your goal',
      title: 'What should French unlock for you?',
      subtitle:
          'Your answer shapes the examples, daily plan, and feedback you receive.',
      children: [
        _choice(
          label: 'TEF / TCF Canada',
          detail: 'Build toward an immigration language score',
          selected: _goal == 'tef_canada',
          onTap: () => setState(() => _goal = 'tef_canada'),
        ),
        _choice(
          label: 'Everyday French',
          detail: 'Speak with more confidence in daily life',
          selected: _goal == 'everyday',
          onTap: () => setState(() => _goal = 'everyday'),
        ),
        _choice(
          label: 'Build the foundations',
          detail: 'Start broadly and choose a goal later',
          selected: _goal == 'unsure',
          onTap: () => setState(() => _goal = 'unsure'),
        ),
      ],
      footer: PasseportPrimaryButton(
        label: 'Continue',
        onPressed: _goal == null ? null : _next,
        icon: CupertinoIcons.arrow_right,
      ),
    );
  }

  Widget _levelStep() {
    return _step(
      eyebrow: 'Starting point',
      title: 'Where are you today?',
      subtitle:
          'Choose the closest answer. The plan will adjust as you create real evidence.',
      children: [
        _choice(
          label: 'A1 — Just starting',
          detail: 'Little or no French yet; I need the essentials',
          selected: _level == 'a1',
          onTap: () => setState(() => _level = 'a1'),
        ),
        _choice(
          label: 'A2 — I know the basics',
          detail: 'Simple phrases and everyday words, but I hesitate',
          selected: _level == 'a2',
          onTap: () => setState(() => _level = 'a2'),
        ),
        _choice(
          label: 'B1 — I can hold a conversation',
          detail: 'I manage everyday situations and want more range',
          selected: _level == 'b1',
          onTap: () => setState(() => _level = 'b1'),
        ),
        _choice(
          label: 'B2 — I\'m comfortable, polishing',
          detail: 'I discuss most topics and want exam-level accuracy',
          selected: _level == 'b2',
          onTap: () => setState(() => _level = 'b2'),
        ),
        const SizedBox(height: 12),
        Text(
          'A comfortable daily session',
          style: Passeport.body(13, weight: FontWeight.w600),
        ),
        const SizedBox(height: 9),
        PSSegmented<String>(
          segments: const [
            (value: 'quick', label: '5 min'),
            (value: 'standard', label: '15 min'),
            (value: 'deep', label: '30 min'),
          ],
          selected: _sessionLength,
          onChanged: (value) => setState(() => _sessionLength = value),
        ),
      ],
      footer: PasseportPrimaryButton(
        label: 'Build my plan',
        onPressed: _level == null ? null : _next,
        icon: CupertinoIcons.arrow_right,
      ),
    );
  }

  /// Round play/stop button on each tutor card — hears the tutor's sample in
  /// their real voice before choosing.
  Widget _previewButton(TutorPersona p) {
    final loading = _previewer.loadingId == p.id;
    final playing = _previewer.playingId == p.id;
    return Semantics(
      button: true,
      label: playing
          ? 'Stop ${p.displayName}\'s voice sample'
          : 'Play ${p.displayName}\'s voice sample',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          PSHaptics.selection();
          _previewer.play(p);
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: playing ? Passeport.maroon : Passeport.infoSoft,
            shape: BoxShape.circle,
          ),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Passeport.sky,
                  ),
                )
              : Icon(
                  playing ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill,
                  size: 16,
                  color: playing ? Colors.white : Passeport.sky,
                ),
        ),
      ),
    );
  }

  Widget _tutorStep() {
    Widget group(TutorAccent accent, String detailSuffix) {
      final pair = TutorPersona.byAccent(accent);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${accent.label} French'.toUpperCase(),
            style: Passeport.body(
              10.5,
              weight: FontWeight.w800,
            ).copyWith(color: Passeport.maroon, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          for (final p in pair)
            _choice(
              label: p.displayName,
              detail: '${p.tagline} — $detailSuffix',
              selected: _tutorChoice?.id == p.id,
              onTap: () => setState(() => _tutorChoice = p),
              trailing: _previewButton(p),
            ),
        ],
      );
    }

    return _step(
      eyebrow: 'Your tutor',
      title: 'Who will you practice with?',
      subtitle:
          'Tap ▶ to hear each tutor, then choose. France French is what most '
          'exams use; Québec French is what you\'ll hear across Canada. You '
          'can switch tutors anytime in Settings.',
      children: [
        group(TutorAccent.france, 'standard metropolitan French'),
        const SizedBox(height: 10),
        group(TutorAccent.quebec, 'natural Québécois French'),
      ],
      footer: PasseportPrimaryButton(
        label: 'Continue',
        onPressed: _tutorChoice == null ? null : _next,
        icon: CupertinoIcons.arrow_right,
      ),
    );
  }

  Widget _firstSessionStep() {
    return _step(
      eyebrow: 'Ready to begin',
      title: 'One clear next step, every day.',
      subtitle:
          'ParleSprint will connect vocabulary, grammar, comprehension, writing, and a short conversation with ${(_tutorChoice ?? TutorPersona.marie).displayName}.',
      children: [
        _PromiseRow(
          icon: CupertinoIcons.scope,
          title: 'Chosen for your goal',
          detail: 'Each recommendation explains why it comes next.',
        ),
        _PromiseRow(
          icon: CupertinoIcons.waveform,
          title: 'Speaking built into the path',
          detail:
              '${(_tutorChoice ?? TutorPersona.marie).displayName} helps you use what you just learned.',
        ),
        _PromiseRow(
          icon: CupertinoIcons.chart_bar_alt_fill,
          title: 'Progress backed by evidence',
          detail: 'No invented scores or pressure-driven streaks.',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Passeport.successSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(
                CupertinoIcons.mic_fill,
                color: Passeport.sage,
                size: 19,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Microphone access is requested only when your first speaking activity begins.',
                  style: Passeport.body(
                    12.5,
                  ).copyWith(color: Passeport.inkSoft, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
      footer: PasseportPrimaryButton(
        label: 'Continue',
        onPressed: _finish,
        icon: CupertinoIcons.arrow_right,
      ),
    );
  }
}

class _PromiseRow extends StatelessWidget {
  const _PromiseRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Passeport.infoSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Passeport.sky, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Passeport.body(14, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Passeport.body(
                    12.5,
                  ).copyWith(color: Passeport.slateDim, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
