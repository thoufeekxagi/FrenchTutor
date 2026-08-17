import 'dart:async';

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
import '../../services/speak_language_profile.dart';
import '../../services/srs_service.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/primary_action_button.dart';
import 'agent_led_vocab_screen.dart';
import '../lessons/vocabulary_workshop_screen.dart';

enum _PickerMode { auto, category, custom }

/// Sits in front of the vocab stage so today's word list isn't always a black-box auto-pick.
/// Two modes: fully automatic (today's mixed SRS queue, unchanged default), and a
/// category-first manual picker — choose a section, then a sheet shows just that section's
/// words to select from. Already-known words (SM-2 reps >= 3, interval >= 21 days) show a
/// green check and are excluded from Auto mode by default, though they can still be manually
/// re-picked. Ported from VocabPickerView.swift.
class VocabPickerScreen extends ConsumerStatefulWidget {
  const VocabPickerScreen({super.key, this.preferredEntryIds});

  final List<String>? preferredEntryIds;

  @override
  ConsumerState<VocabPickerScreen> createState() => _VocabPickerScreenState();
}

class _VocabPickerScreenState extends ConsumerState<VocabPickerScreen> {
  _PickerMode _mode = _PickerMode.auto;
  final Set<String> _manualSelection = {};
  final _customController = TextEditingController();
  bool _isPlanning = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

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

  Future<List<VocabEntry>> get _autoQueue async {
    final preferredIds = widget.preferredEntryIds;
    if (preferredIds != null) {
      final byId = {
        for (final entry in _allPhases.expand(
          (phase) => phase.themes.expand((theme) => theme.entries),
        ))
          entry.id: entry,
      };
      return preferredIds
          .map((id) => byId[id])
          .whereType<VocabEntry>()
          .toList();
    }
    return SRSService(store: ref.read(learningStoreProvider)).dailyMixedQueue();
  }

  /// How many words the session actually ends up with — for a mission's
  /// preferred set that's just its length; for the Auto tile, `_autoQueue`
  /// now returns an oversized candidate POOL, so the real count is whatever
  /// `SRSService.autoQueueSize` is currently set to (capped by how many the
  /// pool actually has, for a very sparse bank).
  Future<int> _autoQueueDisplayCount(int poolSize) async {
    if (widget.preferredEntryIds != null) return poolSize.clamp(0, 5).toInt();
    final target = await SRSService.autoQueueSize;
    return (poolSize < target ? poolSize : target).clamp(0, 5).toInt();
  }

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
              'today, pick up where you left off.',
              style: DesignTokens.body(13.5),
            ),
            const SizedBox(height: 12),
            PrimaryActionButton(
              label: 'Continue, ${resumable.remaining.length} words left',
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
            color: DesignTokens.mutedDim,
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
                  if (widget.preferredEntryIds == null)
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
                          (value: _PickerMode.custom, label: 'Custom'),
                        ],
                        selected: _mode,
                        onChanged: (mode) => setState(() => _mode = mode),
                      ),
                    ),
                  Expanded(
                    child:
                        widget.preferredEntryIds != null ||
                            _mode == _PickerMode.auto
                        ? _autoBody()
                        : _mode == _PickerMode.category
                        ? _categoryBody()
                        : _customBody(),
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
                        ).copyWith(color: DesignTokens.mutedDim),
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
        return FutureBuilder<int>(
          future: _autoQueueDisplayCount(queue.length),
          builder: (context, countSnapshot) {
            final displayCount = countSnapshot.data ?? queue.length;
            return _autoBodyContent(
              queue: queue,
              isLoading: isLoading,
              displayCount: displayCount,
            );
          },
        );
      },
    );
  }

  Widget _autoBodyContent({
    required List<VocabEntry> queue,
    required bool isLoading,
    required int displayCount,
  }) {
    final previewWords = queue.take(displayCount).toList(growable: false);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.screenMargin,
              DesignTokens.space7,
              DesignTokens.screenMargin,
              DesignTokens.space5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: DesignTokens.infoSoft,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Icon(
                    CupertinoIcons.rectangle_stack_fill,
                    color: DesignTokens.info,
                    size: 31,
                  ),
                ),
                const SizedBox(height: DesignTokens.space5),
                KickerText(
                  isLoading ? 'Preparing your set' : 'Today’s vocabulary',
                  color: DesignTokens.info,
                ),
                const SizedBox(height: DesignTokens.space2),
                Text(
                  isLoading
                      ? 'Building a useful set for you.'
                      : '$displayCount words ready',
                  textAlign: TextAlign.center,
                  style: DesignTokens.display(30),
                ),
                const SizedBox(height: DesignTokens.space3),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Text(
                    widget.preferredEntryIds == null
                        ? 'A fresh mix of due reviews and new words, chosen for today’s practice.'
                        : 'A focused set selected for your current mission. Learn these before moving on.',
                    textAlign: TextAlign.center,
                    style: DesignTokens.body(
                      15,
                    ).copyWith(color: DesignTokens.mutedDim, height: 1.45),
                  ),
                ),
                if (isLoading) ...[
                  const SizedBox(height: DesignTokens.space6),
                  const SizedBox(width: 132, child: PSProgressIndicator()),
                ] else if (queue.isEmpty) ...[
                  const SizedBox(height: DesignTokens.space5),
                  _emptyRecommendedWordsNotice(),
                ] else ...[
                  const SizedBox(height: DesignTokens.space6),
                  _wordSetPreview(previewWords, displayCount),
                ],
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: PrimaryActionButton(
            label: queue.isEmpty
                ? 'No recommended words yet'
                : 'Start $displayCount-word practice',
            icon: CupertinoIcons.arrow_right,
            onPressed: isLoading || queue.isEmpty
                ? null
                : () => _beginSession(queue, curateFromPool: true),
          ),
        ),
      ],
    );
  }

  Widget _wordSetPreview(List<VocabEntry> words, int displayCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Your first set',
                style: DesignTokens.body(13, weight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '$displayCount words',
                style: DesignTokens.body(
                  12,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final word in words)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: DesignTokens.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    word.fr,
                    style: DesignTokens.body(
                      13,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.primaryDeep),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyRecommendedWordsNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignTokens.space4),
      decoration: BoxDecoration(
        color: DesignTokens.infoSoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Text(
        'No words are due right now. Choose a category to practise specific words.',
        textAlign: TextAlign.center,
        style: DesignTokens.body(14).copyWith(height: 1.4),
      ),
    );
  }

  // MARK: - Category mode

  Widget _customBody() {
    final profile = ref.read(learningStoreProvider).profile();
    final level = SpeakLanguageProfile.forProfile(profile).level;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.screenMargin,
        DesignTokens.space6,
        DesignTokens.screenMargin,
        DesignTokens.space5,
      ),
      children: [
        const Icon(CupertinoIcons.sparkles, color: DesignTokens.info, size: 30),
        const SizedBox(height: DesignTokens.space4),
        Text('Build a custom five-word set', style: DesignTokens.display(26)),
        const SizedBox(height: DesignTokens.space2),
        Text(
          'Tell the tutor what you want to practise. The words will match your $level level and use the same Preview → Learn → Recall flow.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
        ),
        const SizedBox(height: DesignTokens.space5),
        TextField(
          controller: _customController,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'What should the words be about?',
            hintText: 'Numbers, travel, food, work…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: DesignTokens.space5),
        PrimaryActionButton(
          label: 'Generate five words',
          icon: CupertinoIcons.arrow_right,
          onPressed: _isPlanning ? null : _beginCustomSession,
        ),
      ],
    );
  }

  Future<void> _beginCustomSession() async {
    final prompt = _customController.text.trim();
    if (prompt.isEmpty) return;
    setState(() => _isPlanning = true);
    try {
      final profile = ref.read(learningStoreProvider).profile();
      final level = SpeakLanguageProfile.forProfile(profile).level;
      final words = await LessonAgentService.shared.generateCourseVocabulary(
        levelBand: level,
        unitTitle: 'Custom vocabulary',
        sessionTitle: prompt,
        contextPrompt: 'Create a useful five-word set about: $prompt',
        targetPhrases: const [],
        count: 5,
      );
      if (words.length < 5) throw StateError('Incomplete vocabulary set');
      final id = 'custom-vocabulary-${DateTime.now().microsecondsSinceEpoch}';
      ref
          .read(generatedVocabularySetStoreProvider)
          .insert(
            GeneratedVocabularySet(
              id: id,
              title: prompt,
              summary: 'Custom vocabulary for $prompt.',
              topic: prompt,
              levelBand: level,
              entries: words.take(5).toList(growable: false),
              createdAt: DateTime.now(),
            ),
          );
      unawaited(_attachCustomCover(id, prompt, level, words.take(5).toList()));
      if (!mounted) return;
      setState(() => _isPlanning = false);
      await AppRouter.push<bool>(
        context,
        (_) => VocabularyWorkshopScreen(
          phase: 1,
          theme: VocabTheme(id: id, title: prompt, entries: words),
          initialDeck: words.take(5).toList(growable: false),
          contentItemPrefix: id,
          focusNote:
              'Custom words generated for your $level level. Audio is prepared while you preview the deck.',
        ),
        fullscreenDialog: true,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _isPlanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate that word set yet.'),
          ),
        );
      }
    }
  }

  Future<void> _attachCustomCover(
    String id,
    String topic,
    String level,
    List<VocabEntry> words,
  ) async {
    try {
      final wordList = words
          .map((word) => '${word.fr} (${word.en})')
          .join(', ');
      final bytes = await LessonAgentService.shared.generateStoryCover(
        title: topic,
        summary: 'Custom French vocabulary for $topic. Words: $wordList.',
        topic: topic,
        levelBand: level,
        coverPrompt:
            'Create one coherent real-life learning scene for a French vocabulary set about $topic. Use visual details that represent these exact words: $wordList. Show the words through objects, actions, or a natural setting, never as written labels. No text, letters, logos, borders, watermarks, collage panels, or UI.',
      );
      final url = await ref
          .read(syncServiceProvider)
          .uploadStoryCover(storyId: id, bytes: bytes);
      if (url != null && url.isNotEmpty) {
        ref.read(generatedVocabularySetStoreProvider).updateCoverUrl(id, url);
      }
    } catch (error) {
      debugPrint('Custom vocabulary cover failed: $error');
    }
  }

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
                      color: DesignTokens.mutedDim,
                    ),
                    const SizedBox(height: 8),
                    // Two full-width columns — the old fixed 150px chips left
                    // a dead strip of unused space down the right edge.
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final chipWidth = (constraints.maxWidth - 8) / 2;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: phase.themes
                              .map((theme) => _categoryChip(theme, chipWidth))
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        PSBottomActionBar(
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

  Widget _categoryChip(VocabTheme theme, double width) {
    final selected = _selectedCount(theme);
    final hasSelection = selected > 0;
    return GestureDetector(
      onTap: () => _showCategoryWordSheet(theme),
      child: Container(
        width: width,
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
                color: hasSelection ? DesignTokens.info : DesignTokens.mutedDim,
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
            // The PS sheet wrapper is transparent by design — content brings
            // its own surface. Without this the word grid floated see-through
            // over the dimmed screen behind it.
            builder: (context, scrollController) => Container(
              decoration: const BoxDecoration(
                color: DesignTokens.canvas,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
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
                    color: isSelected ? DesignTokens.info : DesignTokens.muted,
                  ),
                ),
              ],
            ),
            Text(
              entry.en,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.body(11).copyWith(
                color: isSelected ? DesignTokens.info : DesignTokens.mutedDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Shared

  Widget _startButton({required int count, required VoidCallback onPressed}) {
    return PrimaryActionButton(
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
  ///
  /// [curateFromPool] is only true for the Auto tile: [words] there is a
  /// deliberately oversized candidate POOL (see `SRSService.dailyMixedQueue`),
  /// and this call is what actually selects the real session size out of it.
  /// Resuming a paused session or a manual category pick already IS the
  /// exact intended set — those must never be curated/truncated further.
  Future<void> _beginSession(
    List<VocabEntry> words, {
    bool curateFromPool = false,
  }) async {
    if (words.isEmpty) return;
    setState(() => _isPlanning = true);
    final store = ref.read(learningStoreProvider);
    final targetSize = curateFromPool
        ? (await SRSService.autoQueueSize).clamp(1, 5).toInt()
        : words.length.clamp(1, 5).toInt();

    SessionPlan? planResult;
    try {
      planResult = await LessonAgentService.shared
          .planVocabSession(candidateWords: words, count: targetSize)
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
            .take(targetSize)
            .toList();
      } else {
        // `words` is already shuffled by `dailyMixedQueue` for the Auto
        // tile, so even this fallback gives a different set call to call —
        // never the same deterministic slice every time.
        chosenQueue = words.take(targetSize).toList();
      }
    } else {
      chosenQueue = words.take(targetSize).toList();
    }
    if (!mounted) return;
    setState(() => _isPlanning = false);

    final profile = store.profile();
    final level = SpeakLanguageProfile.forProfile(profile).level;
    final sessionId =
        'vocabulary-session-${DateTime.now().microsecondsSinceEpoch}';
    final topic = curateFromPool
        ? 'Recommended vocabulary'
        : 'Course vocabulary';
    final summary =
        focusNote ??
        'A saved vocabulary practice set built from the words selected for this session.';
    ref
        .read(generatedVocabularySetStoreProvider)
        .insert(
          GeneratedVocabularySet(
            id: sessionId,
            title: 'Today\'s Words',
            summary: summary,
            topic: topic,
            levelBand: level,
            entries: chosenQueue,
            createdAt: DateTime.now(),
          ),
        );
    unawaited(
      _attachSessionCover(
        id: sessionId,
        topic: topic,
        context: summary,
        level: level,
        words: chosenQueue,
      ),
    );

    final workshopResult = await AppRouter.push<bool>(
      context,
      (_) => VocabularyWorkshopScreen(
        phase: 1,
        theme: VocabTheme(
          id: 'daily-vocabulary',
          title: 'Today\'s Words',
          entries: chosenQueue,
        ),
        initialDeck: chosenQueue,
        contentItemPrefix: 'daily-vocabulary',
        focusNote: focusNote,
      ),
      fullscreenDialog: true,
    );
    if (!mounted) return;
    final result = VocabStageResult(
      wordsCovered: workshopResult == true ? chosenQueue : const [],
      reviewedCount: workshopResult == true ? chosenQueue.length : 0,
      plannedWordIds: chosenQueue.map((word) => word.id).toList(),
    );
    Navigator.of(context).pop(
      workshopResult == true
          ? StageOutcome.completed(result)
          : StageOutcome<VocabStageResult>.paused(
              result: result,
              reason: 'cancelled',
            ),
    );
  }

  Future<void> _attachSessionCover({
    required String id,
    required String topic,
    required String context,
    required String level,
    required List<VocabEntry> words,
  }) async {
    try {
      final wordList = words
          .map((word) => '${word.fr} (${word.en})')
          .join(', ');
      final bytes = await LessonAgentService.shared.generateStoryCover(
        title: 'Today\'s Words',
        summary: '$context Words: $wordList.',
        topic: topic,
        levelBand: level,
        coverPrompt:
            'Create one coherent real-life learning scene that visually represents this exact French vocabulary set: $wordList. Let the context guide the setting: $context. Show meaning through objects, actions, and human context, never written labels. No text, letters, logos, borders, watermarks, collage panels, or UI.',
      );
      final url = await ref
          .read(syncServiceProvider)
          .uploadStoryCover(storyId: id, bytes: bytes);
      if (url != null && url.isNotEmpty) {
        ref.read(generatedVocabularySetStoreProvider).updateCoverUrl(id, url);
      }
    } catch (error) {
      debugPrint('Vocabulary session cover failed: $error');
    }
  }
}
