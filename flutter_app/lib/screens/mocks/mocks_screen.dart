import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../labs/connectors_lab_screen.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/writing_lab_screen.dart';

/// Ported from MocksView.swift. Full timed mock exam simulation is a future feature
/// ("coming soon") — for now each skill links straight to its lab so students can build
/// foundations there first.
class MocksScreen extends StatelessWidget {
  const MocksScreen({super.key});

  static const _sections = [
    (
      name: 'Listening',
      icon: CupertinoIcons.headphones,
      time: '40 min',
      labId: 'listening',
    ),
    (
      name: 'Reading',
      icon: CupertinoIcons.book,
      time: '60 min',
      labId: 'connectors',
    ),
    (
      name: 'Writing',
      icon: CupertinoIcons.pencil,
      time: '60 min',
      labId: 'writing',
    ),
    (
      name: 'Speaking',
      icon: CupertinoIcons.mic_fill,
      time: '15 min',
      labId: 'marie',
    ),
  ];

  Widget? _destination(String labId) {
    switch (labId) {
      case 'listening':
        return const ListeningLabScreen();
      case 'writing':
        return const WritingLabScreen();
      case 'connectors':
        return const ConnectorsLabScreen();
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text('Mock exam', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: PSContentColumn(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.screenMargin,
              DesignTokens.space4,
              DesignTokens.screenMargin,
              32,
            ),
            children: [
              Text('Build exam readiness', style: DesignTokens.display(28)),
              const SizedBox(height: DesignTokens.space2),
              Text(
                'Practice one skill at a time now. The complete timed TEF Canada simulation is still in development.',
                style: DesignTokens.body(
                  15,
                ).copyWith(color: DesignTokens.slateDim, height: 1.45),
              ),
              const SizedBox(height: DesignTokens.space6),
              _recommendedPractice(context),
              const SizedBox(height: 32),
              Text('Choose another skill', style: DesignTokens.display(20)),
              const SizedBox(height: DesignTokens.space1),
              Text(
                'Each lab develops a skill used in the exam.',
                style: DesignTokens.body(
                  14,
                ).copyWith(color: DesignTokens.slateDim),
              ),
              const SizedBox(height: DesignTokens.space4),
              ..._sections
                  .skip(1)
                  .map((section) => _skillRow(context, section)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recommendedPractice(BuildContext context) {
    final section = _sections.first;
    final destination = _destination(section.labId)!;

    return Container(
      padding: const EdgeInsets.all(DesignTokens.space5),
      decoration: BoxDecoration(
        color: DesignTokens.infoSoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: DesignTokens.surface,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
            ),
            child: Icon(section.icon, color: DesignTokens.info, size: 23),
          ),
          const SizedBox(height: DesignTokens.space4),
          Text('Start with listening', style: DesignTokens.display(21)),
          const SizedBox(height: DesignTokens.space2),
          Text(
            'Practice understanding spoken French before taking on the full timed section.',
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.inkSoft, height: 1.45),
          ),
          const SizedBox(height: DesignTokens.space3),
          Row(
            children: [
              const Icon(
                CupertinoIcons.clock,
                size: 17,
                color: DesignTokens.slateDim,
              ),
              const SizedBox(width: DesignTokens.space2),
              Text(
                section.time,
                style: DesignTokens.body(
                  13,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.slateDim),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.space5),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: DesignTokens.primary,
                foregroundColor: DesignTokens.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    DesignTokens.radiusMedium,
                  ),
                ),
              ),
              onPressed: () => Navigator.of(
                context,
              ).push(AppRouter.route(builder: (_) => destination)),
              child: Text(
                'Practice listening',
                style: DesignTokens.body(
                  15,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.surface),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skillRow(
    BuildContext context,
    ({String name, IconData icon, String time, String labId}) section,
  ) {
    final destination = _destination(section.labId);
    final available = destination != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space3),
      child: Semantics(
        button: available,
        enabled: available,
        label: available
            ? 'Practice ${section.name}, ${section.time}'
            : '${section.name} practice coming soon',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: !available
              ? null
              : () => Navigator.of(
                  context,
                ).push(AppRouter.route(builder: (_) => destination)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: available
                        ? DesignTokens.successSoft
                        : DesignTokens.parchmentDim,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusMedium,
                    ),
                  ),
                  child: Icon(
                    section.icon,
                    size: 20,
                    color: available
                        ? DesignTokens.success
                        : DesignTokens.slate,
                  ),
                ),
                const SizedBox(width: DesignTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        section.name,
                        style: DesignTokens.body(15, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: DesignTokens.space1),
                      Text(
                        available ? 'Open practice lab' : 'Coming soon',
                        style: DesignTokens.body(
                          13,
                        ).copyWith(color: DesignTokens.slateDim),
                      ),
                    ],
                  ),
                ),
                Text(
                  section.time,
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.slateDim),
                ),
                const SizedBox(width: DesignTokens.space2),
                Icon(
                  available
                      ? CupertinoIcons.chevron_right
                      : CupertinoIcons.lock,
                  size: 18,
                  color: DesignTokens.slate,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
