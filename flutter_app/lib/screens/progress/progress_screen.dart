import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/content_service.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/progress_service.dart';
import '../../widgets/adaptive/adaptive.dart';

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  RoadmapMonth? _currentMonth;

  @override
  void initState() {
    super.initState();
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    final progress = ref.read(progressServiceProvider);
    final month = await progress.currentMonth();
    if (mounted) {
      setState(() => _currentMonth = month);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(progressServiceProvider);
    final habits = progress.todaysHabits();
    final skills = progress.skillProgress();
    final store = ref.read(learningStoreProvider);
    final monthPrefix = store.dayString(DateTime.now()).substring(0, 7);
    final activeDays = store
        .activeDays()
        .where((d) => d.startsWith(monthPrefix))
        .length;
    final recalledIds = store
        .entriesRecalledSince(DateTime.now().subtract(const Duration(days: 7)))
        .toSet();
    final recalledWords = ContentService.shared.vocabPhases
        .expand((phase) => phase.themes.expand((theme) => theme.entries))
        .where((entry) => recalledIds.contains(entry.id))
        .take(6)
        .toList();

    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: PSContentColumn(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.screenMargin,
              DesignTokens.space6,
              DesignTokens.screenMargin,
              40,
            ),
            children: [
              Text('Progress', style: DesignTokens.display(30)),
              const SizedBox(height: DesignTokens.space2),
              Text(
                'See the practice behind your growing French.',
                style: DesignTokens.body(
                  16,
                ).copyWith(color: DesignTokens.slateDim, height: 1.4),
              ),
              const SizedBox(height: 28),

              // --- Evidence, not streaks: what the learner can actually do ---
              _buildEvidenceSummary(
                activeDays,
                recalledIds.length,
                recalledWords,
              ),
              const SizedBox(height: 32),

              // --- Today's habits ---
              if (habits.isNotEmpty) ...[
                _sectionHeading(
                  'Today',
                  'Small actions that keep your learning moving.',
                ),
                const SizedBox(height: DesignTokens.space4),
                _buildHabits(habits),
                const SizedBox(height: 32),
              ],

              // --- Skill progress ---
              _sectionHeading(
                'Skills',
                'Measured from the work you have completed.',
              ),
              const SizedBox(height: DesignTokens.space5),
              ...skills.map(_buildSkill),

              // --- Roadmap month ---
              if (_currentMonth != null) ...[
                const SizedBox(height: 28),
                _sectionHeading(
                  'Current focus',
                  'Where this month is taking you.',
                ),
                const SizedBox(height: DesignTokens.space4),
                _buildRoadmap(_currentMonth!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: DesignTokens.display(20)),
        const SizedBox(height: DesignTokens.space1),
        Text(
          description,
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.slateDim, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildEvidenceSummary(
    int activeDays,
    int recalledCount,
    List<VocabEntry> sampleWords,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignTokens.space5),
      decoration: BoxDecoration(
        color: DesignTokens.infoSoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: DesignTokens.surface,
                  borderRadius: BorderRadius.circular(
                    DesignTokens.radiusMedium,
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  color: DesignTokens.info,
                  size: 22,
                ),
              ),
              const SizedBox(width: DesignTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your week in practice',
                      style: DesignTokens.display(18),
                    ),
                    const SizedBox(height: DesignTokens.space1),
                    Text(
                      '$activeDays study day${activeDays == 1 ? '' : 's'} this month',
                      style: DesignTokens.body(
                        13,
                      ).copyWith(color: DesignTokens.slateDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.space5),
          Text(
            recalledCount > 0
                ? 'You recalled $recalledCount word${recalledCount == 1 ? '' : 's'} from memory without help.'
                : 'Recall a word without help and your first progress update will appear here.',
            style: DesignTokens.body(
              16,
              weight: FontWeight.w600,
            ).copyWith(height: 1.4),
          ),
          if (sampleWords.isNotEmpty) ...[
            const SizedBox(height: DesignTokens.space4),
            Wrap(
              spacing: DesignTokens.space2,
              runSpacing: DesignTokens.space2,
              children: sampleWords
                  .map(
                    (word) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.space3,
                        vertical: DesignTokens.space2,
                      ),
                      decoration: BoxDecoration(
                        color: DesignTokens.surface,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusPill,
                        ),
                      ),
                      child: Text(
                        word.fr,
                        style: DesignTokens.body(13, weight: FontWeight.w600),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHabits(
    List<({DailyHabit habit, bool done, int minutes})> habits,
  ) {
    return Column(
      children: habits.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: DesignTokens.space3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: DesignTokens.minTapTarget,
                height: DesignTokens.minTapTarget,
                child: Icon(
                  item.done
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  size: 25,
                  color: item.done ? DesignTokens.success : DesignTokens.slate,
                ),
              ),
              const SizedBox(width: DesignTokens.space2),
              Expanded(
                child: Text(
                  item.habit.title,
                  style: DesignTokens.body(15, weight: FontWeight.w500)
                      .copyWith(
                        color: item.done
                            ? DesignTokens.slateDim
                            : DesignTokens.text,
                        decoration: item.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                ),
              ),
              const SizedBox(width: DesignTokens.space3),
              Text(
                '${item.minutes} min',
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.slateDim),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSkill(SkillProgress skill) {
    final percentage = (skill.fraction * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: DesignTokens.successSoft,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
            ),
            child: Icon(
              _iconForSkill(skill.name),
              size: 21,
              color: DesignTokens.success,
            ),
          ),
          const SizedBox(width: DesignTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        skill.name,
                        style: DesignTokens.body(15, weight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '$percentage%',
                      style: DesignTokens.body(
                        13,
                        weight: FontWeight.w600,
                      ).copyWith(color: DesignTokens.slateDim),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.space2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
                  child: LinearProgressIndicator(
                    value: skill.fraction,
                    minHeight: 7,
                    backgroundColor: DesignTokens.parchmentDim,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      DesignTokens.success,
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.space2),
                Text(
                  skill.detail,
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.slateDim, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoadmap(RoadmapMonth month) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.space5),
      decoration: BoxDecoration(
        color: DesignTokens.successSoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: DesignTokens.surface,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
            ),
            alignment: Alignment.center,
            child: Text(
              '${month.month}',
              style: DesignTokens.display(
                20,
              ).copyWith(color: DesignTokens.success),
            ),
          ),
          const SizedBox(width: DesignTokens.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Month ${month.month}',
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.slateDim),
                ),
                const SizedBox(height: DesignTokens.space1),
                Text(
                  month.title,
                  style: DesignTokens.body(16, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForSkill(String name) {
    switch (name) {
      case 'Vocabulary':
        return CupertinoIcons.square_stack_3d_up;
      case 'Grammar':
        return CupertinoIcons.book;
      case 'Listening':
        return CupertinoIcons.headphones;
      case 'Writing':
        return CupertinoIcons.square_pencil;
      default:
        return CupertinoIcons.book_fill;
    }
  }
}
