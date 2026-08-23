import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../services/alphabet_prewarm.dart';
import '../../services/notification_scheduler_service.dart';
import '../../widgets/v3/v3_surface.dart';

/// First-run setup in the same dark, focused language as the learning
/// surfaces. It writes the same profile fields and adaptive-plan contract as
/// the previous funnel, but keeps the decisions in one short, reversible flow.
class V3OnboardingScreen extends ConsumerStatefulWidget {
  const V3OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  ConsumerState<V3OnboardingScreen> createState() => _V3OnboardingScreenState();
}

class _V3OnboardingScreenState extends ConsumerState<V3OnboardingScreen> {
  var _step = 0;
  var _goal = 'tef_canada';
  var _level = 'a1';
  var _minutes = '10';
  var _reminders = true;
  var _tutor = TutorPersona.defaultPersona;
  final _focus = <String>{
    'Speaking',
    'Listening',
    'Reading',
    'Writing',
    'Vocabulary',
  };

  Future<void> _finish() async {
    final store = ref.read(learningStoreProvider);
    final profile = store.profile()
      ..goal = _goal
      ..level = _level
      ..sessionLength = switch (_minutes) {
        '5' => 'quick',
        '20' => 'deep',
        _ => 'standard',
      }
      ..interests = _focus.toList()
      ..reminderTime = _reminders ? '19:00' : null
      ..preferredDays = _reminders
          ? const ['mon', 'tue', 'wed', 'thu', 'fri']
          : const []
      ..onboardingVersion = 'v3-personal-study-plan'
      ..onboardedAt = DateTime.now();
    store.saveProfile(profile);
    unawaited(NotificationSchedulerService.sync(profile));
    ref.read(adaptiveCourseStoreProvider).ensureCurrentPlan(profile);
    await ActiveTutor.set(_tutor);
    await TutorTuning.saveLanguageMix(LearnerLevel.defaultLanguageMix(_level));
    AlphabetPrewarm.maybeStart(isBeginner: _level == 'a1');
    widget.onFinished();
  }

  void _next() {
    if (_step == 3) {
      unawaited(_finish());
      return;
    }
    setState(() => _step += 1);
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step -= 1);
  }

  @override
  Widget build(BuildContext context) {
    return V3Scaffold(
      child: Column(
        children: [
          V3Header(
            title: _step == 0 ? 'Welcome to ParleSprint' : 'Make it yours',
            subtitle: _step == 0
                ? 'A small daily path to confident French.'
                : 'Step ${_step + 1} of 4',
            leading: _step == 0 ? null : V3BackButton(onPressed: _back),
            trailing: _step == 0
                ? null
                : Text(
                    '${_step + 1}/4',
                    style: DesignTokens.body(
                      12,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.nightAccent),
                  ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: SingleChildScrollView(
                key: ValueKey(_step),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: _page(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: V3PrimaryButton(
              label: _step == 3 ? 'Start learning' : 'Continue',
              icon: _step == 3 ? Icons.arrow_forward_rounded : null,
              onPressed: _next,
            ),
          ),
        ],
      ),
    );
  }

  Widget _page() {
    return switch (_step) {
      0 => _welcomePage(),
      1 => _planPage(),
      2 => _focusPage(),
      _ => _readyPage(),
    };
  }

  Widget _welcomePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Icon(
          Icons.auto_awesome_rounded,
          color: DesignTokens.nightAccent,
          size: 46,
        ),
        const SizedBox(height: 26),
        Text(
          'Learn French in the moments you actually have.',
          style: DesignTokens.display(
            34,
          ).copyWith(color: DesignTokens.nightText, height: 1.08),
        ),
        const SizedBox(height: 16),
        Text(
          'We will build your first 20-session pathway, then adapt the next block as your progress changes. Reading, listening, speaking, writing, grammar, and vocabulary stay connected.',
          style: DesignTokens.body(
            16,
          ).copyWith(color: DesignTokens.nightMuted, height: 1.45),
        ),
        const SizedBox(height: 24),
        const V3Card(
          child: Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: DesignTokens.nightAccent),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You can change these choices later in Settings.',
                  style: TextStyle(
                    color: DesignTokens.nightMuted,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _planPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Set the starting point.',
          style: DesignTokens.display(
            28,
          ).copyWith(color: DesignTokens.nightText),
        ),
        const SizedBox(height: 8),
        Text(
          'Every generated lesson respects this level and goal. A1 stays clear and practical; B2 can work with nuance and speed.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.nightMuted, height: 1.4),
        ),
        const SizedBox(height: 22),
        V3Row(
          icon: Icons.flag_outlined,
          title: 'Current level',
          subtitle: 'The language complexity you will hear and produce',
          value: LearnerLevel.displayLabel(_level),
          onTap: () async {
            final value = await showV3Picker<String>(
              context: context,
              title: 'Current level',
              selected: _level,
              options: const [
                V3PickerOption(
                  value: 'a1',
                  label: 'A1',
                  description: 'Starting out',
                ),
                V3PickerOption(
                  value: 'a2',
                  label: 'A2',
                  description: 'Everyday basics',
                ),
                V3PickerOption(
                  value: 'b1',
                  label: 'B1',
                  description: 'Independent speaker',
                ),
                V3PickerOption(
                  value: 'b2',
                  label: 'B2',
                  description: 'Confident and nuanced',
                ),
              ],
            );
            if (value != null) setState(() => _level = value);
          },
        ),
        const SizedBox(height: 9),
        V3Row(
          icon: Icons.track_changes_rounded,
          title: 'Main goal',
          subtitle: 'The reason your pathway should keep coming back to you',
          value: _goal == 'tef_canada' ? 'TEF Canada' : 'Everyday French',
          onTap: () async {
            final value = await showV3Picker<String>(
              context: context,
              title: 'Main goal',
              selected: _goal,
              options: const [
                V3PickerOption(
                  value: 'tef_canada',
                  label: 'TEF Canada',
                  description: 'Exam-ready skills',
                ),
                V3PickerOption(
                  value: 'everyday',
                  label: 'Everyday French',
                  description: 'Useful daily conversation',
                ),
              ],
            );
            if (value != null) setState(() => _goal = value);
          },
        ),
        const SizedBox(height: 9),
        V3Row(
          icon: Icons.timer_outlined,
          title: 'Time per session',
          subtitle: 'Your daily recommendation',
          value: '$_minutes min',
          onTap: () async {
            final value = await showV3Picker<String>(
              context: context,
              title: 'Time per session',
              selected: _minutes,
              options: const [
                V3PickerOption(
                  value: '5',
                  label: 'Quick',
                  description: '5 minutes',
                ),
                V3PickerOption(
                  value: '10',
                  label: 'Standard',
                  description: '10 minutes',
                ),
                V3PickerOption(
                  value: '20',
                  label: 'Deep',
                  description: '20 minutes',
                ),
              ],
            );
            if (value != null) setState(() => _minutes = value);
          },
        ),
      ],
    );
  }

  Widget _focusPage() {
    const choices = [
      ('Speaking', Icons.mic_none_rounded),
      ('Listening', Icons.headphones_outlined),
      ('Reading', Icons.menu_book_outlined),
      ('Writing', Icons.edit_note_rounded),
      ('Grammar', Icons.auto_fix_high_outlined),
      ('Vocabulary', Icons.style_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose your emphasis.',
          style: DesignTokens.display(
            28,
          ).copyWith(color: DesignTokens.nightText),
        ),
        const SizedBox(height: 8),
        Text(
          'The full course stays connected. These choices only decide what gets extra attention first.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.nightMuted, height: 1.4),
        ),
        const SizedBox(height: 22),
        for (final choice in choices) ...[
          V3Card(
            raised: _focus.contains(choice.$1),
            borderColor: _focus.contains(choice.$1)
                ? DesignTokens.nightAccent
                : null,
            onTap: () => setState(() {
              if (_focus.contains(choice.$1)) {
                if (_focus.length > 1) _focus.remove(choice.$1);
              } else {
                _focus.add(choice.$1);
              }
            }),
            child: Row(
              children: [
                Icon(choice.$2, color: DesignTokens.nightAccent),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    choice.$1,
                    style: DesignTokens.body(
                      15,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.nightText),
                  ),
                ),
                Icon(
                  _focus.contains(choice.$1)
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: _focus.contains(choice.$1)
                      ? DesignTokens.nightAccent
                      : DesignTokens.nightMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _readyPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your first pathway is ready.',
          style: DesignTokens.display(
            28,
          ).copyWith(color: DesignTokens.nightText),
        ),
        const SizedBox(height: 8),
        Text(
          'Meet your tutor, then start with one useful session. Your next block will be generated from what you complete and what still needs practice.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.nightMuted, height: 1.4),
        ),
        const SizedBox(height: 22),
        V3Row(
          icon: Icons.record_voice_over_outlined,
          title: _tutor.displayName,
          subtitle: _tutor.tagline,
          value: _tutor.accent.label,
          onTap: () async {
            final value = await showV3Picker<TutorPersona>(
              context: context,
              title: 'Choose your tutor',
              selected: _tutor,
              options: [
                for (final tutor in TutorPersona.all)
                  V3PickerOption(
                    value: tutor,
                    label: tutor.displayName,
                    description: tutor.tagline,
                    icon: tutor.isFemale
                        ? Icons.face_3_outlined
                        : Icons.face_outlined,
                  ),
              ],
            );
            if (value != null) setState(() => _tutor = value);
          },
        ),
        const SizedBox(height: 9),
        V3Card(
          padding: const EdgeInsets.fromLTRB(14, 8, 7, 8),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                color: DesignTokens.nightAccent,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  'Daily reminder at 7:00 PM',
                  style: DesignTokens.body(
                    15,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.nightText),
                ),
              ),
              V3Toggle(
                value: _reminders,
                onChanged: (value) => setState(() => _reminders = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        V3Card(
          raised: true,
          child: Text(
            '${LearnerLevel.displayLabel(_level)} · ${_goal == 'tef_canada' ? 'TEF Canada' : 'Everyday French'} · $_minutes minutes\n${_focus.join(' · ')}',
            style: DesignTokens.body(
              14,
              weight: FontWeight.w700,
            ).copyWith(color: DesignTokens.nightText, height: 1.45),
          ),
        ),
      ],
    );
  }
}
