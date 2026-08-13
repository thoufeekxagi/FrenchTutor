import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../orchestration/models/competency.dart';
import '../../orchestration/models/content_descriptor.dart';
import '../../orchestration/models/competency_state.dart';
import 'learning_graph_view.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/web/web_layout.dart';

enum _MasteryTier { newSkill, building, ready }

extension on _MasteryTier {
  String get label => switch (this) {
    _MasteryTier.newSkill => 'NEW',
    _MasteryTier.building => 'BUILDING',
    _MasteryTier.ready => 'READY',
  };

  Color foreground(BuildContext context) => switch (this) {
    _MasteryTier.newSkill => Passeport.slateDim,
    _MasteryTier.building => Passeport.sky,
    _MasteryTier.ready => Passeport.sage,
  };

  Color background(BuildContext context) => switch (this) {
    _MasteryTier.newSkill => Passeport.parchmentDim,
    _MasteryTier.building => Passeport.infoSoft,
    _MasteryTier.ready => Passeport.successSoft,
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

    if (MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded) {
      return _webPath(framework, bestStateByCompetency);
    }

    return Scaffold(
      backgroundColor: Passeport.parchment,
      body: SafeArea(
        child: PSContentColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your path', style: DesignTokens.display(30)),
                    const SizedBox(height: DesignTokens.space1),
                    Text(
                      '${_currentBand(profile.level)} · ${profile.goal == 'tef_canada' ? 'TEF Canada' : 'Everyday French'}',
                      style: DesignTokens.body(
                        15,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                    const SizedBox(height: DesignTokens.space4),
                    Container(
                      padding: const EdgeInsets.all(DesignTokens.space4),
                      decoration: BoxDecoration(
                        color: DesignTokens.surface,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusCard,
                        ),
                        border: Border.all(color: DesignTokens.hairline),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_currentBand(profile.level)} Intermediate',
                              style: DesignTokens.body(
                                15,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            'Speaking · Building',
                            style: DesignTokens.label(
                              11,
                            ).copyWith(color: DesignTokens.secondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                  children: [
                    Text('Curriculum path', style: DesignTokens.display(22)),
                    const SizedBox(height: 12),
                    if (framework == null)
                      const _EmptyPath()
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Passeport.infoSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              CupertinoIcons.info_circle_fill,
                              color: DesignTokens.secondary,
                              size: 21,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Complete the next skill in order. Your state moves from New to Building to Ready as evidence accumulates.',
                                style: Passeport.body(13).copyWith(
                                  color: Passeport.inkSoft,
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

  Widget _webPath(
    CompetencyFramework? framework,
    Map<String, CompetencyState> bestStateByCompetency,
  ) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: WebPage(
          header: const WebPageHeader(
            title: 'Your French fingerprint',
            subtitle: 'A live map of the evidence behind your French.',
          ),
          children: [
            WebCard(
              padding: const EdgeInsets.all(DesignTokens.space6),
              child: FingerprintView(
                store: ref.watch(learningStoreProvider),
                content: ref.watch(contentServiceProvider),
              ),
            ),
            const SizedBox(height: DesignTokens.space6),
            const WebSectionHeader(title: 'Curriculum path'),
            WebCard(
              padding: const EdgeInsets.all(DesignTokens.space6),
              child: framework == null
                  ? const _EmptyPath()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(DesignTokens.space4),
                          decoration: BoxDecoration(
                            color: DesignTokens.infoSoft,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusMedium,
                            ),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                CupertinoIcons.sparkles,
                                color: DesignTokens.info,
                                size: 21,
                              ),
                              SizedBox(width: DesignTokens.space3),
                              Expanded(
                                child: Text(
                                  'Every skill moves from New to Building to Ready as you practice. Open a level to see its next skills.',
                                  style: TextStyle(height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: DesignTokens.space5),
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
                                      _tierFor(
                                        bestStateByCompetency[item.id],
                                      ) ==
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
                            const SizedBox(height: DesignTokens.space3),
                            for (final competency
                                in framework.competencies.where(
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
                          const SizedBox(height: DesignTokens.space3),
                        ],
                      ],
                    ),
            ),
          ],
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
            color: Passeport.slateDim,
          ),
          const SizedBox(width: 6),
          Text(
            '$band FOUNDATION',
            style: Passeport.body(
              11,
              weight: FontWeight.w700,
            ).copyWith(color: Passeport.slateDim, letterSpacing: 1),
          ),
          const Spacer(),
          Text(
            '$readyCount/$count ready',
            style: Passeport.body(12).copyWith(color: Passeport.slateDim),
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
          color: Passeport.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: DesignTokens.cardShadow,
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
                          style: Passeport.body(15, weight: FontWeight.w700),
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
                          style: Passeport.body(9.5, weight: FontWeight.w700)
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
                    style: Passeport.body(
                      13,
                    ).copyWith(color: Passeport.slateDim, height: 1.4),
                  ),
                  if (competency.prerequisiteIds.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Builds after ${competency.prerequisiteIds.map((id) => titleById[id] ?? id).join(' · ')}',
                      style: Passeport.body(
                        11.5,
                        weight: FontWeight.w600,
                      ).copyWith(color: Passeport.sky),
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
            const Icon(CupertinoIcons.map, color: Passeport.sky, size: 34),
            const SizedBox(height: 14),
            Text('Your path is being prepared', style: Passeport.display(22)),
            const SizedBox(height: 7),
            Text(
              'The competency map will appear after the curriculum finishes loading.',
              textAlign: TextAlign.center,
              style: Passeport.body(
                14,
              ).copyWith(color: Passeport.slateDim, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
