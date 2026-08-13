import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/session.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/session_row.dart';
import '../../widgets/web/web_constrained_view.dart';
import 'history_screen.dart';

/// Every practice session the learner has ever done — missions and
/// standalone lab practice alike, newest first, filterable by stage —
/// replacing the dashboard's "Recent practice" card (capped at 2, no way to
/// see the rest). Tapping a row opens the same [HistoryScreen] transcript
/// view the dashboard already uses.
class AllHistoryScreen extends ConsumerStatefulWidget {
  const AllHistoryScreen({super.key});

  @override
  ConsumerState<AllHistoryScreen> createState() => _AllHistoryScreenState();
}

class _AllHistoryScreenState extends ConsumerState<AllHistoryScreen> {
  List<Session> _sessions = [];
  bool _loading = true;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _loading = true);
    final sessions = ref.read(storageServiceProvider).getAllSessions();
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  List<String> get _availableStages {
    final present = _sessions
        .map((s) => SessionRow.stageLabel(s.stage))
        .whereType<String>()
        .toSet();
    // Keep a stable, familiar order; only show stages that actually appear.
    const known = [
      'Vocab',
      'Grammar',
      'Reading',
      'Roleplay',
      'Writing',
      'Speaking',
      'Story',
    ];
    return known.where(present.contains).toList();
  }

  List<Session> get _filteredSessions {
    if (_filter == 'All') return _sessions;
    return _sessions
        .where((s) => SessionRow.stageLabel(s.stage) == _filter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final stages = _availableStages;
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('All practice', style: DesignTokens.display(20)),
      ),
      body: SafeArea(
        top: false,
        child: WebConstrainedView(
          maxWidth: 1080,
          child: PSContentColumn(
            child: _loading
                ? const Center(child: PSProgressIndicator())
                : _sessions.isEmpty
                ? _emptyState()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (stages.isNotEmpty) _filterBar(stages),
                      Expanded(
                        child: RefreshIndicator(
                          color: DesignTokens.primary,
                          onRefresh: () async => _reload(),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                              DesignTokens.screenMargin,
                              DesignTokens.space4,
                              DesignTokens.screenMargin,
                              32,
                            ),
                            itemCount: _filteredSessions.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: DesignTokens.parchmentDim,
                            ),
                            itemBuilder: (context, index) {
                              final session = _filteredSessions[index];
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => AppRouter.push(
                                  context,
                                  (_) => HistoryScreen(session: session),
                                ),
                                child: SessionRow(session: session),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _filterBar(List<String> stages) {
    final chips = ['All', ...stages];
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.screenMargin,
          vertical: DesignTokens.space2,
        ),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: DesignTokens.space2),
        itemBuilder: (context, index) {
          final label = chips[index];
          final selected = _filter == label;
          return Semantics(
            button: true,
            selected: selected,
            child: InkWell(
              borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
              onTap: () => setState(() => _filter = label),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: DesignTokens.minTapTarget,
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.space4,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? DesignTokens.ink
                      : DesignTokens.parchmentDim,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
                ),
                child: Text(
                  label,
                  style: DesignTokens.body(13, weight: FontWeight.w600)
                      .copyWith(
                        color: selected
                            ? DesignTokens.surface
                            : DesignTokens.inkSoft,
                      ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.space5),
        child: Text(
          'Nothing practiced yet. It\'ll show up here once you do.',
          textAlign: TextAlign.center,
          style: DesignTokens.body(14).copyWith(color: DesignTokens.slateDim),
        ),
      ),
    );
  }
}
