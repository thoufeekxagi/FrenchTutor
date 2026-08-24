import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/speaking_course.dart';
import '../../providers/database_provider.dart';
import 'speaking_lesson_flow_screen.dart';

/// Speak-style free-talk catalog. It is deliberately a catalog, not another
/// speaking home: the learner chooses a topic, follows its prompts, then
/// enters the shared free-talk conversation.
class SpeakFreeTalkScreen extends ConsumerStatefulWidget {
  const SpeakFreeTalkScreen({super.key});

  @override
  ConsumerState<SpeakFreeTalkScreen> createState() =>
      _SpeakFreeTalkScreenState();
}

class _SpeakFreeTalkScreenState extends ConsumerState<SpeakFreeTalkScreen> {
  String _filter = 'Hot';

  String get _level {
    final raw = ref.watch(learningStoreProvider).profile().level.toUpperCase();
    return raw == 'A1' || raw == 'ZERO' || raw == 'BASICS' ? 'A1' : 'A2';
  }

  Future<void> _openTopic(
    BuildContext context,
    SpeakingCourseLesson lesson,
  ) async {
    await AppRouter.push(
      context,
      (_) => SpeakingLessonFlowScreen(
        title: lesson.title,
        topic: lesson.subtitle,
        level: lesson.level,
        contentKey: lesson.id,
        steps: [
          for (final line in lesson.lines)
            SpeakingPhraseStep(
              french: line.french,
              english: line.english,
              partnerFrench: line.partnerFrench,
              partnerEnglish: line.partnerEnglish,
              tip: line.tip,
              openResponse: true,
            ),
        ],
      ),
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
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: DesignTokens.nightText,
                  ),
                ),
                const SizedBox(width: 4),
                Text('Free talk', style: _display(25)),
                const Spacer(),
                _roundIcon(Icons.history_rounded, 'History'),
                const SizedBox(width: 8),
                _roundIcon(Icons.favorite_border_rounded, 'Saved'),
              ],
            ),
            const SizedBox(height: 22),
            Text('Talk about your world', style: _display(29)),
            const SizedBox(height: 7),
            Text(
              'Choose a topic, follow the prompts, and speak at your profile level.',
              style: _body(
                14,
              ).copyWith(color: DesignTokens.nightMuted, height: 1.35),
            ),
            const SizedBox(height: 22),
            _filterRow(),
            const SizedBox(height: 16),
            Text('FREE TALK TOPICS', style: _label(12)),
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
    final topics = SpeakingCourseCatalog.freeTalkForLevel(_level);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: topics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: 122,
      ),
      itemBuilder: (context, index) {
        final topic = topics[index];
        return GestureDetector(
          onTap: () => _openTopic(context, topic),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 8, 9),
            decoration: BoxDecoration(
              color: DesignTokens.nightSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DesignTokens.nightHairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: DesignTokens.nightSurfaceRaised,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    topic.icon,
                    color: DesignTokens.nightAccent,
                    size: 17,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _body(12, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${topic.lines.length} prompts',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _body(10).copyWith(color: DesignTokens.nightMuted),
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
