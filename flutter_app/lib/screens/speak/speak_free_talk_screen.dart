import 'package:flutter/material.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/speaking_course.dart';
import 'speak_roleplay_screen.dart';

/// Speak-style roleplay catalog. It is deliberately a catalog, not another
/// speaking home: the learner chooses a scene here, previews its goal, then
/// enters the shared roleplay conversation.
class SpeakFreeTalkScreen extends StatefulWidget {
  const SpeakFreeTalkScreen({super.key});

  @override
  State<SpeakFreeTalkScreen> createState() => _SpeakFreeTalkScreenState();
}

class _SpeakFreeTalkScreenState extends State<SpeakFreeTalkScreen> {
  String _filter = 'Hot';

  Future<void> _openTopic(
    BuildContext context,
    SpeakingCourseLesson lesson,
  ) async {
    await AppRouter.push(
      context,
      (_) => SpeakRoleplayScreen(lesson: lesson),
      fullscreenDialog: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: DesignTokens.nightText,
                  ),
                ),
                const SizedBox(width: 4),
                Text('Roleplay', style: _display(25)),
                const Spacer(),
                _roundIcon(Icons.history_rounded, 'History'),
                const SizedBox(width: 8),
                _roundIcon(Icons.favorite_border_rounded, 'Saved'),
              ],
            ),
            const SizedBox(height: 22),
            Text('Practice a real situation', style: _display(29)),
            const SizedBox(height: 7),
            Text(
              'Choose a scene, see the goal, then speak with your tutor one turn at a time.',
              style: _body(
                14,
              ).copyWith(color: DesignTokens.nightMuted, height: 1.35),
            ),
            const SizedBox(height: 22),
            _filterRow(),
            const SizedBox(height: 16),
            Text('ROLEPLAY TOPICS', style: _label(12)),
            const SizedBox(height: 10),
            _topicGrid(context),
          ],
        ),
      ),
    );
  }

  Widget _filterRow() {
    return Row(
      children: [
        for (final filter in const ['Hot', 'New', 'Top today']) ...[
          GestureDetector(
            onTap: () => setState(() => _filter = filter),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: _filter == filter
                    ? DesignTokens.nightAccent
                    : DesignTokens.nightSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _filter == filter
                      ? DesignTokens.nightAccent
                      : DesignTokens.nightHairline,
                ),
              ),
              child: Text(
                filter,
                style: _body(12, weight: FontWeight.w800).copyWith(
                  color: _filter == filter
                      ? Colors.black
                      : DesignTokens.nightMuted,
                ),
              ),
            ),
          ),
          if (filter != 'Top today') const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _roundIcon(IconData icon, String label) {
    return Semantics(
      button: true,
      label: label,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          shape: BoxShape.circle,
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        child: Icon(icon, size: 18, color: DesignTokens.nightText),
      ),
    );
  }

  Widget _topicGrid(BuildContext context) {
    final topics = SpeakingCourseCatalog.roleplays;
    const colors = [
      Color(0xFFB97920),
      Color(0xFF24489A),
      Color(0xFF3C4A67),
      Color(0xFF177F7B),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: topics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.93,
      ),
      itemBuilder: (context, index) {
        final topic = topics[index];
        return GestureDetector(
          onTap: () => _openTopic(context, topic),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors[index % colors.length],
              borderRadius: BorderRadius.circular(20),
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
                  child: Icon(topic.icon, color: Colors.white, size: 22),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.title,
                      style: _body(15, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${topic.lines.length} turns · ${topic.level}',
                      style: _body(11).copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  TextStyle _display(double size) =>
      DesignTokens.display(size).copyWith(color: DesignTokens.nightText);

  TextStyle _body(double size, {FontWeight weight = FontWeight.w400}) =>
      DesignTokens.body(
        size,
        weight: weight,
      ).copyWith(color: DesignTokens.nightText);

  TextStyle _label(double size) => _body(
    size,
    weight: FontWeight.w800,
  ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.3);
}
