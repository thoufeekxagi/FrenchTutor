import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_styles.dart';
import '../../orchestration/models/competency.dart';
import '../../orchestration/models/competency_state.dart';
import 'learning_graph_view.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';

enum _MasteryTier { newSkill, building, ready }

extension on _MasteryTier {
  String get label => switch (this) {
    _MasteryTier.newSkill => 'NEW',
    _MasteryTier.building => 'BUILDING',
    _MasteryTier.ready => 'READY',
  };

  Color foreground(BuildContext context) => switch (this) {
    _MasteryTier.newSkill => AppStyles.mutedDim,
    _MasteryTier.building => AppStyles.info,
    _MasteryTier.ready => AppStyles.success,
  };

  Color background(BuildContext context) => switch (this) {
    _MasteryTier.newSkill => AppStyles.canvasDim,
    _MasteryTier.building => AppStyles.infoSoft,
    _MasteryTier.ready => AppStyles.successSoft,
  };
}

_MasteryTier _tierFor(CompetencyState? state) {
  if (state == null || state.needsMoreEvidence) return _MasteryTier.newSkill;
  if (state.masteryEstimate >= 0.75 && state.confidence >= 0.5) {
    return _MasteryTier.ready;
  }
  return _MasteryTier.building;
}

/// Maps a profile's stored level (CEFR 'a1'..'b2', or legacy values like
/// 'zero'/'conversational' — see `Profile.level` doc comment) to the
/// uppercase band strings used in the competency graph content
/// (`competency_graph_v1.json`'s `difficultyBand`), so the map can default
/// to opening the band the learner is actually working in.
String _currentBand(String level) => switch (level.toLowerCase()) {
  'a1' || 'zero' || 'basics' => 'A1',
  'a2' => 'A2',
  'b1' || 'conversational' => 'B1',
  'b2' => 'B2',
  _ => 'A1',
};

class PathScreen extends ConsumerStatefulWidget {
  const PathScreen({super.key});

  @override
  ConsumerState<PathScreen> createState() => _PathScreenState();
}

class _PathScreenState extends ConsumerState<PathScreen> {
  Set<String>? _expandedBands;

  @override
  Widget build(BuildContext context) {
    final framework = ref.watch(competencyStoreProvider).framework();
    final profile = ref.watch(learningStoreProvider).profile();
    final states = ref.watch(competencyStateStoreProvider).all();
    final bestStateByCompetency = <String, CompetencyState>{};
    for (final state in states) {
      final existing = bestStateByCompetency[state.competencyId];
      if (existing == null ||
          state.masteryEstimate > existing.masteryEstimate) {
        bestStateByCompetency[state.competencyId] = state;
      }
    }
    // Only the learner's current band starts open — everything else stays
    // collapsed to a one-line header, so the screen reads as a real "you are
    // here" map instead of the entire syllabus dumped at once.
    _expandedBands ??= {_currentBand(profile.level)};

    return Scaffold(
      backgroundColor: AppStyles.canvas,
      body: SafeArea(
        child: PSContentColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fixed header: the fingerprint canvas stays put as the page
              // scrolls — only its own contents pan/zoom, never the frame.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your French fingerprint',
                      style: AppStyles.display(28),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Shaped by how you practice.',
                      style: AppStyles.body(
                        14.5,
                      ).copyWith(color: AppStyles.mutedDim, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    FingerprintView(
                      store: ref.watch(learningStoreProvider),
                      content: ref.watch(contentServiceProvider),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                  children: [
                    Text('Curriculum path', style: AppStyles.display(22)),
                    const SizedBox(height: 12),
                    if (framework == null)
                      const _EmptyPath()
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppStyles.infoSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              CupertinoIcons.sparkles,
                              color: AppStyles.info,
                              size: 21,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Every skill moves from New to Building to Ready as you practice. Tap a level to expand it.',
                                style: AppStyles.body(13).copyWith(
                                  color: AppStyles.inkSoft,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      for (final band in _bands(framework.competencies)) ...[
                        _BandHeader(
                          band: band,
                          count: framework.competencies
                              .where((item) => item.difficultyBand == band)
                              .length,
                          readyCount: framework.competencies
                              .where((item) => item.difficultyBand == band)
                              .where(
                                (item) =>
                                    _tierFor(bestStateByCompetency[item.id]) ==
                                    _MasteryTier.ready,
                              )
                              .length,
                          expanded: _expandedBands!.contains(band),
                          onToggle: () => setState(() {
                            final expanded = _expandedBands!;
                            if (!expanded.remove(band)) expanded.add(band);
                          }),
                        ),
                        if (_expandedBands!.contains(band)) ...[
                          const SizedBox(height: 10),
                          for (final competency in framework.competencies.where(
                            (item) => item.difficultyBand == band,
                          ))
                            _CompetencyNode(
                              competency: competency,
                              titleById: {
                                for (final item in framework.competencies)
                                  item.id: item.title,
                              },
                              tier: _tierFor(
                                bestStateByCompetency[competency.id],
                              ),
                            ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _bands(List<Competency> competencies) {
    final bands = <String>[];
    for (final item in competencies) {
      if (!bands.contains(item.difficultyBand)) bands.add(item.difficultyBand);
    }
    return bands;
  }
}

class _BandHeader extends StatelessWidget {
  const _BandHeader({
    required this.band,
    required this.count,
    required this.readyCount,
    required this.expanded,
    required this.onToggle,
  });

  final String band;
  final int count;
  final int readyCount;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Row(
        children: [
          Icon(
            expanded
                ? CupertinoIcons.chevron_down
                : CupertinoIcons.chevron_right,
            size: 14,
            color: AppStyles.mutedDim,
          ),
          const SizedBox(width: 6),
          Text(
            '$band FOUNDATION',
            style: AppStyles.body(
              11,
              weight: FontWeight.w700,
            ).copyWith(color: AppStyles.mutedDim, letterSpacing: 1),
          ),
          const Spacer(),
          Text(
            '$readyCount/$count ready',
            style: AppStyles.body(12).copyWith(color: AppStyles.mutedDim),
          ),
        ],
      ),
    );
  }
}

class _CompetencyNode extends StatelessWidget {
  const _CompetencyNode({
    required this.competency,
    required this.titleById,
    required this.tier,
  });

  final Competency competency;
  final Map<String, String> titleById;
  final _MasteryTier tier;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppStyles.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: DesignTokens.surfaceShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tier.background(context),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                _iconFor(competency.kind),
                color: tier.foreground(context),
                size: 20,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          competency.title,
                          style: AppStyles.body(15, weight: FontWeight.w700),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: tier.background(context),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          tier.label,
                          style: AppStyles.body(9.5, weight: FontWeight.w700)
                              .copyWith(
                                color: tier.foreground(context),
                                letterSpacing: 0.7,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    competency.description,
                    style: AppStyles.body(
                      13,
                    ).copyWith(color: AppStyles.mutedDim, height: 1.4),
                  ),
                  if (competency.prerequisiteIds.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Builds after ${competency.prerequisiteIds.map((id) => titleById[id] ?? id).join(' · ')}',
                      style: AppStyles.body(
                        11.5,
                        weight: FontWeight.w600,
                      ).copyWith(color: AppStyles.info),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(CompetencyKind kind) => switch (kind) {
    CompetencyKind.lexical => CupertinoIcons.textformat_abc,
    CompetencyKind.grammar => CupertinoIcons.textformat_alt,
    CompetencyKind.phonology => CupertinoIcons.waveform,
    CompetencyKind.function => CupertinoIcons.chat_bubble_2_fill,
    CompetencyKind.discourse => CupertinoIcons.text_bubble_fill,
    CompetencyKind.strategy => CupertinoIcons.scope,
  };
}

class _EmptyPath extends StatelessWidget {
  const _EmptyPath();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.map, color: AppStyles.info, size: 34),
            const SizedBox(height: 14),
            Text('Your path is being prepared', style: AppStyles.display(22)),
            const SizedBox(height: 7),
            Text(
              'The competency map will appear after the curriculum finishes loading.',
              textAlign: TextAlign.center,
              style: AppStyles.body(
                14,
              ).copyWith(color: AppStyles.mutedDim, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
