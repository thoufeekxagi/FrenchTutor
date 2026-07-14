import '../../widgets/adaptive/adaptive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../design/app_router.dart';
import '../../flow/stage_outcome.dart';
import '../../data/content_service.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/srs_service.dart';
import '../../widgets/passeport_card.dart';
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
    return store.allSRSStates().entries.where((e) => e.value.reps >= 3 && e.value.intervalDays >= 21).map((e) => e.key).toSet();
  }

  List<VocabPhase> get _allPhases => ContentService.shared.vocabPhases;

  Future<List<VocabEntry>> get _autoQueue => SRSService(store: ref.read(learningStoreProvider)).dailyMixedQueue();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: Text("Today's Words", style: Passeport.display(18)),
        backgroundColor: Passeport.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: SegmentedButton<_PickerMode>(
                  segments: const [
                    ButtonSegment(value: _PickerMode.auto, label: Text('Auto')),
                    ButtonSegment(value: _PickerMode.category, label: Text('By Category')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ),
              Expanded(child: _mode == _PickerMode.auto ? _autoBody() : _categoryBody()),
            ],
          ),
          if (_isPlanning)
            Container(
              color: Colors.black.withValues(alpha: 0.15),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Passeport.card, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PSProgressIndicator(),
                      const SizedBox(height: 10),
                      Text("Personalizing today's session…", style: Passeport.mono(11).copyWith(color: Passeport.slateDim)),
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            children: [
              const Spacer(),
              PasseportCard(
                padding: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 30, color: Passeport.brass),
                    const SizedBox(height: 10),
                    Text('${queue.length} words today', style: Passeport.display(20, weight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Text(
                      'A mix of words due for review plus new ones, in curriculum order — the same set Marie would pick for you.',
                      style: Passeport.body(13).copyWith(color: Passeport.slateDim),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _startButton(count: queue.length, onPressed: () => _beginSession(queue)),
            ],
          ),
        );
      },
    );
  }

  // MARK: - Category mode

  int _selectedCount(VocabTheme theme) => theme.entries.where((e) => _manualSelection.contains(e.id)).length;

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
                    KickerText('Phase ${phase.phase} · ${phase.title}', color: Passeport.slateDim),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: phase.themes.map((theme) => _categoryChip(theme)).toList(),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          color: Passeport.parchmentDim,
          child: _startButton(
            count: _manualSelection.length,
            onPressed: () {
              final all = _allPhases.expand((p) => p.themes.expand((t) => t.entries)).toList();
              _beginSession(all.where((e) => _manualSelection.contains(e.id)).toList());
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
          color: hasSelection ? Passeport.maroon : Passeport.card,
          borderRadius: BorderRadius.circular(10),
          border: hasSelection ? null : Border.all(color: Passeport.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              theme.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Passeport.body(12.5, weight: FontWeight.w500).copyWith(color: hasSelection ? Passeport.parchment : Passeport.text),
            ),
            const SizedBox(height: 3),
            Text(
              hasSelection ? '$selected of ${theme.entries.length} picked' : '${theme.entries.length} words',
              style: Passeport.mono(9).copyWith(color: hasSelection ? Passeport.parchment.withValues(alpha: 0.85) : Passeport.slateDim),
            ),
          ],
        ),
      ),
    );
  }

  void _showCategoryWordSheet(VocabTheme theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Passeport.card,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final allSelected = theme.entries.every((e) => _manualSelection.contains(e.id));
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
                        child: Text(allSelected ? 'Deselect All' : 'Select All'),
                      ),
                      const Spacer(),
                      Text(theme.title, style: Passeport.display(15, weight: FontWeight.w500)),
                      const Spacer(),
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 170, mainAxisExtent: 56, crossAxisSpacing: 8, mainAxisSpacing: 8),
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

  Widget _wordChip(VocabEntry entry, void Function(void Function()) setSheetState) {
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
          color: isSelected ? Passeport.maroon : Passeport.card,
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? null : Border.all(color: Passeport.hairline),
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
                    style: Passeport.body(12.5, weight: FontWeight.w500).copyWith(color: isSelected ? Passeport.parchment : Passeport.text),
                  ),
                ),
                if (isKnown) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: 10, color: Colors.green)),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    size: 13,
                    color: isSelected ? Passeport.parchment : Passeport.slate,
                  ),
                ),
              ],
            ),
            Text(
              entry.en,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Passeport.mono(9.5).copyWith(color: isSelected ? Passeport.parchment.withValues(alpha: 0.85) : Passeport.slateDim),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Shared

  Widget _startButton({required int count, required VoidCallback onPressed}) {
    return PasseportPrimaryButton(
      label: count > 0 ? "Start with $count word${count == 1 ? '' : 's'}" : 'Pick some words first',
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
            mistakeTags: mistakeTags.map((m) => (tag: m.tag, description: m.description, count: m.count)).toList(),
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
        chosenQueue = prioritized.map((id) => byId[id]).whereType<VocabEntry>().toList();
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
