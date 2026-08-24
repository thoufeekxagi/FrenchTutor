import 'package:flutter/material.dart';

import 'speak_ui.dart';
import '../../design/tokens.dart';

class SpeakChallengeScreen extends StatelessWidget {
  const SpeakChallengeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          const SpeakHeader(
            title: 'Challenge',
            subtitle: 'Small goals. Real speaking progress.',
          ),
          const SizedBox(height: 22),
          SpeakCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: SpeakColors.orange,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: Colors.white,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Speak for 7 days',
                        style: DesignTokens.body(16, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You have completed 3 of 7 days.',
                        style: DesignTokens.body(
                          12,
                        ).copyWith(color: SpeakColors.inkSoft),
                      ),
                      const SizedBox(height: 9),
                      const SpeakProgressBar(value: 0.43),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const SpeakSectionTitle(title: 'Challenges'),
          const SizedBox(height: 12),
          _challenge(
            icon: Icons.mic_rounded,
            color: SpeakColors.accent,
            title: 'Make 10 minutes count',
            subtitle: 'Speak aloud for ten minutes this week.',
            progress: 0.6,
          ),
          const SizedBox(height: 10),
          _challenge(
            icon: Icons.chat_bubble_rounded,
            color: SpeakColors.green,
            title: 'Three real conversations',
            subtitle: 'Complete three Free Talk roleplays.',
            progress: 0.33,
          ),
          const SizedBox(height: 10),
          _challenge(
            icon: Icons.local_fire_department_rounded,
            color: SpeakColors.orange,
            title: 'Keep the streak alive',
            subtitle: 'Practise on five different days.',
            progress: 0.2,
          ),
          const SizedBox(height: 26),
          SpeakSectionTitle(title: 'Leagues', action: 'Coming soon'),
          const SizedBox(height: 12),
          SpeakCard(
            child: Row(
              children: [
                Icon(Icons.groups_rounded, color: SpeakColors.accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Compare your speaking momentum with other learners.',
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: SpeakColors.inkSoft),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _challenge({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required double progress,
  }) {
    return SpeakCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 21),
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
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: DesignTokens.body(
                    11.5,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
                const SizedBox(height: 9),
                SpeakProgressBar(value: progress),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(progress * 100).round()}%',
            style: DesignTokens.body(
              11,
              weight: FontWeight.w700,
            ).copyWith(color: SpeakColors.accent),
          ),
        ],
      ),
    );
  }
}
