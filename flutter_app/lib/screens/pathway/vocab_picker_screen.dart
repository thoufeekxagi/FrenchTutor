import '../../widgets/adaptive/adaptive.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../design/app_router.dart';
import '../../flow/stage_outcome.dart';
import '../../data/content_service.dart';
import '../../models/content_models.dart';
import '../../models/daily_session.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/srs_service.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import 'agent_led_vocab_screen.dart';

enum _PickerMode { auto, category }

/// Sits in front of the vocab stage so today's word list isn't always a black-box auto-pick.
/// Two modes: fully automatic (today's mixed SRS queue, unchanged default), and a
/// category-first manual picker — choose a section, then a sheet shows just that section's
/// words to select from. Already-known words (SM-2 reps >= 3, interval >= 21 days) show a
/// green check and are excluded from Auto mode by default, though they can still be manually
/// re-picked. Ported from VocabPickerView.swift.
class VocabPickerScreen extends ConsumerStatefulWidget {
  const VocabPickerScreen({super.key});

  @override
  ConsumerState<VocabPickerScreen> createState() => _VocabPickerScreenState();
}

class _VocabPickerScreenState extends ConsumerState<VocabPickerScreen> {
  _PickerMode _mode = _PickerMode.auto;
  final Set<String> _manualSelection = {};
  bool _isPlanning = false;

  Set<String> get _knownIds {
    final store = ref.read(learningStoreProvider);
    return store
        .allSRSStates()
        .entries
        .where((e) => e.value.reps >= 3 && e.value.intervalDays >= 21)
        .map((e) => e.key)
        .toSet();
  }

  List<VocabPhase> get _allPhases => ContentService.shared.vocabPhases;

  Future<List<VocabEntry>> get _autoQueue =>
      SRSService(store: ref.read(learningStoreProvider)).dailyMixedQueue();

  /// Today's interrupted session, if any — planned words minus practiced ones.
  /// Non-null makes the "continue where you left off" card appear up top; the
  /// regular picker below stays available for "brand new words instead".
  ({List<VocabEntry> remaining, List<VocabEntry> planned})? get _resumable {
    final record = ref
        .read(learningStoreProvider)
        .dailySession()
        .stages[PathwayStage.vocab]!;
    if (record.status != StageStatus.paused) return null;
    final json = record.resultJson;
    final plannedIds =
        (json?['plannedWordIds'] as List?)?.cast<String>() ?? const <String>[];
    if (plannedIds.isEmpty) return null;
    final practiced = ((json?['wordIds'] as List?)?.cast<String>() ?? const [])
        .toSet();
    final remainingIds = plannedIds
        .where((id) => !practiced.contains(id))
        .toList();
    if (remainingIds.isEmpty) return null;
    final byId = {
      for (final e in _allPhases.expand(
        (p) => p.themes.expand((t) => t.entries),
      ))
        e.id: e,
    };
    List<VocabEntry> entries(List<String> ids) =>
        ids.map((id) => byId[id]).whereType<VocabEntry>().toList();
    final remaining = entries(remainingIds);
    if (remaining.isEmpty) return null;
    return (remaining: remaining, planned: entries(plannedIds));
  }

  Widget _resumeCard(
    ({List<VocabEntry> remaining, List<VocabEntry> planned}) resumable,
  ) {
    final done = resumable.planned.length - resumable.remaining.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.screenMargin,
        DesignTokens.space3,
        DesignTokens.screenMargin,
        0,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DesignTokens.primarySoft,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KickerText('In progress', color: DesignTokens.primaryDeep),
            const SizedBox(height: 4),
            Text(
              '$done of ${resumable.planned.length} words practiced earlier '
              'today — pick up where you left off.',
              style: DesignTokens.body(13.5),
            ),
            const SizedBox(height: 12),
            PasseportPrimaryButton(
              label: 'Continue — ${resumable.remaining.length} words left',
              onPressed: () => _beginSession(resumable.remaining),
            ),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: () => _beginSession(resumable.planned),
                child: Text(
                  'Restart the full set',
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w500,
                  ).copyWith(color: DesignTokens.primaryDeep),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text("Today's Words", style: DesignTokens.display(18)),
        backgroundColor: DesignTokens.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            CupertinoIcons.xmark,
            size: 20,
            color: DesignTokens.slateDim,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignTokens.contentMaxWidth,
              ),
              child: Column(
                children: [
                  if (_resumable case final resumable?) _resumeCard(resumable),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DesignTokens.screenMargin,
                      DesignTokens.space3,
                      DesignTokens.screenMargin,
                      0,
                    ),
                    child: PSSegmented<_PickerMode>(
                      segments: const [
                        (value: _PickerMode.auto, label: 'Recommended'),
                        (value: _PickerMode.category, label: 'By category'),
                      ],
                      selected: _mode,
                      onChanged: (mode) => setState(() => _mode = mode),
                    ),
                  ),
                  Expanded(
                    child: _mode == _PickerMode.auto
                        ? _autoBody()
                        : _categoryBody(),
                  ),
                ],
              ),
            ),
          ),
          if (_isPlanning)
            Container(
              color: DesignTokens.ink.withValues(alpha: 0.16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: DesignTokens.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PSProgressIndicator(),
                      const SizedBox(height: 10),
                      Text(
                        "Personalizing today's session…",
                        style: DesignTokens.mono(
                          11,
                        ).copyWith(color: DesignTokens.slateDim),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // MARK: - Auto mode

  Widget _autoBody() {
    return FutureBuilder<List<VocabEntry>>(
      future: _autoQueue,
      builder: (context, snapshot) {
        final queue = snapshot.data ?? [];
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.screenMargin,
            DesignTokens.space6,
            DesignTokens.screenMargin,
            DesignTokens.space5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: DesignTokens.infoSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.rectangle_stack_fill,
                  color: DesignTokens.info,
                  size: 23,
                ),
              ),
              const SizedBox(height: DesignTokens.space5),
              Text(
                isLoading
                    ? 'Building today’s word queue'
                    : '${queue.length} words ready',
                style: DesignTokens.display(26),
              ),
              const SizedBox(height: DesignTokens.space3),
              Text(
                'Due reviews come first, followed by new words in curriculum order. Marie can prioritize this real queue before practice starts.',
                style: DesignTokens.body(
                  15,
                ).copyWith(color: DesignTokens.slateDim, height: 1.45),
              ),
              if (isLoading) ...[
                const SizedBox(height: DesignTokens.space5),
                const PSProgressIndicator(),
              ] else if (queue.isEmpty) ...[
                const SizedBox(height: DesignTokens.space4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(DesignTokens.space4),
                  decoration: BoxDecoration(
                    color: DesignTokens.infoSoft,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusCard,
                    ),
                  ),
                  child: Text(
                    'No words are due right now. Choose a category to practice specific words.',
                    style: DesignTokens.body(14).copyWith(height: 1.4),
                  ),
                ),
              ],
              const Spacer(),
              PasseportPrimaryButton(
                label: queue.isEmpty
                    ? 'No recommended words yet'
                    : 'Start ${queue.length}-word practice',
                icon: CupertinoIcons.arrow_right,
                onPressed: isLoading || queue.isEmpty
                    ? null
                    : () => _beginSession(queue),
              ),
            ],
          ),
        );
      },
    );
  }

  // MARK: - Category mode

  int _selectedCount(VocabTheme theme) =>
      theme.entries.where((e) => _manualSelection.contains(e.id)).length;

  Widget _categoryBody() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            children: _allPhases.map((phase) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KickerText(
                      'Phase ${phase.phase} · ${phase.title}',
                      color: DesignTokens.slateDim,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: phase.themes
                          .map((theme) => _categoryChip(theme))
                          .toList(),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          color: DesignTokens.canvas,
          child: _startButton(
            count: _manualSelection.length,
            onPressed: () {
              final all = _allPhases
                  .expand((p) => p.themes.expand((t) => t.entries))
                  .toList();
              _beginSession(
                all.where((e) => _manualSelection.contains(e.id)).toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _categoryChip(VocabTheme theme) {
    final selected = _selectedCount(theme);
    final hasSelection = selected > 0;
    return GestureDetector(
      onTap: () => _showCategoryWordSheet(theme),
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: hasSelection ? DesignTokens.infoSoft : DesignTokens.surface,
          borderRadius: BorderRadius.circular(10),
          border: hasSelection
              ? null
              : Border.all(color: DesignTokens.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              theme.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.body(
                12.5,
                weight: FontWeight.w500,
              ).copyWith(color: DesignTokens.ink),
            ),
            const SizedBox(height: 3),
            Text(
              hasSelection
                  ? '$selected of ${theme.entries.length} picked'
                  : '${theme.entries.length} words',
              style: DesignTokens.body(11).copyWith(
                color: hasSelection ? DesignTokens.info : DesignTokens.slateDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCategoryWordSheet(VocabTheme theme) {
    showPSModalSheet(
      context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final allSelected = theme.entries.every(
            (e) => _manualSelection.contains(e.id),
          );
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            setState(() {
                              if (allSelected) {
                                for (final e in theme.entries) {
                                  _manualSelection.remove(e.id);
                                }
                              } else {
                                for (final e in theme.entries) {
                                  _manualSelection.add(e.id);
                                }
                              }
                            });
                          });
                        },
                        child: Text(
                          allSelected ? 'Deselect All' : 'Select All',
                        ),
                      ),
                      const Spacer(),
                      Text(
                        theme.title,
                        style: DesignTokens.display(
                          15,
                          weight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 170,
                          mainAxisExtent: 56,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: theme.entries.length,
                    itemBuilder: (context, i) {
                      final entry = theme.entries[i];
                      return _wordChip(entry, setSheetState);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _wordChip(
    VocabEntry entry,
    void Function(void Function()) setSheetState,
  ) {
    final isKnown = _knownIds.contains(entry.id);
    final isSelected = _manualSelection.contains(entry.id);
    return GestureDetector(
      onTap: () {
        setSheetState(() {
          setState(() {
            if (isSelected) {
              _manualSelection.remove(entry.id);
            } else {
              _manualSelection.add(entry.id);
            }
          });
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? DesignTokens.infoSoft : DesignTokens.surface,
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? null : Border.all(color: DesignTokens.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.fr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.body(
                      12.5,
                      weight: FontWeight.w500,
                    ).copyWith(color: DesignTokens.ink),
                  ),
                ),
                if (isKnown)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      CupertinoIcons.checkmark_seal_fill,
                      size: 10,
                      color: DesignTokens.success,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    isSelected
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                    size: 13,
                    color: isSelected ? DesignTokens.info : DesignTokens.slate,
                  ),
                ),
              ],
            ),
            Text(
              entry.en,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.body(11).copyWith(
                color: isSelected ? DesignTokens.info : DesignTokens.slateDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Shared

  Widget _startButton({required int count, required VoidCallback onPressed}) {
    return PasseportPrimaryButton(
      label: count > 0
          ? "Start with $count word${count == 1 ? '' : 's'}"
          : 'Pick some words first',
      onPressed: count > 0 ? onPressed : null,
    );
  }

  /// Briefly personalizes the session before it starts — the planner call is raced against a
  /// short timeout so a slow/failed OpenRouter call never blocks getting into practice. Example
  /// sentences are pre-authored offline for the entire word bank and looked up instantly via
  /// ContentService, so there's nothing to wait on or fail for that part.
  Future<void> _beginSession(List<VocabEntry> words) async {
    if (words.isEmpty) return;
    setState(() => _isPlanning = true);
    final store = ref.read(learningStoreProvider);
    final mistakeTags = store.topMistakeTags();
    final diary = store.recentDiaryEntries();

    SessionPlan? planResult;
    try {
      planResult = await LessonAgentService.shared
          .planVocabSession(
            candidateWords: words,
            mistakeTags: mistakeTags
                .map(
                  (m) =>
                      (tag: m.tag, description: m.description, count: m.count),
                )
                .toList(),
            recentDiary: diary.map((d) => d.summary).toList(),
          )
          .timeout(const Duration(seconds: 14));
    } catch (_) {
      planResult = null;
    }

    List<VocabEntry> chosenQueue;
    String? focusNote;
    if (planResult != null) {
      focusNote = planResult.focusNote.isEmpty ? null : planResult.focusNote;
      final prioritized = planResult.prioritizedWordIds;
      if (prioritized != null) {
        final byId = {for (final w in words) w.id: w};
        chosenQueue = prioritized
            .map((id) => byId[id])
            .whereType<VocabEntry>()
            .toList();
      } else {
        chosenQueue = words;
      }
    } else {
      chosenQueue = words;
    }
    final sessionExamples = ContentService.shared.vocabExamplesFor(words);

    if (!mounted) return;
    setState(() => _isPlanning = false);

    final outcome = await AppRouter.push<StageOutcome<VocabStageResult>>(
      context,
      (_) => AgentLedVocabScreen(
        vocabQueue: chosenQueue,
        focusNote: focusNote,
        examplesByWordId: sessionExamples,
      ),
      fullscreenDialog: true,
    );
    if (outcome != null && mounted) Navigator.of(context).pop(outcome);
  }
}
