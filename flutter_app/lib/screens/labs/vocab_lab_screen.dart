import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/vocabulary_session_store.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/practice_artwork_service.dart';
import '../../services/speak_language_profile.dart';
import '../../services/sync_service.dart';
import '../../services/vocabulary_level_policy.dart';
import '../../services/vocabulary_story_catalog.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../settings/settings_screen.dart';
import 'vocabulary_flashcards_screen.dart';
import '../../widgets/v3/v3_surface.dart';

/// Vocabulary starts with a small set library. Each set owns five words and a
/// short connected story that supplies the teaching and review context.
class VocabLabScreen extends ConsumerStatefulWidget {
  const VocabLabScreen({super.key, this.topic});

  final String? topic;

  @override
  ConsumerState<VocabLabScreen> createState() => _VocabLabScreenState();
}

class _VocabularySetPreview {
  const _VocabularySetPreview({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.topic,
    required this.levelBand,
    required this.entries,
    required this.icon,
    this.source = 'curriculum',
  });

  final String id;
  final String title;
  final String subtitle;
  final String topic;
  final String levelBand;
  final List<VocabEntry> entries;
  final IconData icon;
  final String source;
}

class _VocabLabScreenState extends ConsumerState<VocabLabScreen> {
  List<VocabularySessionRecord> _sessions = const [];
  String? _selectedSetId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (!mounted) return;
    try {
      setState(() {
        _sessions = ref.read(vocabularySessionStoreProvider).recent(limit: 8);
      });
    } catch (error, stackTrace) {
      debugPrint('Vocabulary library load failed: $error\n$stackTrace');
    }
  }

  Future<void> _openFlashcards({
    required String title,
    required List<VocabEntry> entries,
    required String source,
    required String topic,
    required String levelBand,
    String? coverUrl,
  }) async {
    await AppRouter.push<bool>(
      context,
      (_) => VocabularyFlashcardsScreen(
        title: title,
        entries: entries,
        source: source,
        topic: topic,
        levelBand: levelBand,
        studyDepth: VocabularyStudyDepth.wordsAndSentences,
        storyExamples: _storyExamplesFor(title, entries),
        coverUrl: coverUrl,
      ),
      fullscreenDialog: true,
    );
    if (mounted) _load();
  }

  String get _profileLevel {
    final profile = ref.read(learningStoreProvider).profile();
    return SpeakLanguageProfile.forProfile(profile).level;
  }

  Map<String, BilingualExample> _storyExamplesFor(
    String title,
    List<VocabEntry> entries,
  ) {
    for (final story in VocabularyStoryCatalog.starterSets) {
      if (story.title == title) return story.examplesFor(entries);
    }
    return const {};
  }

  Widget _levelBadge({required String level}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: DesignTokens.primarySoft,
      borderRadius: BorderRadius.circular(100),
      border: Border.all(color: DesignTokens.primary),
    ),
    child: Text(level, style: DesignTokens.label(11, weight: FontWeight.w800)),
  );

  Widget _sectionLabel(String value) => Text(
    value,
    style: DesignTokens.label(
      12,
      weight: FontWeight.w800,
    ).copyWith(color: DesignTokens.primary, letterSpacing: 1.15),
  );

  @override
  Widget build(BuildContext context) {
    final sets = _setPreviews();
    final featured = _selectedSet(sets);
    final completedCount = sets.where(_isSetCompleted).length;
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: WebConstrainedView(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 34),
            children: [
              _homeHeader(context),
              const SizedBox(height: 22),
              Text('Make words stick', style: DesignTokens.display(30)),
              const SizedBox(height: 8),
              Text(
                'Choose a story set and learn five useful words that stay connected.',
                style: DesignTokens.body(
                  14,
                ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _levelBadge(level: _profileLevel),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${sets.length} story sets · $completedCount complete',
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _sectionLabel('NEXT SET'),
              const SizedBox(height: 10),
              if (featured != null) _featuredSetCard(featured),
              const SizedBox(height: 28),
              _sectionLabel('STORY SETS'),
              const SizedBox(height: 10),
              _setGrid(sets),
              const SizedBox(height: 22),
              _createSetRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeHeader(BuildContext context) => SizedBox(
    height: 52,
    child: Row(
      children: [
        Semantics(
          button: true,
          label: 'Back',
          child: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: DesignTokens.ink,
          ),
        ),
        Expanded(
          child: Text(
            'Vocabulary',
            textAlign: TextAlign.center,
            style: DesignTokens.display(21),
          ),
        ),
        Semantics(
          button: true,
          label: 'Vocabulary settings',
          child: IconButton(
            onPressed: () =>
                AppRouter.push(context, (_) => const SettingsScreen()),
            icon: const Icon(Icons.tune_rounded),
            color: DesignTokens.primary,
          ),
        ),
      ],
    ),
  );

  List<_VocabularySetPreview> _setPreviews() {
    // Keep this first release deterministic while the story/review loop is
    // being validated. The lexical picker can append sets in a later pass.
    return _starterPreviews;
  }

  List<_VocabularySetPreview> get _starterPreviews => [
    for (final story in VocabularyStoryCatalog.starterSets)
      _VocabularySetPreview(
        id: story.id,
        title: story.title,
        subtitle: story.subtitle,
        topic: story.topic,
        levelBand: story.levelBand,
        entries: story.entries,
        icon: _iconForSet(story.title, story.topic),
        source: 'starter-story',
      ),
  ];

  IconData _iconForSet(String title, String topic) {
    final value = '$title $topic'.toLowerCase();
    if (value.contains('greet') || value.contains('polite')) {
      return Icons.chat_bubble_outline_rounded;
    }
    if (value.contains('food') ||
        value.contains('restaurant') ||
        value.contains('café')) {
      return Icons.local_cafe_outlined;
    }
    if (value.contains('home') || value.contains('housing')) {
      return Icons.home_outlined;
    }
    if (value.contains('travel') ||
        value.contains('transport') ||
        value.contains('town')) {
      return Icons.map_outlined;
    }
    if (value.contains('time') ||
        value.contains('day') ||
        value.contains('routine')) {
      return Icons.calendar_month_outlined;
    }
    if (value.contains('work') || value.contains('career')) {
      return Icons.work_outline_rounded;
    }
    if (value.contains('health')) return Icons.local_pharmacy_outlined;
    return Icons.auto_awesome_rounded;
  }

  _VocabularySetPreview? _selectedSet(List<_VocabularySetPreview> sets) {
    if (sets.isEmpty) return null;
    for (final set in sets) {
      if (set.id == _selectedSetId) return set;
    }
    for (final set in sets) {
      if (!_isSetCompleted(set)) return set;
    }
    return sets.first;
  }

  bool _isSetCompleted(_VocabularySetPreview set) => _sessions.any(
    (session) =>
        session.title.trim().toLowerCase() == set.title.trim().toLowerCase() &&
        session.status == VocabularySessionStatus.completed,
  );

  Widget _featuredSetCard(_VocabularySetPreview set) {
    final complete = _isSetCompleted(set);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
        border: Border.all(color: DesignTokens.primary),
        boxShadow: DesignTokens.surfaceShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _setIcon(set, large: true),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(set.title, style: DesignTokens.display(18)),
                    const SizedBox(height: 4),
                    Text(
                      '${set.levelBand} · ${set.entries.length} words',
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.muted),
                    ),
                  ],
                ),
              ),
              if (complete)
                Icon(Icons.check_circle_rounded, color: DesignTokens.success),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            set.subtitle,
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 16),
          Divider(color: DesignTokens.hairline),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final phase in const [
                (Icons.menu_book_outlined, 'Story'),
                (Icons.short_text_rounded, 'Learn'),
                (Icons.check_circle_outline_rounded, 'Recall'),
              ])
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(phase.$1, color: DesignTokens.primary, size: 17),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          phase.$2,
                          style: DesignTokens.label(10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          PrimaryActionButton(
            label: 'Start story set',
            onPressed: () => unawaited(_openPreviewSet(set)),
          ),
        ],
      ),
    );
  }

  Widget _setGrid(List<_VocabularySetPreview> sets) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: sets.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 0.96,
    ),
    itemBuilder: (context, index) {
      final set = sets[index];
      return _VocabularySetCard(
        key: ValueKey(set.id),
        set: set,
        selected: set.id == _selectedSetId,
        complete: _isSetCompleted(set),
        onTap: () => setState(() => _selectedSetId = set.id),
      );
    },
  );

  Widget _setIcon(_VocabularySetPreview set, {bool large = false}) => Container(
    width: large ? 54 : 42,
    height: large ? 54 : 42,
    decoration: BoxDecoration(
      color: DesignTokens.primarySoft,
      borderRadius: BorderRadius.circular(large ? DesignTokens.radiusCard : 13),
    ),
    child: Icon(set.icon, color: DesignTokens.primary, size: large ? 27 : 21),
  );

  Widget _createSetRow() => Material(
    color: DesignTokens.surface,
    borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
    child: InkWell(
      onTap: () => unawaited(_openCreateSet()),
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          border: Border.all(color: DesignTokens.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: DesignTokens.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create a custom set',
                    style: DesignTokens.body(14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Generate five words for your own topic.',
                    style: DesignTokens.body(
                      11,
                    ).copyWith(color: DesignTokens.muted, height: 1.35),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: DesignTokens.primary),
          ],
        ),
      ),
    ),
  );

  Future<void> _openCreateSet() async {
    final set = await showModalBottomSheet<GeneratedVocabularySet>(
      context: context,
      backgroundColor: DesignTokens.nightSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _VocabularySetMakerSheet(),
    );
    if (set != null && mounted) {
      await _openFlashcards(
        title: set.title,
        entries: set.entries,
        source: 'custom',
        topic: set.topic,
        levelBand: set.levelBand,
        coverUrl: set.coverUrl,
      );
    }
  }

  Future<void> _openPreviewSet(_VocabularySetPreview set) async {
    if (set.entries.isEmpty) return;
    await _openFlashcards(
      title: set.title,
      entries: set.entries,
      source: set.source,
      topic: set.topic,
      levelBand: set.levelBand,
    );
  }
}

class _VocabularySetCard extends StatelessWidget {
  const _VocabularySetCard({
    super.key,
    required this.set,
    required this.selected,
    required this.complete,
    required this.onTap,
  });

  final _VocabularySetPreview set;
  final bool selected;
  final bool complete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${set.title}, ${set.entries.length} vocabulary words',
    child: Material(
      color: selected ? DesignTokens.primarySoft : DesignTokens.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 11, 9, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? DesignTokens.primary : DesignTokens.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: selected
                          ? DesignTokens.primary
                          : DesignTokens.primarySoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      set.icon,
                      size: 18,
                      color: selected
                          ? DesignTokens.onPrimary
                          : DesignTokens.primary,
                    ),
                  ),
                  const Spacer(),
                  if (complete)
                    Icon(
                      Icons.check_circle_rounded,
                      color: DesignTokens.success,
                      size: 19,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                set.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.body(14, weight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${set.entries.length} words',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.body(
                  11,
                ).copyWith(color: DesignTokens.muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _VocabularySetMakerSheet extends ConsumerStatefulWidget {
  const _VocabularySetMakerSheet();

  @override
  ConsumerState<_VocabularySetMakerSheet> createState() =>
      _VocabularySetMakerSheetState();
}

class _VocabularySetMakerSheetState
    extends ConsumerState<_VocabularySetMakerSheet> {
  final _controller = TextEditingController();
  bool _generating = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty || _generating) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final profile = ref.read(learningStoreProvider).profile();
      final level = SpeakLanguageProfile.forProfile(profile).level;
      final generated = await ref
          .read(lessonAgentServiceProvider)
          .generateCourseVocabulary(
            levelBand: level,
            unitTitle: 'Vocabulary set',
            sessionTitle: prompt,
            contextPrompt:
                'Create exactly five useful A1 vocabulary words about $prompt. '
                'Keep them concrete and tightly connected to one short everyday story.',
            targetPhrases: const [],
            count: 5,
          );
      final words = VocabularyLevelPolicy.filterGenerated(
        generated,
        level,
      ).take(5).toList(growable: false);
      if (words.length < 3) {
        throw StateError('The generated set did not contain enough words.');
      }
      final id = 'vocabulary-set-${DateTime.now().microsecondsSinceEpoch}';
      final set = GeneratedVocabularySet(
        id: id,
        title: prompt,
        summary:
            'Five useful French words connected by one short story about $prompt.',
        topic: prompt,
        levelBand: level,
        entries: words,
        createdAt: DateTime.now(),
      );
      ref.read(generatedVocabularySetStoreProvider).insert(set);
      unawaited(_attachCover(set, ref.read(syncServiceProvider)));
      if (mounted) Navigator.of(context).pop(set);
    } catch (error) {
      if (mounted) {
        setState(() {
          _generating = false;
          _error = 'We could not make that set. Try a simpler topic.';
        });
      }
      debugPrint('Vocabulary set generation failed: $error');
    }
  }

  Future<void> _attachCover(
    GeneratedVocabularySet set,
    SyncService sync,
  ) async {
    // Capture the store before the sheet is dismissed. Artwork generation is
    // intentionally fire-and-forget, so this callback must not read `ref`
    // after the sheet's State has been disposed.
    final vocabularySets = ref.read(generatedVocabularySetStoreProvider);
    try {
      final words = set.entries.map((entry) => entry.fr).join(', ');
      final url = await PracticeArtworkService.generateAndUpload(
        sync: sync,
        id: set.id,
        title: set.title,
        summary: set.summary,
        topic: set.topic,
        levelBand: set.levelBand,
        visualStyle:
            'Premium 3D artistic still life or miniature diorama; tactile objects, soft studio light, refined materials, and a calm editorial composition. No people or characters.',
        coverPrompt:
            'A premium 3D artistic still life for a French vocabulary story about ${set.topic}. '
            'Arrange a few tactile everyday objects that clearly suggest these five words: $words. '
            'Make the objects feel like one connected moment, not a collage. Soft studio lighting, '
            'subtle depth, elegant materials, warm cinematic color, no people or characters.',
      );
      if (url != null && url.isNotEmpty) {
        vocabularySets.updateCoverUrl(set.id, url);
      }
    } catch (error) {
      debugPrint('Vocabulary artwork generation failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create a set', style: DesignTokens.display(24)),
            const SizedBox(height: 6),
            Text(
              'Give us one topic. We will make five useful words for it.',
              style: DesignTokens.body(
                14,
              ).copyWith(color: DesignTokens.nightMuted),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_generating,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => unawaited(_generate()),
              decoration: InputDecoration(
                labelText: 'Topic',
                hintText: 'Morning routine, café, travel…',
                errorText: _error,
                filled: true,
                fillColor: DesignTokens.nightSurfaceRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: DesignTokens.nightHairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: DesignTokens.nightHairline),
                ),
              ),
            ),
            const SizedBox(height: 16),
            V3PrimaryButton(
              label: 'Make five words',
              icon: Icons.auto_awesome_rounded,
              onPressed: _generating ? null : _generate,
            ),
          ],
        ),
      ),
    );
  }
}
