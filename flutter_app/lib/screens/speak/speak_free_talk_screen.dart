import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import 'speak_roleplay_screen.dart';
import 'speak_ui.dart';

class SpeakFreeTalkScreen extends ConsumerWidget {
  const SpeakFreeTalkScreen({super.key});

  Future<void> _openTopic(BuildContext context, String topic) async {
    await AppRouter.push(context, (_) => SpeakRoleplayScreen(topic: topic));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'Community',
                      style: DesignTokens.display(
                        18,
                        weight: FontWeight.w500,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                    const SizedBox(width: 12),
                    Text('Topics', style: DesignTokens.display(18)),
                  ],
                ),
              ),
              _roundIcon(Icons.history_rounded),
              const SizedBox(width: 8),
              _roundIcon(Icons.favorite_border_rounded),
            ],
          ),
          const SizedBox(height: 12),
          const SpeakPill(label: 'Roleplay', selected: false),
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: SpeakColors.line),
              ),
              child: Text(
                '1',
                style: DesignTokens.body(12, weight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _topicGrid(context),
          const SizedBox(height: 16),
          SpeakPrimaryButton(
            label: 'Create your own',
            icon: Icons.add_rounded,
            onTap: () => _openTopic(context, 'a roleplay you create'),
          ),
        ],
      ),
    );
  }

  Widget _roundIcon(IconData icon) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: SpeakColors.line),
      ),
      child: Icon(icon, size: 18, color: SpeakColors.inkSoft),
    );
  }

  Widget _topicGrid(BuildContext context) {
    const topics = [
      ('Meet a New Friend', Icons.people_alt_rounded, DesignTokens.info),
      ('At a Crêperie', Icons.restaurant_rounded, DesignTokens.mastery),
      ('At a Nike Store', Icons.shopping_bag_rounded, DesignTokens.inkSoft),
      ('At a Coffee Shop', Icons.local_cafe_rounded, DesignTokens.secondary),
      (
        'Ask for Directions',
        Icons.directions_walk_rounded,
        DesignTokens.primaryDeep,
      ),
      (
        'Make a Reservation',
        Icons.calendar_month_rounded,
        DesignTokens.success,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: topics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.9,
      ),
      itemBuilder: (context, index) {
        final topic = topics[index];
        return GestureDetector(
          onTap: () => _openTopic(context, topic.$1),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: topic.$3,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(topic.$2, color: Colors.white, size: 22),
                ),
                Text(
                  topic.$1,
                  style: DesignTokens.body(
                    14,
                    weight: FontWeight.w700,
                  ).copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
