import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../data/content_service.dart';
import '../../providers/database_provider.dart';
import '../../services/progress_service.dart';
import '../../models/content_models.dart';

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
    final activeDays = store.activeDays().where((d) => d.startsWith(monthPrefix)).length;
    final recalledIds = store.entriesRecalledSince(DateTime.now().subtract(const Duration(days: 7))).toSet();
    final recalledWords = ContentService.shared.vocabPhases
        .expand((ph) => ph.themes.expand((t) => t.entries))
        .where((e) => recalledIds.contains(e.id))
        .take(6)
        .toList();

    return Scaffold(
      backgroundColor: Passeport.parchment,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 24),
            Text('Progress', style: Passeport.display(24)),
            const SizedBox(height: 4),
            Text(
              'Your learning journey',
              style: Passeport.body(14).copyWith(color: Passeport.slateDim),
            ),
            const SizedBox(height: 28),

            // --- Evidence, not streaks: what the learner can actually do ---
            _buildEvidenceCard(activeDays, recalledIds.length, recalledWords),
            const SizedBox(height: 24),

            // --- Today's habits ---
            if (habits.isNotEmpty) ...[
              Text(
                "TODAY'S HABITS",
                style: Passeport.mono(10, weight: FontWeight.w600)
                    .copyWith(color: Passeport.slateDim, letterSpacing: 1.2),
              ),
              const SizedBox(height: 10),
              _buildHabitsCard(habits),
              const SizedBox(height: 24),
            ],

            // --- Skill progress ---
            Text(
              'SKILL PROGRESS',
              style: Passeport.mono(10, weight: FontWeight.w600)
                  .copyWith(color: Passeport.slateDim, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),
            ...skills.map((skill) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildSkillRow(skill),
                )),
            const SizedBox(height: 12),

            // --- Roadmap month ---
            if (_currentMonth != null) ...[
              Text(
                'ROADMAP',
                style: Passeport.mono(10, weight: FontWeight.w600)
                    .copyWith(color: Passeport.slateDim, letterSpacing: 1.2),
              ),
              const SizedBox(height: 10),
              _buildRoadmapCard(_currentMonth!),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildEvidenceCard(int activeDays, int recalledCount, List<VocabEntry> sampleWords) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Passeport.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Passeport.hairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: Passeport.display(16, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            recalledCount > 0
                ? 'You recalled $recalledCount word${recalledCount == 1 ? '' : 's'} from memory, unaided.'
                : 'Your first recalled words will show up here.',
            style: Passeport.body(13).copyWith(color: Passeport.slateDim),
          ),
          if (sampleWords.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: sampleWords
                  .map((w) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Passeport.brass.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(w.fr,
                            style: Passeport.mono(11, weight: FontWeight.w500)
                                .copyWith(color: Passeport.inkSoft)),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '$activeDays study day${activeDays == 1 ? '' : 's'} this month',
            style: Passeport.mono(11).copyWith(color: Passeport.slateDim),
          ),
        ],
      ),
    );
  }

  Widget _buildHabitsCard(
      List<({DailyHabit habit, bool done, int minutes})> habits) {
    return Container(
      decoration: BoxDecoration(
        color: Passeport.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Passeport.hairline, width: 1),
      ),
      child: Column(
        children: habits.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isLast = index == habits.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(bottom: BorderSide(color: Passeport.hairline, width: 1)),
            ),
            child: Row(
              children: [
                Icon(
                  item.done ? Icons.check_circle : Icons.circle_outlined,
                  size: 22,
                  color: item.done ? Passeport.maroon : Passeport.slate,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.habit.title,
                    style: Passeport.body(14).copyWith(
                      color: item.done ? Passeport.slateDim : Passeport.text,
                      decoration: item.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                Text(
                  '${item.minutes} min',
                  style: Passeport.mono(12).copyWith(color: Passeport.slateDim),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSkillRow(SkillProgress skill) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Passeport.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Passeport.hairline, width: 1),
      ),
      child: Row(
        children: [
          Icon(
            _iconForSkill(skill.name),
            size: 24,
            color: Passeport.brass,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(skill.name, style: Passeport.body(14, weight: FontWeight.w600)),
                    Text(
                      '${(skill.fraction * 100).round()}%',
                      style: Passeport.mono(12).copyWith(color: Passeport.slateDim),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: skill.fraction,
                    minHeight: 6,
                    backgroundColor: Passeport.parchmentDim,
                    valueColor: const AlwaysStoppedAnimation<Color>(Passeport.maroon),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  skill.detail,
                  style: Passeport.body(11).copyWith(color: Passeport.slateDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoadmapCard(RoadmapMonth month) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Passeport.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Passeport.hairline, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Passeport.brass.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '${month.month}',
                style: Passeport.display(18, weight: FontWeight.w700)
                    .copyWith(color: Passeport.brass),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Month ${month.month}',
                  style: Passeport.body(14, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  month.title,
                  style: Passeport.body(12).copyWith(color: Passeport.slateDim),
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
        return Icons.style;
      case 'Grammar':
        return Icons.menu_book;
      case 'Listening':
        return Icons.headphones;
      case 'Writing':
        return Icons.edit_note;
      default:
        return Icons.school;
    }
  }
}
