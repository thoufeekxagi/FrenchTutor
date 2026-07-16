import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../orchestration/dev/developer_path_preview.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_card.dart';

class OrchestrationLabScreen extends ConsumerStatefulWidget {
  const OrchestrationLabScreen({super.key});

  @override
  ConsumerState<OrchestrationLabScreen> createState() =>
      _OrchestrationLabScreenState();
}

class _OrchestrationLabScreenState
    extends ConsumerState<OrchestrationLabScreen> {
  DeveloperPersonaScenario _persona = developerPersonaScenarios[2];

  Future<void> _choosePersona() async {
    final selected = await showPSActionSheet<DeveloperPersonaScenario>(
      context,
      title: 'Test persona',
      actions: [
        for (final persona in developerPersonaScenarios)
          (
            label: '${persona.name} — ${persona.summary}',
            value: persona,
            destructive: false,
          ),
      ],
    );
    if (selected != null && mounted) setState(() => _persona = selected);
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final framework = ref.watch(competencyStoreProvider).framework();
    if (framework == null) {
      return Scaffold(
        backgroundColor: Passeport.parchmentDim,
        appBar: AppBar(
          title: Text('Orchestration Lab', style: Passeport.display(20)),
        ),
        body: Center(
          child: Text(
            'No persisted competency framework.',
            style: Passeport.body(15).copyWith(color: Passeport.slateDim),
          ),
        ),
      );
    }
    final preview = const DeveloperPathPreviewBuilder().build(
      framework: framework,
      persona: _persona,
    );

    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        backgroundColor: Passeport.parchmentDim,
        title: Text('Orchestration Lab', style: Passeport.display(20)),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: PSContentColumn(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Runtime', color: Passeport.slateDim),
                  const SizedBox(height: 8),
                  Text(
                    framework.curriculumVersion,
                    style: Passeport.display(18, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${framework.competencies.length} competencies · '
                    '${framework.mappings.length} mappings · framework ${framework.frameworkVersion}',
                    style: Passeport.mono(
                      11,
                    ).copyWith(color: Passeport.slateDim),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Scenario', color: Passeport.slateDim),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _choosePersona,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _persona.name,
                                  style: Passeport.body(
                                    15,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _persona.summary,
                                  style: Passeport.body(
                                    12,
                                  ).copyWith(color: Passeport.slateDim),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            CupertinoIcons.chevron_down,
                            size: 16,
                            color: Passeport.slateDim,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PSSegmented<int>(
                    segments: const [
                      (value: 20, label: '20m'),
                      (value: 45, label: '45m'),
                      (value: 90, label: '90m'),
                      (value: 120, label: '2h'),
                    ],
                    selected:
                        [20, 45, 90, 120].contains(_persona.availableMinutes)
                        ? _persona.availableMinutes
                        : 120,
                    onChanged: (minutes) => setState(
                      () => _persona = _persona.copyWith(
                        availableMinutes: minutes,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ToggleRow(
                    label: 'Can speak aloud',
                    value: _persona.canSpeakAloud,
                    onChanged: (value) => setState(
                      () => _persona = _persona.copyWith(canSpeakAloud: value),
                    ),
                  ),
                  _ToggleRow(
                    label: 'Network available',
                    value: _persona.networkAvailable,
                    onChanged: (value) => setState(
                      () =>
                          _persona = _persona.copyWith(networkAvailable: value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                KickerText('Path preview', color: Passeport.slateDim),
                const Spacer(),
                Text(
                  '${preview.totalMinutes} min',
                  style: Passeport.mono(11).copyWith(color: Passeport.maroon),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (index, task) in preview.tasks.indexed) ...[
              PasseportCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Passeport.brass.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: Passeport.mono(11, weight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.competencyTitle,
                            style: Passeport.body(14, weight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            task.contentItemId,
                            style: Passeport.mono(
                              11,
                            ).copyWith(color: Passeport.slateDim),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${task.modality.wireName} · ${task.role.name} · ${task.estimatedMinutes} min',
                            style: Passeport.body(
                              11,
                            ).copyWith(color: Passeport.brass),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            task.reason,
                            style: Passeport.body(
                              12,
                            ).copyWith(color: Passeport.slateDim),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
            PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Boundaries', color: Passeport.slateDim),
                  const SizedBox(height: 8),
                  for (final note in preview.notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        note,
                        style: Passeport.body(
                          12,
                        ).copyWith(color: Passeport.slateDim),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      children: [
        Text(label, style: Passeport.body(14)),
        const Spacer(),
        PSSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );
}
