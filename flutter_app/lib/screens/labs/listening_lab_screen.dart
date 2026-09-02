import 'dart:async';

import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../data/database/generated_story_store.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/elevenlabs_audio_service.dart';
import '../../services/audio_container_utils.dart';
import '../../services/gemini_live_audio_service.dart';
import '../../services/listening_audio_config.dart';
import '../../services/listening_audio_prefetch_cache.dart';
import '../../services/practice_artwork_service.dart';
import '../../services/recent_lesson_warmup_service.dart';
import '../../widgets/personalized_generation_loader.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../exam/exam_practice_screen.dart';
import '../lessons/listening_practice_screen.dart';
import '../lessons/story_reader_screen.dart';

// Fixed topic categories the learner can tap to steer generation, alongside
// "Surprise me" (no topic supplied) — kept short since these are also chip
// labels. Surprise mode does not inject onboarding interests.
const _storyTopicCategories = [
  'Travel',
  'Food',
  'Music',
  'Technology',
  'Environment',
];

IconData _topicIcon(String topic) {
  switch (topic.toLowerCase()) {
    case 'travel':
      return Icons.flight_rounded;
    case 'food':
      return Icons.restaurant_rounded;
    case 'music':
      return Icons.music_note_rounded;
    case 'technology':
      return Icons.computer_rounded;
    case 'environment':
      return Icons.eco_rounded;
    default:
      return Icons.circle_outlined;
  }
}

const _listeningFormatOptions = [
  _ListeningFormatOption(
    id: 'story',
    label: 'Story',
    detail: 'A short spoken French story',
    icon: CupertinoIcons.book,
  ),
  _ListeningFormatOption(
    id: 'narration',
    label: 'Narration',
    detail: 'Calm, clear story narration',
    icon: CupertinoIcons.waveform,
  ),
  _ListeningFormatOption(
    id: 'music',
    label: 'Music',
    detail: 'Simple lyrics for listening practice',
    icon: CupertinoIcons.music_note_2,
  ),
];

class _ListeningFormatOption {
  const _ListeningFormatOption({
    required this.id,
    required this.label,
    required this.detail,
    required this.icon,
  });

  final String id;
  final String label;
  final String detail;
  final IconData icon;
}

class _RenderedListeningAudio {
  const _RenderedListeningAudio({
    required this.clip,
    required this.storageMode,
    required this.extension,
    required this.contentType,
  });

  final ElevenLabsAudioClip clip;
  final String storageMode;
  final String extension;
  final String contentType;
}

/// The learner's personal library of AI-generated stories — the "Read a new
/// story" tile at top always generates a fresh one (Story + Quiz + Keywords +
/// Grammar, all AI-generated together) and opens it immediately; every story
/// generated this way is saved below so it can be reopened later, replacing
/// the old browsable list of hardcoded listening.json exercises.
class ListeningLabScreen extends ConsumerStatefulWidget {
  const ListeningLabScreen({
    super.key,
    this.topic,
    this.readingMode = false,
    this.autoStart = false,
    this.examName,
    this.examLevel,
    this.examMode = false,
  });

  final String? topic;
  final bool readingMode;
  final bool autoStart;
  final String? examName;
  final String? examLevel;
  final bool examMode;

  @override
  ConsumerState<ListeningLabScreen> createState() => _ListeningLabScreenState();
}

class _ListeningLabScreenState extends ConsumerState<ListeningLabScreen> {
  bool _generatingStory = false;
  List<GeneratedStory>? _stories;
  final Set<String> _artworkRepairInFlight = <String>{};
  // null = "Surprise me" for the topic, not the audio format.
  String? _selectedTopic;
  String _selectedFormat = 'story';

  @override
  void initState() {
    super.initState();
    _loadStories();
    unawaited(_refreshStories());
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_generateStory());
      });
    }
  }

  void _loadStories() {
    if (!mounted) return;
    if (widget.examMode) return;
    final store = ref.read(generatedStoryStoreProvider);
    final stories = store.list(
      practiceMode: widget.readingMode ? 'reading' : 'listening',
    );
    setState(() => _stories = stories);
    if (!widget.readingMode) {
      _prefetchRecentAudio(stories);
      _repairNewestMissingCover(stories);
    }
  }

  void _prefetchRecentAudio(List<GeneratedStory> stories) {
    // Kept as a small compatibility wrapper for existing callers. The shared
    // warm-up also covers older saved lessons, not only the latest three.
    RecentLessonWarmupService.shared.warm(
      stories: stories,
      sync: ref.read(syncServiceProvider),
    );
  }

  void _repairNewestMissingCover(List<GeneratedStory> stories) {
    GeneratedStory? candidate;
    for (final story in stories) {
      if (story.coverUrl?.trim().isEmpty != false) {
        candidate = story;
        break;
      }
    }
    if (candidate == null || !_artworkRepairInFlight.add(candidate.id)) return;
    unawaited(
      _generateCover(candidate, null).whenComplete(() {
        _artworkRepairInFlight.remove(candidate!.id);
      }),
    );
  }

  Future<void> _refreshStories() async {
    if (widget.examMode) return;
    try {
      await ref.read(syncServiceProvider).hydrateGeneratedStories();
    } catch (error, stackTrace) {
      debugPrint('Listening story hydration failed: $error\n$stackTrace');
    }
    if (mounted) _loadStories();
  }

  Future<void> _generateStory() async {
    if (_generatingStory) return;
    setState(() => _generatingStory = true);
    var generationStage = 'story';
    try {
      if (!widget.examMode && !widget.readingMode) {
        await _generateListeningStoryFast();
        return;
      }
      final profile = ref.read(learningStoreProvider).profile();
      final levelBand = _cefrLevelFor(profile.level).toUpperCase();
      final existingStories = ref.read(generatedStoryStoreProvider).list();
      final package = await LessonAgentService.shared.buildListeningStoryBook(
        topic: _topicFor(),
        levelBand: widget.examLevel ?? levelBand,
        examName: widget.examMode ? widget.examName : null,
        examLevel: widget.examMode ? widget.examLevel : null,
        audioFormat: widget.readingMode ? null : _selectedFormat,
        avoidTitles: existingStories.map((story) => story.title),
        avoidOpenings: existingStories.map(
          (story) => story.passage.segments.isEmpty
              ? ''
              : story.passage.segments.first.fr,
        ),
      );
      final story = GeneratedStory(
        id: newGeneratedStoryId(),
        passage: package.passage,
        quiz: package.quiz,
        keywords: package.keywords,
        createdAt: DateTime.now(),
        levelBand: package.levelBand,
        summary: package.summary,
        topic: package.topic,
        readTimeMinutes: package.readTimeMinutes,
        practiceMode: 'listening',
      );
      generationStage = 'audio';
      final renderedAudio = widget.examMode || widget.readingMode
          ? null
          : await _prepareAudioWithQuotaRecovery(story: story);
      var persistedStory = story;
      if (!widget.examMode && !widget.readingMode && renderedAudio != null) {
        final audioPath = await ref
            .read(syncServiceProvider)
            .uploadListeningAudio(
              storyId: story.id,
              mode: renderedAudio.storageMode,
              bytes: renderedAudio.clip.bytes,
              extension: renderedAudio.extension,
              contentType: renderedAudio.contentType,
            );
        if (audioPath == null || audioPath.isEmpty) {
          throw const ElevenLabsProviderException(
            'The rendered lesson audio could not be saved. Please try again.',
          );
        }
        persistedStory = story.copyWith(
          audioPath: audioPath,
          audioMode: renderedAudio.storageMode,
        );
      }
      final examAttempt = widget.examMode
          ? ref
                .read(examPracticeStoreProvider)
                .startStory(
                  examName: widget.examName ?? 'Exam practice',
                  levelBand: widget.examLevel ?? story.levelBand,
                  skill: 'listening',
                  story: persistedStory,
                )
          : null;
      final store = ref.read(generatedStoryStoreProvider);
      if (!widget.examMode) {
        store.insert(persistedStory);
      }
      if (!mounted) return;
      if (!widget.examMode) _loadStories();
      // Start artwork before entering the lesson. The open lesson watches
      // the shared story store and replaces its placeholder live.
      if (!widget.examMode) {
        unawaited(_generateCover(story, package.coverPrompt));
        if (!widget.readingMode) {
          unawaited(_generateListeningBackground(story, package.coverPrompt));
        }
      }
      final result = await AppRouter.push<Object?>(
        context,
        (_) => _lessonScreen(persistedStory, audioClip: renderedAudio?.clip),
        fullscreenDialog: widget.autoStart,
      );
      if (widget.examMode &&
          result is ExamPracticeResult &&
          examAttempt != null) {
        ref
            .read(examPracticeStoreProvider)
            .complete(
              id: examAttempt.id,
              score: result.correct,
              total: result.total,
            );
      }
      if (widget.autoStart && mounted) {
        Navigator.of(context).pop(result ?? false);
      }
    } catch (error, stackTrace) {
      debugPrint(
        'ListeningLabScreen: $generationStage generation failed: $error\n$stackTrace',
      );
      if (mounted) {
        if (widget.autoStart) {
          Navigator.of(context).pop(false);
          return;
        }
        final label = generationStage == 'audio'
            ? '$_selectedFormatLabel generation failed'
            : 'Story generation failed';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label: $error')));
      }
    } finally {
      if (mounted) setState(() => _generatingStory = false);
    }
  }

  Future<void> _generateListeningStoryFast() async {
    final profile = ref.read(learningStoreProvider).profile();
    final levelBand = _cefrLevelFor(profile.level).toUpperCase();
    final store = ref.read(generatedStoryStoreProvider);
    final existingStories = store.list(practiceMode: 'listening');
    final draft = await LessonAgentService.shared.buildListeningStoryDraft(
      topic: _topicFor(),
      levelBand: levelBand,
      audioFormat: _selectedFormat,
      avoidTitles: existingStories.map((story) => story.title),
      avoidOpenings: existingStories.map(
        (story) => story.passage.segments.isEmpty
            ? ''
            : story.passage.segments.first.fr,
      ),
    );
    final story = GeneratedStory(
      id: newGeneratedStoryId(),
      passage: draft.passage,
      quiz: const [],
      keywords: const [],
      createdAt: DateTime.now(),
      levelBand: draft.levelBand,
      summary: draft.summary,
      topic: draft.topic,
      readTimeMinutes: draft.readTimeMinutes,
      practiceMode: 'listening',
    );

    // Persist the usable bilingual draft before any slower enrichment,
    // rendering, or artwork work begins. All three background tasks use this
    // stable id and independently update SQLite and Supabase.
    store.insert(story);
    final enrichment = _enrichListeningStory(story);
    final audio = _renderAndPersistAudio(story: story, format: _selectedFormat);
    unawaited(_generateCover(story, draft.coverPrompt));
    unawaited(_generateListeningBackground(story, draft.coverPrompt));

    if (!mounted) return;
    _loadStories();
    final result = await AppRouter.push<Object?>(
      context,
      (_) => _lessonScreen(story, audioFuture: audio, enrichment: enrichment),
      fullscreenDialog: widget.autoStart,
    );
    if (widget.autoStart && mounted) {
      Navigator.of(context).pop(result ?? false);
    }
  }

  Future<ReadingStoryEnrichment> _enrichListeningStory(
    GeneratedStory story,
  ) async {
    final store = ref.read(generatedStoryStoreProvider);
    final result = await LessonAgentService.shared
        .buildListeningStoryEnrichment(
          passage: story.passage,
          levelBand: story.levelBand,
        );
    store.updateEnrichment(
      story.copyWith(
        passage: result.passage,
        quiz: result.quiz,
        keywords: result.keywords,
      ),
    );
    if (mounted) _loadStories();
    return result;
  }

  Future<ElevenLabsAudioClip?> _renderAndPersistAudio({
    required GeneratedStory story,
    required String format,
  }) async {
    final sync = ref.read(syncServiceProvider);
    final store = ref.read(generatedStoryStoreProvider);
    final rendered = await _prepareAudioWithQuotaRecovery(
      story: story,
      format: format,
    );
    final audioPath = await sync.uploadListeningAudio(
      storyId: story.id,
      mode: rendered.storageMode,
      bytes: rendered.clip.bytes,
      extension: rendered.extension,
      contentType: rendered.contentType,
    );
    if (audioPath == null || audioPath.isEmpty) {
      throw const ElevenLabsProviderException(
        'The rendered lesson audio could not be saved. Please try again.',
      );
    }
    store.updateAudio(
      storyId: story.id,
      audioPath: audioPath,
      audioMode: rendered.storageMode,
    );
    return rendered.clip;
  }

  Future<void> _showFormatPicker() async {
    final selected = await _showChoiceSheet(
      title: 'Choose audio format',
      selected: _selectedFormat,
      options: [
        for (final option in _listeningFormatOptions)
          _ListeningChoiceItem(
            value: option.id,
            label: option.label,
            detail: option.detail,
            icon: option.icon,
          ),
      ],
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedFormat = selected);
  }

  Future<void> _showTopicPicker() async {
    final selected = await _showChoiceSheet(
      title: 'Choose a topic',
      selected: _selectedTopic ?? 'surprise',
      options: [
        const _ListeningChoiceItem(
          value: 'surprise',
          label: 'Surprise me',
          detail: 'Let the lesson choose the premise',
          icon: CupertinoIcons.sparkles,
        ),
        for (final topic in _storyTopicCategories)
          _ListeningChoiceItem(
            value: topic.toLowerCase(),
            label: topic,
            detail: 'Steer the next story toward $topic',
            icon: _topicIcon(topic),
          ),
      ],
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedTopic = selected == 'surprise' ? null : selected);
  }

  Future<String?> _showChoiceSheet({
    required String title,
    required String selected,
    required List<_ListeningChoiceItem> options,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => _ListeningChoiceSheet(
        title: title,
        selected: selected,
        options: options,
      ),
    );
  }

  /// Renders the exact canonical French script through the selected provider.
  /// Gemini Live is the default Listening renderer; ElevenLabs remains an
  /// explicit one-line switch in listening_audio_config.dart for later testing.
  Future<_RenderedListeningAudio> _prepareAudioWithQuotaRecovery({
    required GeneratedStory story,
    String? format,
  }) async {
    final selectedMode = _normalizeListeningFormat(format ?? _selectedFormat);
    if (listeningAudioProvider == ListeningAudioProvider.geminiLive) {
      final script = CanonicalAudioScript.fromStory(
        story,
        format: selectedMode,
      );
      final pcm = await GeminiLiveAudioService.shared.synthesizeListeningLesson(
        text: script.narrationText,
        format: selectedMode,
        level: story.levelBand,
      );
      final wav = pcm16ToWav(
        pcm,
        sampleRate: GeminiLiveAudioService.outputSampleRateHz,
      );
      return _RenderedListeningAudio(
        clip: ElevenLabsAudioClip(
          mode: 'gemini_live_spoken',
          bytes: wav,
          container: 'wav',
        ),
        storageMode: 'gemini_live_spoken',
        extension: 'wav',
        contentType: 'audio/wav',
      );
    }
    final clip = await _prepareExperimentalAudio(
      story: story,
      format: selectedMode,
    );
    return _RenderedListeningAudio(
      clip: clip,
      storageMode: selectedMode,
      extension: 'mp3',
      contentType: 'audio/mpeg',
    );
  }

  Future<ElevenLabsAudioClip> _prepareExperimentalAudio({
    required GeneratedStory story,
    String? format,
  }) async {
    final selectedFormat = _normalizeListeningFormat(format ?? _selectedFormat);
    final script = CanonicalAudioScript.fromStory(
      story,
      format: selectedFormat,
    );
    if (script.lines.isEmpty) {
      throw const ElevenLabsProviderException(
        'This lesson has no French lines to render yet.',
      );
    }
    switch (selectedFormat) {
      case 'podcast':
        if (script.lines.length < 2) {
          throw const ElevenLabsProviderException(
            'Podcast lessons need at least two canonical lines.',
          );
        }
        return ElevenLabsAudioService.shared.synthesizePodcast(
          turns: script.podcastTurns,
        );
      case 'music':
        return ElevenLabsAudioService.shared.composeMusic(
          lyrics: script.lyricLines,
          style:
              'warm acoustic French pop, clear solo vocals, gentle drums, '
              'memorable chorus, conversational verses, 86 BPM, no spoken delivery, '
              'no English lyrics, no explicit content',
          musicLengthMs: 45_000,
        );
      case 'educational':
        return ElevenLabsAudioService.shared.synthesizeNarration(
          text: script.narrationText,
          mode: 'educational',
        );
      case 'narration':
      default:
        return ElevenLabsAudioService.shared.synthesizeNarration(
          text: script.narrationText,
          mode: 'story',
        );
    }
  }

  String _normalizeListeningFormat(String format) =>
      format == 'surprise' ? 'story' : format;

  Future<void> _generateCover(GeneratedStory story, String? coverPrompt) async {
    final sync = ref.read(syncServiceProvider);
    final store = ref.read(generatedStoryStoreProvider);
    try {
      final url = await PracticeArtworkService.generateAndUpload(
        sync: sync,
        id: story.id,
        title: story.title,
        summary: story.summary,
        topic: story.topic,
        levelBand: story.levelBand,
        coverPrompt: coverPrompt,
      );
      if (url == null) return;
      store.updateCoverUrl(story.id, url);
      if (mounted) _loadStories();
    } catch (error, stackTrace) {
      debugPrint(
        'ListeningLabScreen: cover generation failed: $error\n$stackTrace',
      );
    }
  }

  Future<void> _generateListeningBackground(
    GeneratedStory story,
    String? coverPrompt,
  ) async {
    final sync = ref.read(syncServiceProvider);
    final store = ref.read(generatedStoryStoreProvider);
    try {
      final url =
          await PracticeArtworkService.generateListeningBackgroundAndUpload(
            sync: sync,
            id: story.id,
            title: story.title,
            summary: story.summary,
            topic: story.topic,
            levelBand: story.levelBand,
            coverPrompt: coverPrompt,
          );
      if (url != null && url.isNotEmpty) {
        store.updateMusicBackgroundUrl(story.id, url);
      }
    } catch (error, stackTrace) {
      debugPrint(
        'ListeningLabScreen: music background generation failed: $error\n$stackTrace',
      );
    }
  }

  /// If the learner tapped a topic chip, use that directly. Otherwise return
  /// null so the model can choose a natural premise at the learner's level.
  String? _topicFor() {
    if (widget.topic != null && widget.topic!.trim().isNotEmpty) {
      return 'a short everyday story connected to ${widget.topic}';
    }
    if (_selectedTopic != null) {
      return 'something related to ${_selectedTopic!.toLowerCase()} that could happen in daily life';
    }
    // Null is intentional: Surprise me must not inherit onboarding interests
    // or a fixed fallback topic. The model chooses a new premise instead.
    return null;
  }

  String _cefrLevelFor(String level) {
    final normalized = level.toLowerCase();
    return const {'a1', 'a2', 'b1', 'b2'}.contains(normalized)
        ? normalized
        : 'a2';
  }

  Widget _lessonScreen(
    GeneratedStory story, {
    ElevenLabsAudioClip? audioClip,
    Future<ElevenLabsAudioClip?>? audioFuture,
    Future<ReadingStoryEnrichment>? enrichment,
  }) {
    if (widget.examMode) {
      return ExamPracticeScreen(
        story: story,
        examName: widget.examName ?? 'Exam practice',
        levelBand: widget.examLevel ?? story.levelBand,
        skill: 'listening',
      );
    }

    return widget.readingMode
        ? StoryReaderScreen(story: story, showFinishButton: widget.autoStart)
        : ListeningPracticeScreen(
            story: story,
            audioClip: audioClip,
            audioFuture:
                audioFuture ??
                ListeningAudioPrefetchCache.shared.peek(story.id),
            enrichment: enrichment,
            showFinishButton: widget.autoStart,
          );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.autoStart) {
      return _DirectCourseLoading(
        title: widget.readingMode ? 'Reading' : 'Listening',
        message: widget.readingMode
            ? 'Building your course story…'
            : 'Building your course listening…',
      );
    }
    final stories = _stories ?? const [];
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      appBar: AppBar(
        title: Text(
          widget.readingMode ? 'Reading' : 'Listening',
          style: DesignTokens.display(
            30,
          ).copyWith(color: DesignTokens.nightText),
        ),
        backgroundColor: DesignTokens.nightCanvas,
        foregroundColor: DesignTokens.nightText,
        toolbarHeight: 78,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        bottom: false,
        child: WebConstrainedView(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 32),
            children: [
              if (_generatingStory)
                PersonalizedGenerationLoader(
                  content: widget.readingMode
                      ? 'reading story'
                      : 'listening lesson',
                  detail: widget.readingMode
                      ? 'Shaping a short story around your level and interests.'
                      : 'Writing the lesson; audio, artwork, and checks continue in the background.',
                  icon: CupertinoIcons.headphones,
                )
              else
                _GenerateStoryTile(
                  generating: false,
                  selectedTopic: _selectedTopic,
                  selectedFormat: _selectedFormatLabel,
                  listening: !widget.readingMode,
                  onTap: _generateStory,
                ),
              const SizedBox(height: 10),
              if (!widget.readingMode) ...[
                Row(
                  children: [
                    Expanded(
                      child: _ListeningSelectionPill(
                        label: 'Audio format',
                        value: _selectedFormatLabel,
                        onTap: _showFormatPicker,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ListeningSelectionPill(
                        label: 'Topic',
                        value: _selectedTopicLabel,
                        onTap: _showTopicPicker,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (widget.readingMode) ...[
                _TopicChipRow(
                  selected: _selectedTopic,
                  onSelect: (topic) => setState(() => _selectedTopic = topic),
                ),
                const SizedBox(height: 22),
              ],
              if (stories.isNotEmpty) ...[
                _ListeningSectionLabel(
                  widget.readingMode
                      ? 'CONTINUE READING'
                      : 'CONTINUE LISTENING',
                ),
                const SizedBox(height: 9),
                _ContinueStoryCard(
                  story: stories.first,
                  listening: !widget.readingMode,
                  onTap: () => AppRouter.push(
                    context,
                    (_) => _lessonScreen(stories.first),
                  ),
                ),
                const SizedBox(height: 24),
                _ListeningSectionLabel(
                  widget.readingMode
                      ? 'PREVIOUS STORIES'
                      : 'PREVIOUS LISTENING',
                ),
                const SizedBox(height: 9),
                for (final story in stories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StoryBookCard(
                      story: story,
                      onTap: () =>
                          AppRouter.push(context, (_) => _lessonScreen(story)),
                    ),
                  ),
              ] else
                _EmptyLibraryNote(),
            ],
          ),
        ),
      ),
    );
  }

  String get _selectedFormatLabel => _listeningFormatOptions
      .firstWhere(
        (option) => option.id == _selectedFormat,
        orElse: () => _listeningFormatOptions.first,
      )
      .label;

  String get _selectedTopicLabel {
    if (_selectedTopic == null) return 'Surprise me';
    return _storyTopicCategories.firstWhere(
      (topic) => topic.toLowerCase() == _selectedTopic,
      orElse: () => _selectedTopic!,
    );
  }
}

class _ListeningSectionLabel extends StatelessWidget {
  const _ListeningSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: DesignTokens.label(
        11,
      ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 0.8),
    );
  }
}

class _DirectCourseLoading extends StatelessWidget {
  const _DirectCourseLoading({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      appBar: AppBar(
        title: Text(
          title,
          style: DesignTokens.display(
            20,
          ).copyWith(color: DesignTokens.nightText),
        ),
        backgroundColor: DesignTokens.nightCanvas,
        foregroundColor: DesignTokens.nightText,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: PersonalizedGenerationLoader(
            content: title.toLowerCase() == 'reading'
                ? 'reading story'
                : 'listening lesson',
            detail: message,
            icon: CupertinoIcons.book_fill,
          ),
        ),
      ),
    );
  }
}

class _GenerateStoryTile extends StatelessWidget {
  const _GenerateStoryTile({
    required this.generating,
    required this.onTap,
    this.selectedTopic,
    required this.selectedFormat,
    required this.listening,
  });

  final bool generating;
  final VoidCallback onTap;
  final String? selectedTopic;
  final String selectedFormat;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      onTap: generating ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: DesignTokens.nightAccentSoft,
                borderRadius: BorderRadius.circular(15),
              ),
              child: generating
                  ? Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                          DesignTokens.nightAccent,
                        ),
                      ),
                    )
                  : Icon(
                      CupertinoIcons.headphones,
                      color: DesignTokens.nightAccent,
                      size: 25,
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listening
                        ? 'Create a listening lesson'
                        : 'Create a reading story',
                    style: DesignTokens.body(
                      16,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.nightText),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    listening
                        ? '$selectedFormat at your level'
                        : 'A fresh story shaped to your course level',
                    style: DesignTokens.body(
                      12.5,
                    ).copyWith(color: DesignTokens.nightMuted),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              color: DesignTokens.nightAccent,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ListeningSelectionPill extends StatelessWidget {
  const _ListeningSelectionPill({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $value',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: DesignTokens.nightSurface,
            borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
            border: Border.all(color: DesignTokens.nightHairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.label(
                        9,
                      ).copyWith(color: DesignTokens.nightMuted),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.body(
                        12,
                        weight: FontWeight.w700,
                      ).copyWith(color: DesignTokens.nightText),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_down,
                size: 15,
                color: DesignTokens.nightAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListeningChoiceItem {
  const _ListeningChoiceItem({
    required this.value,
    required this.label,
    required this.detail,
    required this.icon,
  });

  final String value;
  final String label;
  final String detail;
  final IconData icon;
}

class _ListeningChoiceSheet extends StatelessWidget {
  const _ListeningChoiceSheet({
    required this.title,
    required this.selected,
    required this.options,
  });

  final String title;
  final String selected;
  final List<_ListeningChoiceItem> options;

  @override
  Widget build(BuildContext context) {
    final accent = DesignTokens.primaryReadable;

    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 620),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: DesignTokens.nightHairline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: DesignTokens.display(
                22,
              ).copyWith(color: DesignTokens.nightText),
            ),
            const SizedBox(height: 12),
            for (final option in options)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(
                  option.icon,
                  color: option.value == selected
                      ? accent
                      : DesignTokens.nightMuted,
                ),
                title: Text(
                  option.label,
                  style: DesignTokens.body(15, weight: FontWeight.w700)
                      .copyWith(
                        color: option.value == selected
                            ? accent
                            : DesignTokens.nightText,
                      ),
                ),
                subtitle: Text(
                  option.detail,
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.nightMuted),
                ),
                trailing: option.value == selected
                    ? Icon(CupertinoIcons.checkmark, color: accent)
                    : null,
                onTap: () => Navigator.pop(context, option.value),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Surprise me" (random pick, the default) plus the fixed topic categories —
/// tapping one steers the next generation toward it without making every
/// sentence literally about that word; tapping it again (or "Surprise me")
/// clears the pick back to fully random.
class _TopicChipRow extends StatelessWidget {
  const _TopicChipRow({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final options = <String?>[null, ..._storyTopicCategories];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final isSelected = option == selected;
          return GestureDetector(
            onTap: () => onSelect(isSelected ? null : option),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? DesignTokens.nightAccentSoft
                    : DesignTokens.nightSurface,
                border: Border.all(
                  color: isSelected
                      ? DesignTokens.nightAccent
                      : DesignTokens.nightHairline,
                ),
                borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
              ),
              alignment: Alignment.center,
              child: Text(
                option ?? 'Surprise me',
                style: DesignTokens.body(12.5, weight: FontWeight.w600)
                    .copyWith(
                      color: isSelected
                          ? DesignTokens.nightAccent
                          : DesignTokens.nightMuted,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ContinueStoryCard extends StatelessWidget {
  const _ContinueStoryCard({
    required this.story,
    required this.onTap,
    required this.listening,
  });

  final GeneratedStory story;
  final VoidCallback onTap;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final darkMode = DesignTokens.isDark;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: _StoryCover(
                story: story,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.84),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listening ? 'CONTINUE LISTENING' : 'CONTINUE READING',
                    style: DesignTokens.label(11).copyWith(
                      color: DesignTokens.nightAccent,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    story.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.display(23).copyWith(
                      color: darkMode ? DesignTokens.nightText : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${story.levelBand} · ${story.passage.segments.length} scenes · ${story.readTimeMinutes} min',
                          style: DesignTokens.body(12).copyWith(
                            color: darkMode
                                ? DesignTokens.nightMuted
                                : Colors.white70,
                          ),
                        ),
                      ),
                      Icon(
                        CupertinoIcons.play_fill,
                        color: DesignTokens.nightAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        listening ? 'Listen' : 'Open book',
                        style: DesignTokens.body(
                          12,
                          weight: FontWeight.w700,
                        ).copyWith(color: DesignTokens.nightAccent),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryBookCard extends StatelessWidget {
  const _StoryBookCard({required this.story, required this.onTap});

  final GeneratedStory story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      onTap: onTap,
      child: Container(
        height: 92,
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            _StoryCover(story: story, width: 112, height: 92),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.body(
                        15,
                        weight: FontWeight.w700,
                      ).copyWith(color: DesignTokens.nightText),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${story.levelBand} · ${story.readTimeMinutes} min',
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(right: 14),
              child: Icon(
                CupertinoIcons.chevron_right,
                color: DesignTokens.nightAccent,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryCover extends StatelessWidget {
  const _StoryCover({
    required this.story,
    required this.width,
    required this.height,
  });

  final GeneratedStory story;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final url = story.coverUrl;
    Widget fallback() => Container(
      color: DesignTokens.nightSurfaceRaised,
      alignment: Alignment.center,
      child: Icon(
        CupertinoIcons.headphones,
        color: DesignTokens.nightAccent,
        size: 30,
      ),
    );
    return SizedBox(
      width: width,
      height: height,
      child: url != null && url.startsWith('asset:')
          ? Image.asset(
              url.substring('asset:'.length),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback(),
            )
          : url == null || url.isEmpty
          ? fallback()
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback(),
            ),
    );
  }
}

class _EmptyLibraryNote extends StatelessWidget {
  const _EmptyLibraryNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.headphones,
            color: DesignTokens.nightMuted,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            'No stories yet. Generate one above to build your library.',
            textAlign: TextAlign.center,
            style: DesignTokens.body(
              13,
            ).copyWith(color: DesignTokens.nightMuted),
          ),
        ],
      ),
    );
  }
}
