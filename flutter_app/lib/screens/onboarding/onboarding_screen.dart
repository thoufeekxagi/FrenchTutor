import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../design/app_router.dart';
import '../../models/profile.dart';
import '../../providers/database_provider.dart';
import '../main_tab_screen.dart';

/// First-run onboarding — three light steps, under a minute, one question per
/// screen (PILOT_PLAN.md Phase 3). Writes the profile that drives queue
/// budgets (session length), Marie's language ratio (level), and the header
/// (goal). No permissions are requested here: the mic prompt happens in
/// context, right before the learner's first spoken attempt.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  String? _goal;
  String? _level;
  String _sessionLength = 'standard';

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    _pageController.nextPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  void _finish() {
    final store = ref.read(learningStoreProvider);
    final Profile profile = store.profile()
      ..goal = _goal ?? 'unsure'
      ..level = _level ?? 'unsure'
      ..sessionLength = _sessionLength
      ..onboardedAt = DateTime.now();
    store.saveProfile(profile);
    AppRouter.pushReplacement(context, (_) => const MainTabScreen());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchment,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _progressDots(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [_goalStep(), _levelStep(), _firstSessionStep()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        return Container(
          width: i == _page ? 22 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: i <= _page ? Passeport.maroon : Passeport.hairline,
            borderRadius: BorderRadius.circular(100),
          ),
        );
      }),
    );
  }

  Widget _step({required String kicker, required String title, String? subtitle, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(kicker.toUpperCase(),
              style: Passeport.mono(10, weight: FontWeight.w600).copyWith(color: Passeport.brass, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Text(title, style: Passeport.display(26, weight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle, style: Passeport.body(13.5).copyWith(color: Passeport.slateDim)),
          ],
          const SizedBox(height: 24),
          ...children,
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _choice({required String label, String? detail, required bool selected, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? Passeport.ink : Passeport.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? Passeport.ink : Passeport.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Passeport.body(14, weight: FontWeight.w500)
                      .copyWith(color: selected ? Passeport.parchment : Passeport.text)),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(detail,
                    style: Passeport.body(11.5)
                        .copyWith(color: selected ? Passeport.slate : Passeport.slateDim)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- Step 1: goal ---
  Widget _goalStep() {
    return _step(
      kicker: 'ParleSprint',
      title: 'What brings you to French?',
      children: [
        _choice(
          label: 'TEF / TCF Canada',
          detail: 'Exam prep, CLB-aligned',
          selected: _goal == 'tef_canada',
          onTap: () {
            setState(() => _goal = 'tef_canada');
            _next();
          },
        ),
        _choice(
          label: 'Everyday French',
          detail: 'Conversation, travel, life',
          selected: _goal == 'everyday',
          onTap: () {
            setState(() => _goal = 'everyday');
            _next();
          },
        ),
        _choice(
          label: 'Not sure yet',
          detail: "We'll start with the fundamentals",
          selected: _goal == 'unsure',
          onTap: () {
            setState(() => _goal = 'unsure');
            _next();
          },
        ),
      ],
    );
  }

  // --- Step 2: level + pace on one screen ---
  Widget _levelStep() {
    return _step(
      kicker: 'Your starting point',
      title: 'How much French do you have?',
      children: [
        _choice(
          label: 'Starting from zero',
          selected: _level == 'zero',
          onTap: () => setState(() => _level = 'zero'),
        ),
        _choice(
          label: 'I know some basics',
          selected: _level == 'basics',
          onTap: () => setState(() => _level = 'basics'),
        ),
        _choice(
          label: 'I can hold a simple conversation',
          selected: _level == 'conversational',
          onTap: () => setState(() => _level = 'conversational'),
        ),
        const SizedBox(height: 14),
        Text('A usual session for you', style: Passeport.body(12.5).copyWith(color: Passeport.slateDim)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (value, label) in [('quick', 'Quick · 5 min'), ('standard', 'Standard · 15'), ('deep', 'Deep · 30')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _sessionLength = value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _sessionLength == value ? Passeport.maroon : Passeport.card,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                          color: _sessionLength == value ? Passeport.maroon : Passeport.hairline),
                    ),
                    child: Text(label,
                        style: Passeport.mono(10.5, weight: FontWeight.w500).copyWith(
                            color: _sessionLength == value ? Passeport.parchment : Passeport.text)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: _level != null ? _next : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Passeport.maroon,
              foregroundColor: Passeport.parchment,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Continue', style: Passeport.body(14, weight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }

  // --- Step 3: what happens next (first success framing, no feature tour) ---
  Widget _firstSessionStep() {
    return _step(
      kicker: 'Your first session',
      title: 'Three words. One short chat.',
      subtitle: "Today you'll learn three useful words, hear each one spoken, "
          "and use one in a short conversation with Marie, your tutor. "
          "About two minutes — that's the whole thing.",
      children: [
        Row(
          children: [
            const Icon(Icons.mic_none, size: 16, color: Passeport.brass),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "We'll ask for the microphone only when it's your turn to speak.",
                style: Passeport.body(12).copyWith(color: Passeport.slateDim),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: _finish,
            style: ElevatedButton.styleFrom(
              backgroundColor: Passeport.maroon,
              foregroundColor: Passeport.parchment,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Start learning', style: Passeport.body(14, weight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }
}
