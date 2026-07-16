import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../orchestration/models/competency.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';

class PathScreen extends ConsumerWidget {
  const PathScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final framework = ref.watch(competencyStoreProvider).framework();
    return Scaffold(
      backgroundColor: Passeport.parchment,
      body: SafeArea(
        child: PSContentColumn(
          child: framework == null
              ? const _EmptyPath()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                  children: [
                    Text('Your path', style: Passeport.display(30)),
                    const SizedBox(height: 5),
                    Text(
                      'The abilities your daily plan is building toward.',
                      style: Passeport.body(
                        14.5,
                      ).copyWith(color: Passeport.slateDim, height: 1.4),
                    ),
                    const SizedBox(height: 22),
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
                            CupertinoIcons.sparkles,
                            color: Passeport.sky,
                            size: 21,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Practice evidence will move competencies from New to Building to Ready. Until then, this map shows the real curriculum sequence without inventing scores.',
                              style: Passeport.body(
                                13,
                              ).copyWith(color: Passeport.inkSoft, height: 1.4),
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
                      ),
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
                          isFoundation: competency.prerequisiteIds.isEmpty,
                        ),
                      const SizedBox(height: 16),
                    ],
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
  const _BandHeader({required this.band, required this.count});

  final String band;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$band FOUNDATION',
          style: Passeport.body(
            11,
            weight: FontWeight.w700,
          ).copyWith(color: Passeport.slateDim, letterSpacing: 1),
        ),
        const Spacer(),
        Text(
          '$count abilities',
          style: Passeport.body(12).copyWith(color: Passeport.slateDim),
        ),
      ],
    );
  }
}

class _CompetencyNode extends StatelessWidget {
  const _CompetencyNode({
    required this.competency,
    required this.titleById,
    required this.isFoundation,
  });

  final Competency competency;
  final Map<String, String> titleById;
  final bool isFoundation;

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
                color: isFoundation
                    ? Passeport.successSoft
                    : Passeport.infoSoft,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                _iconFor(competency.kind),
                color: isFoundation ? Passeport.sage : Passeport.sky,
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
                          color: isFoundation
                              ? Passeport.successSoft
                              : Passeport.parchmentDim,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          isFoundation
                              ? 'START HERE'
                              : competency.kind.name.toUpperCase(),
                          style: Passeport.body(9.5, weight: FontWeight.w700)
                              .copyWith(
                                color: isFoundation
                                    ? Passeport.sage
                                    : Passeport.slateDim,
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
