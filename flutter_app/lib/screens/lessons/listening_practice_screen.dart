import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter_sound/flutter_sound.dart' show PlaybackDisposition;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/elevenlabs_audio_playback_service.dart';
import '../../services/elevenlabs_audio_service.dart';
import '../../services/audio_container_utils.dart';
import '../../services/gemini_live_audio_service.dart';
import '../../services/listening_audio_config.dart';
import '../../services/practice_artwork_service.dart';
import '../../services/session_settings.dart';
import '../../services/session_recorder.dart';
import '../../widgets/bilingual_word_text.dart';
import '../../widgets/floating_notetaker.dart';
import '../../widgets/report_problem_button.dart';
import '../../widgets/story_cover_image.dart';
import 'story_reader_screen.dart';

enum _ListeningStage { firstListen, check, focus, dictation, shadow, recap }

enum _ListeningTab { transcript, quiz, keywords, grammar }

class ListeningPracticeScreen extends ConsumerStatefulWidget {
  const ListeningPracticeScreen({
    super.key,
    required this.story,
    this.audioClip,
    this.audioFuture,
    this.enrichment,
    this.showFinishButton = false,
  });

  final GeneratedStory story;
  final ElevenLabsAudioClip? audioClip;
  final Future<ElevenLabsAudioClip?>? audioFuture;
  final Future<ReadingStoryEnrichment>? enrichment;
  final bool showFinishButton;

  @override
  ConsumerState<ListeningPracticeScreen> createState() =>
      _ListeningPracticeScreenState();
}

class _ListeningPracticeScreenState
    extends ConsumerState<ListeningPracticeScreen> {
  final SessionSettings _settings = SessionSettings.shared;
  late final SessionRecorder _recorder;
  final TextEditingController _dictationController = TextEditingController();
  final Map<int, int> _quizAnswers = {};

  _ListeningStage _stage = _ListeningStage.firstListen;
  _ListeningTab _tab = _ListeningTab.transcript;
  int _currentSegment = 0;
  int _focusSegment = 0;
  int _questionIndex = 0;
  int? _selectedWordIndex;
  int? _selectedWordSegment;
  int? _lyricsSelectedWordIndex;
  int? _currentWord;
  int? _dictationSegment;
  bool _isPlaying = false;
  bool _audioLoading = false;
  bool _showTranscript = false;
  bool _showTranslation = false;
  bool _dictationCorrect = false;
  bool _dictationSubmitted = false;
  bool _isRecording = false;
  bool _shadowCorrect = false;
  String _shadowTranscript = '';
  String? _shadowFeedback;
  double _rate = 1.0;
  bool _finishedSession = false;
  bool _isMarkedLearned = false;
  double _textScale = 1;
  bool _highlightWords = true;
  bool _underlineWords = true;
  bool _darkMode = true;
  Timer? _coverRefreshTimer;
  StreamSubscription<PlaybackDisposition>? _playbackProgressSubscription;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  bool _hasStartedPlayback = false;
  late ElevenLabsAudioClip? _audioClip;
  final Map<int, ElevenLabsAudioClip> _lineAudioCache = {};

  late GeneratedStory _story;
  List<ReadingSegment> get _segments => _story.passage.segments;
  List<MultipleChoiceQuestion> get _questions => _story.quiz.take(2).toList();
  ReadingSegment get _focusLine =>
      _segments[_focusSegment.clamp(0, _segments.length - 1).toInt()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Listening';
    });
    _story = widget.story;
    _audioClip = widget.audioClip;
    _textScale = _settings.textScale;
    _rate = _settings.playbackRate;
    _showTranslation = _settings.translateSentences;
    _highlightWords = _settings.highlightWords;
    _underlineWords = _settings.underlineWords;
    _darkMode = _settings.darkMode;
    unawaited(
      _settings.load().then((_) {
        if (!mounted) return;
        setState(() {
          _textScale = _settings.textScale;
          _rate = _settings.playbackRate;
          _showTranslation = _settings.translateSentences;
          _highlightWords = _settings.highlightWords;
          _underlineWords = _settings.underlineWords;
          _darkMode = _settings.darkMode;
        });
      }),
    );
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'reading_listening',
      topic: _story.displayTitle,
    );
    _playbackProgressSubscription = ElevenLabsAudioPlaybackService
        .shared
        .progress
        .listen(_handlePlaybackProgress);
    _dictationSegment = _findDictationSegment();
    if (widget.enrichment != null) {
      unawaited(_adoptEnrichment(widget.enrichment!));
    }
    if (_audioClip == null) {
      if (widget.audioFuture != null) {
        _audioLoading = true;
        unawaited(_adoptAudio(widget.audioFuture!));
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_loadSavedStoryAudio());
        });
      }
    }
    final needsCover = _story.coverUrl == null || _story.coverUrl!.isEmpty;
    final needsListeningBackground =
        _story.musicBackgroundUrl == null ||
        _story.musicBackgroundUrl!.isEmpty ||
        _isLegacyListeningBackground(_story.musicBackgroundUrl);
    if (needsCover || needsListeningBackground) {
      // Artwork is generated independently so opening a lesson never waits.
      // Keep the already-open player in sync when private uploads finish in
      // the library screen behind this route.
      _coverRefreshTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _refreshArtworkFromStore(),
      );
      if (_isLegacyListeningBackground(_story.musicBackgroundUrl)) {
        unawaited(_regenerateListeningBackground());
      }
    }
  }

  @override
  void dispose() {
    _coverRefreshTimer?.cancel();
    unawaited(_playbackProgressSubscription?.cancel());
    _dictationController.dispose();
    unawaited(LessonSpeechService.shared.deactivate());
    unawaited(ElevenLabsAudioPlaybackService.shared.stop());
    _finishSession();
    super.dispose();
  }

  void _refreshArtworkFromStore() {
    if (!mounted) return;
    GeneratedStory? latest;
    for (final candidate
        in ref
            .read(generatedStoryStoreProvider)
            .list(practiceMode: 'listening')) {
      if (candidate.id == _story.id) {
        latest = candidate;
        break;
      }
    }
    if (latest == null) return;
    final hasCover = latest.coverUrl?.isNotEmpty == true;
    final hasMusicBackground = latest.musicBackgroundUrl?.isNotEmpty == true;
    if (latest.coverUrl != _story.coverUrl ||
        latest.musicBackgroundUrl != _story.musicBackgroundUrl) {
      setState(
        () => _story = _story.copyWith(
          coverUrl: latest!.coverUrl,
          musicBackgroundUrl: latest.musicBackgroundUrl,
          audioPath: latest.audioPath,
          audioMode: latest.audioMode,
        ),
      );
    }
    final needsListeningBackground =
        !hasMusicBackground ||
        _isLegacyListeningBackground(latest.musicBackgroundUrl);
    if (hasCover && !needsListeningBackground) _coverRefreshTimer?.cancel();
  }

  bool _isLegacyListeningBackground(String? url) =>
      url?.contains('-music.') == true;

  Future<void> _regenerateListeningBackground() async {
    try {
      final url =
          await PracticeArtworkService.generateListeningBackgroundAndUpload(
            sync: ref.read(syncServiceProvider),
            id: _story.id,
            title: _story.title,
            summary: _story.summary,
            topic: _story.topic,
            levelBand: _story.levelBand,
            coverPrompt: null,
          );
      if (url == null || !mounted) return;
      ref
          .read(generatedStoryStoreProvider)
          .updateMusicBackgroundUrl(_story.id, url);
    } catch (error, stackTrace) {
      debugPrint(
        'ListeningPracticeScreen: legacy backdrop regeneration failed: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<void> _adoptEnrichment(Future<ReadingStoryEnrichment> future) async {
    try {
      final result = await future;
      if (!mounted) return;
      setState(() {
        _story = _story.copyWith(
          passage: result.passage,
          quiz: result.quiz,
          keywords: result.keywords,
        );
        _dictationSegment = _findDictationSegment();
      });
    } catch (error, stackTrace) {
      debugPrint(
        'ListeningPracticeScreen: background enrichment failed: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<void> _adoptAudio(Future<ElevenLabsAudioClip?> future) async {
    try {
      final clip = await future;
      if (!mounted) return;
      if (clip != null) {
        setState(() {
          _audioClip = clip;
          _audioLoading = false;
        });
        return;
      }
      // A recent saved lesson may have missed the prefetch download. Give
      // the durable path one normal load attempt before showing an error.
      if (_story.audioPath?.trim().isNotEmpty == true) {
        await _loadSavedStoryAudio();
        return;
      }
      setState(() => _audioLoading = false);
      _showAudioError(
        const ElevenLabsProviderException(
          'Gemini did not return playable lesson audio.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _audioLoading = false;
        _isPlaying = false;
      });
      _showAudioError(error);
    }
  }

  void _handlePlaybackProgress(PlaybackDisposition disposition) {
    if (!mounted) return;
    final duration = disposition.duration;
    final position = disposition.position;
    final durationMs = duration.inMilliseconds;
    final positionMs = position.inMilliseconds.clamp(0, durationMs).toInt();
    final nextSegment = durationMs <= 0 || _segments.isEmpty
        ? _currentSegment
        : ((positionMs / durationMs) * _segments.length)
              .floor()
              .clamp(0, _segments.length - 1)
              .toInt();
    int? nextWord;
    var wordCursor = 0;
    if (durationMs > 0 && _segments.isNotEmpty) {
      final totalWords = _segments.fold<int>(
        0,
        (sum, segment) => sum + _plainWords(segment.fr).length,
      );
      if (totalWords > 0) {
        final globalWord = (positionMs / durationMs * totalWords)
            .floor()
            .clamp(0, totalWords - 1)
            .toInt();
        for (var index = 0; index < _segments.length; index++) {
          final count = _plainWords(_segments[index].fr).length;
          if (globalWord < wordCursor + count) {
            nextWord = globalWord - wordCursor;
            break;
          }
          wordCursor += count;
        }
      }
    }
    setState(() {
      _playbackDuration = duration;
      _playbackPosition = position;
      _currentSegment = nextSegment;
      _currentWord = nextWord;
      _isPlaying = ElevenLabsAudioPlaybackService.shared.isPlaying;
    });
  }

  void _selectListeningWord(int segmentIndex, int wordIndex) {
    final isSame =
        _selectedWordSegment == segmentIndex &&
        _lyricsSelectedWordIndex == wordIndex;
    setState(() {
      _selectedWordSegment = isSame ? null : segmentIndex;
      _lyricsSelectedWordIndex = isSame ? null : wordIndex;
    });
  }

  int? _findDictationSegment() {
    for (var index = 0; index < _segments.length; index++) {
      final line = _segments[index].fr.toLowerCase();
      if (_story.keywords.any((word) => line.contains(word.fr.toLowerCase()))) {
        return index;
      }
    }
    return _segments.isEmpty ? null : (_segments.length > 1 ? 1 : 0);
  }

  String _dictationTarget() {
    final index = _dictationSegment;
    if (index == null || _segments.isEmpty) return '';
    final line = _segments[index].fr;
    final keyword = _story.keywords.cast<VocabEntry?>().firstWhere(
      (word) =>
          word != null && line.toLowerCase().contains(word.fr.toLowerCase()),
      orElse: () => null,
    );
    if (keyword != null) return keyword.fr;
    final words = _plainWords(line);
    if (words.isEmpty) return '';
    return words.length > 2 ? words[words.length ~/ 2] : words.first;
  }

  String _dictationPrompt() {
    final index = _dictationSegment;
    if (index == null || _segments.isEmpty) return '';
    final target = _dictationTarget();
    final line = _segments[index].fr;
    final start = line.toLowerCase().indexOf(target.toLowerCase());
    if (target.isEmpty || start < 0) return line;
    return '${line.substring(0, start)}_____'
        '${line.substring(start + target.length)}';
  }

  List<String> _plainWords(String text) => text
      .replaceAll(RegExp(r"[^A-Za-zÀ-ÿ0-9'’-]+"), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.trim().isNotEmpty)
      .toList();

  String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.,!?;:«»"()]'), '')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _playStory({int fromIndex = 0}) async {
    if (_segments.isEmpty || _audioLoading) return;
    if (fromIndex > 0) {
      await _playLine(fromIndex);
      return;
    }
    _audioLoading = true;
    if (mounted) setState(() {});
    try {
      await LessonSpeechService.shared.deactivate();
      await ElevenLabsAudioPlaybackService.shared.stop();
      if (!mounted) return;
      setState(() {
        _isPlaying = true;
        _hasStartedPlayback = true;
        _playbackPosition = Duration.zero;
        _playbackDuration = Duration.zero;
        _currentSegment = fromIndex;
      });
      final clip = _audioClip;
      if (clip == null) {
        throw const ElevenLabsProviderException(
          'This lesson audio is not ready. Try rendering it again.',
        );
      }
      await ElevenLabsAudioPlaybackService.shared.play(
        clip.bytes,
        container: clip.container,
        speed: _rate,
        onFinished: () {
          if (!mounted) return;
          setState(() {
            _isPlaying = false;
            _audioLoading = false;
            _playbackPosition = _playbackDuration;
            _currentSegment = _segments.isEmpty ? 0 : _segments.length - 1;
          });
        },
      );
      if (mounted) setState(() => _audioLoading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _audioLoading = false;
        });
        _showAudioError(error);
      }
    } finally {
      if (mounted && _audioLoading) setState(() => _audioLoading = false);
    }
  }

  Future<void> _playLine(int index) async {
    if (index < 0 || index >= _segments.length || _audioLoading) return;
    _audioLoading = true;
    if (mounted) setState(() {});
    try {
      await LessonSpeechService.shared.deactivate();
      await ElevenLabsAudioPlaybackService.shared.stop();
      if (!mounted) return;
      setState(() {
        _isPlaying = true;
        _hasStartedPlayback = true;
        _currentSegment = index;
      });
      final clip = _lineAudioCache[index] ??= await _synthesizeLineAudio(
        _segments[index].fr,
      );
      await ElevenLabsAudioPlaybackService.shared.play(
        clip.bytes,
        container: clip.container,
        speed: _rate,
        onFinished: () {
          if (mounted) {
            setState(() {
              _isPlaying = false;
              _audioLoading = false;
            });
          }
        },
      );
      if (mounted) setState(() => _audioLoading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _audioLoading = false;
        });
        _showAudioError(error);
      }
    } finally {
      if (mounted && _audioLoading) setState(() => _audioLoading = false);
    }
  }

  Future<void> _togglePlayback() async {
    if (_audioLoading) return;
    if (_isPlaying) {
      await ElevenLabsAudioPlaybackService.shared.pause();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }
    if (_hasStartedPlayback &&
        ElevenLabsAudioPlaybackService.shared.canResume) {
      await ElevenLabsAudioPlaybackService.shared.resume();
      if (mounted) setState(() => _isPlaying = true);
      return;
    }
    await _playStory(
      fromIndex: _stage == _ListeningStage.firstListen ? 0 : _currentSegment,
    );
  }

  Future<void> _loadSavedStoryAudio() async {
    if (!mounted || _audioClip != null) return;
    setState(() => _audioLoading = true);
    try {
      final storedPath = _story.audioPath;
      if (storedPath != null && storedPath.trim().isNotEmpty) {
        final bytes = await ref
            .read(syncServiceProvider)
            .downloadListeningAudio(storedPath);
        if (bytes == null || bytes.isEmpty) {
          throw const ElevenLabsProviderException(
            'The saved lesson audio could not be downloaded.',
          );
        }
        if (!mounted) return;
        setState(() {
          _audioClip = ElevenLabsAudioClip(
            mode: _story.audioMode ?? 'narration',
            bytes: bytes,
            container: _isWavAudioPath(storedPath) ? 'wav' : 'mp3',
          );
          _audioLoading = false;
        });
        return;
      }

      // Compatibility path for lessons made before durable audio storage was
      // added. New lessons never use this branch after reopening.
      final script = CanonicalAudioScript.fromStory(
        _story,
        format: _story.audioMode ?? 'narration',
      );
      final format = _story.audioMode ?? 'narration';
      final clip = await _synthesizeSavedAudioWithQuotaRecovery(
        script: script,
        format: format,
      );
      if (!mounted) return;
      setState(() {
        _audioClip = clip;
        _audioLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _audioLoading = false);
      _showAudioError(error);
    }
  }

  bool _isWavAudioPath(String path) =>
      path.toLowerCase().endsWith('.wav') ||
      _story.audioMode == 'gemini_live_spoken';

  Future<ElevenLabsAudioClip> _synthesizeLineAudio(String text) async {
    if (listeningAudioProvider == ListeningAudioProvider.geminiLive) {
      return _synthesizeGeminiLiveSpokenClip(text: text, format: 'narration');
    }
    try {
      return await ElevenLabsAudioService.shared.synthesizeNarration(
        text: text,
        mode: 'narration',
      );
    } on ElevenLabsProviderException catch (error) {
      if (!error.isQuotaExceeded) rethrow;
      return _synthesizeGeminiLiveSpokenClip(text: text, format: 'narration');
    }
  }

  Future<ElevenLabsAudioClip> _synthesizeSavedAudioWithQuotaRecovery({
    required CanonicalAudioScript script,
    required String format,
  }) async {
    if (format == 'gemini_live_spoken') {
      return _synthesizeGeminiLiveSpokenClip(
        text: script.narrationText,
        format: 'narration',
      );
    }
    if (listeningAudioProvider == ListeningAudioProvider.geminiLive) {
      return _synthesizeGeminiLiveSpokenClip(
        text: script.narrationText,
        format: format,
      );
    }
    try {
      return switch (format) {
        'music' => await ElevenLabsAudioService.shared.composeMusic(
          lyrics: script.lyricLines,
          style: 'warm acoustic French pop, clear solo vocals, 86 BPM',
          musicLengthMs: 45_000,
        ),
        'podcast' => await ElevenLabsAudioService.shared.synthesizePodcast(
          turns: script.podcastTurns,
        ),
        'educational' =>
          await ElevenLabsAudioService.shared.synthesizeNarration(
            text: script.narrationText,
            mode: 'educational',
          ),
        _ => await ElevenLabsAudioService.shared.synthesizeNarration(
          text: script.narrationText,
          mode: 'story',
        ),
      };
    } on ElevenLabsProviderException catch (error) {
      if (!error.isQuotaExceeded) rethrow;
      return _synthesizeGeminiLiveSpokenClip(
        text: script.narrationText,
        format: format,
      );
    }
  }

  Future<ElevenLabsAudioClip> _synthesizeGeminiLiveSpokenClip({
    required String text,
    required String format,
  }) async {
    final pcm = await GeminiLiveAudioService.shared.synthesizeListeningLesson(
      text: text,
      format: format,
      level: _story.levelBand,
    );
    return ElevenLabsAudioClip(
      mode: 'gemini_live_spoken',
      bytes: pcm16ToWav(
        pcm,
        sampleRate: GeminiLiveAudioService.outputSampleRateHz,
      ),
      container: 'wav',
    );
  }

  void _showAudioError(Object error) {
    final message = error is ElevenLabsProviderException
        ? error.message
        : 'The verified lesson audio could not be prepared. Please try again.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectListeningTab(int index) {
    final tab = _ListeningTab.values[index.clamp(0, 3).toInt()];
    setState(() {
      _tab = tab;
      if (tab == _ListeningTab.transcript) {
        _showTranscript = true;
      } else {
        // A content tab owns the screen. Never leave lyrics/transcript behind
        // it, because that creates the exact mixed layout the player is meant
        // to avoid.
        _showTranscript = false;
        _showTranslation = false;
      }
      if (tab == _ListeningTab.quiz) _stage = _ListeningStage.check;
    });
  }

  void _openLyrics() {
    setState(() {
      _tab = _ListeningTab.transcript;
      _showTranscript = true;
    });
  }

  void _toggleTranslation() {
    setState(() {
      if (!_showTranscript) {
        _tab = _ListeningTab.transcript;
        _showTranscript = true;
        _showTranslation = true;
        return;
      }
      _showTranslation = !_showTranslation;
    });
  }

  void _closeLyrics() {
    setState(() {
      _showTranscript = false;
      _tab = _ListeningTab.transcript;
    });
  }

  void _cycleTextSize() {
    final next = _textScale < 0.98
        ? 1.0
        : _textScale < 1.15
        ? 1.25
        : 0.9;
    setState(() => _textScale = next);
    unawaited(_settings.setTextScale(next));
  }

  Future<void> _copyCurrentLine() async {
    final line = _segments.isEmpty
        ? _story.displayTitle
        : _segments[_currentSegment.clamp(0, _segments.length - 1).toInt()].fr;
    await Clipboard.setData(ClipboardData(text: line));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('French line copied.')));
    }
  }

  Future<void> _showMoreMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => _ListeningMoreSheet(
        isMarkedLearned: _isMarkedLearned,
        isLyricsVisible: _showTranscript,
        sessionType: 'Listening: ${_story.displayTitle}',
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'lyrics':
        _showTranscript ? _closeLyrics() : _openLyrics();
      case 'quiz':
        _selectListeningTab(_ListeningTab.quiz.index);
      case 'keywords':
        _selectListeningTab(_ListeningTab.keywords.index);
      case 'grammar':
        _selectListeningTab(_ListeningTab.grammar.index);
      case 'speed':
        _cycleRate();
      case 'learn':
        setState(() => _isMarkedLearned = true);
      case 'notes':
        ref.read(notetakerStateProvider).isExpanded = true;
      case 'settings':
        await _showSettings();
    }
  }

  Widget _tabBody() {
    return switch (_tab) {
      _ListeningTab.transcript =>
        _stage == _ListeningStage.firstListen
            ? const SizedBox.shrink()
            : _stageBody(),
      _ListeningTab.quiz => _checkView(),
      _ListeningTab.keywords => _keywordsView(),
      _ListeningTab.grammar => _grammarView(),
    };
  }

  Widget _keywordsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageEyebrow(label: 'Keywords', detail: 'Words from this story'),
        const SizedBox(height: 10),
        Text(
          'Keep these words close.',
          style: DesignTokens.display(28).copyWith(color: Colors.white),
        ),
        const SizedBox(height: 16),
        if (_story.keywords.isEmpty)
          _EmptyStage(
            eyebrow: 'Keywords',
            title: 'No keywords yet.',
            body:
                'The generated lesson did not include a saved vocabulary list.',
            buttonLabel: 'Back to story',
            onPressed: () {},
          )
        else
          for (final keyword in _story.keywords)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NightPanel(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        keyword.fr,
                        style: DesignTokens.display(
                          18,
                        ).copyWith(color: DesignTokens.nightText),
                      ),
                    ),
                    Text(
                      keyword.en,
                      style: DesignTokens.body(
                        14,
                      ).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _grammarView() {
    final notes = _segments
        .where((segment) => segment.grammarNote.trim().isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageEyebrow(label: 'Grammar', detail: 'Notes from the story'),
        const SizedBox(height: 10),
        Text(
          'Notice how the French works.',
          style: DesignTokens.display(28).copyWith(color: Colors.white),
        ),
        const SizedBox(height: 16),
        if (notes.isEmpty)
          _NightPanel(
            child: Text(
              'Grammar notes are not available for this lesson yet.',
              style: DesignTokens.body(
                14,
              ).copyWith(color: DesignTokens.nightMuted),
            ),
          )
        else
          for (final segment in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NightPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      segment.fr,
                      style: DesignTokens.body(
                        15,
                        weight: FontWeight.w700,
                      ).copyWith(color: DesignTokens.nightText),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      segment.grammarNote,
                      style: DesignTokens.body(
                        13,
                      ).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  void _cycleRate() {
    final rates = SessionSettings.playbackRates;
    final currentIndex = rates.indexWhere(
      (value) => (value - _rate).abs() < 0.001,
    );
    final next =
        rates[(currentIndex < 0 ? 0 : currentIndex + 1) % rates.length];
    setState(() => _rate = next);
    unawaited(_settings.setPlaybackRate(next));
    unawaited(ElevenLabsAudioPlaybackService.shared.setSpeed(next));
  }

  void _selectQuizAnswer(int answerIndex) {
    setState(() => _quizAnswers[_questionIndex] = answerIndex);
  }

  void _advanceFromCheck() {
    if (_questions.isEmpty || _questionIndex >= _questions.length - 1) {
      setState(() {
        _tab = _ListeningTab.transcript;
        _stage = _ListeningStage.focus;
      });
      return;
    }
    setState(() => _questionIndex += 1);
  }

  Future<void> _moveFocus(int delta) async {
    if (_segments.isEmpty) return;
    final next = (_focusSegment + delta).clamp(0, _segments.length - 1).toInt();
    if (next == _focusSegment) return;

    // Moving between lines must also stop the previous reply. Otherwise a
    // delayed audio callback can make the newly selected line look finished
    // while the old line is still audible.
    await LessonSpeechService.shared.deactivate();
    await ElevenLabsAudioPlaybackService.shared.stop();
    if (!mounted) return;
    setState(() {
      _focusSegment = next;
      _selectedWordIndex = null;
      // Keep the learner's Hide/Translate choice for the whole Focus stage.
      // They can turn it off explicitly on any later line; advancing should
      // not make them repeat the same tap for every sentence.
      _isPlaying = false;
      _audioLoading = false;
    });
  }

  Future<void> _advanceFocus() async {
    if (_focusSegment >= _segments.length - 1) {
      await LessonSpeechService.shared.deactivate();
      await ElevenLabsAudioPlaybackService.shared.stop();
      if (mounted) {
        setState(() {
          _tab = _ListeningTab.transcript;
          _stage = _ListeningStage.dictation;
        });
      }
      return;
    }
    await _moveFocus(1);
  }

  void _submitDictation() {
    final target = _normalize(_dictationTarget());
    final answer = _normalize(_dictationController.text);
    if (answer.isEmpty) return;
    setState(() {
      _dictationSubmitted = true;
      _dictationCorrect = answer == target;
      _tab = _ListeningTab.transcript;
      _stage = _ListeningStage.shadow;
    });
    _recorder.logUser(_dictationController.text);
    _recorder.logTutor('${_dictationPrompt()} → ${_dictationTarget()}');
  }

  Future<void> _toggleShadow() async {
    final speech = LessonSpeechService.shared;
    if (_isRecording) {
      await speech.stopListening();
      return;
    }
    await speech.deactivate();
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _shadowTranscript = '';
      _shadowFeedback = null;
    });
    await speech.startListening(
      locale: 'fr-FR',
      onPartial: (_) {},
      onFinal: _handleShadowTranscript,
    );
    if (mounted && !speech.isListening) setState(() => _isRecording = false);
  }

  Future<void> _handleShadowTranscript(String transcript) async {
    if (!mounted) return;
    final trimmed = transcript.trim();
    setState(() {
      _isRecording = false;
      _shadowTranscript = trimmed;
    });
    if (trimmed.isEmpty) {
      setState(
        () => _shadowFeedback =
            'I could not hear a clear attempt. Try once more.',
      );
      return;
    }
    _recorder.logUser(trimmed);
    try {
      final judgment = await LessonAgentService.shared
          .judgePronunciationAttempt(
            targetWord: _focusLine.fr,
            studentSaid: trimmed,
          );
      if (!mounted) return;
      setState(() {
        _shadowCorrect = judgment.isCorrect;
        _shadowFeedback = judgment.isCorrect
            ? 'Good match. Your version is clear enough to keep moving.'
            : (judgment.description ??
                  'Listen once more, then repeat the whole line.');
      });
    } catch (_) {
      final match = _roughPhraseMatch(_focusLine.fr, trimmed);
      if (!mounted) return;
      setState(() {
        _shadowCorrect = match;
        _shadowFeedback = match
            ? 'Nice repeat. The key words came through clearly.'
            : 'I heard a different phrase. Replay the line and try again.';
      });
    }
  }

  bool _roughPhraseMatch(String target, String heard) {
    final targetWords = _plainWords(_normalize(target));
    final heardWords = _plainWords(_normalize(heard)).toSet();
    if (targetWords.isEmpty) return false;
    final matches = targetWords.where(heardWords.contains).length;
    return matches / targetWords.length >= 0.6;
  }

  void _finishSession() {
    if (_finishedSession) return;
    _finishedSession = true;
    final correct = _quizAnswers.entries
        .where(
          (entry) =>
              entry.key < _questions.length &&
              entry.value == _questions[entry.key].answerIndex,
        )
        .length;
    _recorder.finish(
      summary:
          'Listened to "${_story.displayTitle}" and caught $correct/${_questions.length} details.',
    );
  }

  void _finishAndPop() {
    _finishSession();
    Navigator.of(context).pop(widget.showFinishButton ? true : null);
  }

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => _ListeningSettingsSheet(settings: _settings),
    );
    if (!mounted) return;
    setState(() {
      _textScale = _settings.textScale;
      _rate = _settings.playbackRate;
      _showTranslation = _settings.translateSentences;
      _highlightWords = _settings.highlightWords;
      _underlineWords = _settings.underlineWords;
      _darkMode = _settings.darkMode;
    });
    unawaited(ElevenLabsAudioPlaybackService.shared.setSpeed(_rate));
  }

  @override
  Widget build(BuildContext context) {
    final showLyrics = _showTranscript;
    final contentTab = !showLyrics && _tab != _ListeningTab.transcript;
    return Scaffold(
      backgroundColor: _darkMode ? Colors.black : DesignTokens.canvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _ListeningImmersiveBackground(
            story: _story,
            dimmed: showLyrics || contentTab,
          ),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  left: 14,
                  right: 14,
                  child: _ListeningTopBar(
                    isMarkedLearned: _isMarkedLearned,
                    onBack: _finishAndPop,
                    onMarkLearned: () =>
                        setState(() => _isMarkedLearned = !_isMarkedLearned),
                    onSettings: _showSettings,
                    onMore: _showMoreMenu,
                  ),
                ),
                if (showLyrics)
                  Positioned.fill(
                    top: 84,
                    bottom: 14,
                    child: _ListeningFullscreenTranscript(
                      segments: _segments,
                      currentSegment: _currentSegment,
                      currentWord: _currentWord,
                      selectedSegment: _selectedWordSegment,
                      selectedWord: _lyricsSelectedWordIndex,
                      keywords: _story.keywords,
                      highlightWords: _highlightWords,
                      underlineWords: _underlineWords,
                      showTranslation: _showTranslation,
                      textScale: _textScale,
                      isPlaying: _isPlaying,
                      isLoading: _audioLoading,
                      rate: _rate,
                      playbackPosition: _playbackPosition,
                      playbackDuration: _playbackDuration,
                      onTogglePlayback: _togglePlayback,
                      onReplay: () => _playStory(),
                      onCycleRate: _cycleRate,
                      onToggleLyrics: _closeLyrics,
                      onToggleTranslation: _toggleTranslation,
                      onCycleTextSize: _cycleTextSize,
                      onCopyLine: _copyCurrentLine,
                      onWordTap: _selectListeningWord,
                    ),
                  ),
                if (!showLyrics && contentTab)
                  Positioned(
                    top: 104,
                    left: 16,
                    right: 16,
                    bottom: 112,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 22),
                      child: _tabBody(),
                    ),
                  ),
                if (!showLyrics && contentTab)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: contentTab ? 82 : 244,
                    child: _ListeningStageIslandTabs(
                      current: _tab,
                      onTap: _selectListeningTab,
                    ),
                  ),
                if (!showLyrics)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: _ListeningPlayerDock(
                      story: _story,
                      audioClip: _audioClip,
                      segments: _segments,
                      currentSegment: _currentSegment,
                      compact: contentTab,
                      isLiked: ref
                          .read(storyFavoriteStoreProvider)
                          .isFavorite(_story.id),
                      isPlaying: _isPlaying,
                      isLoading: _audioLoading,
                      rate: _rate,
                      playbackPosition: _playbackPosition,
                      playbackDuration: _playbackDuration,
                      onTogglePlayback: _togglePlayback,
                      onReplay: () => _playStory(),
                      onCycleRate: _cycleRate,
                      onToggleLyrics: _openLyrics,
                      onToggleTranslation: _toggleTranslation,
                      onCycleTextSize: _cycleTextSize,
                      onCopyLine: _copyCurrentLine,
                      onToggleFavorite: () {
                        final favorites = ref.read(storyFavoriteStoreProvider);
                        final next = !favorites.isFavorite(_story.id);
                        favorites.setFavorite(_story.id, next);
                        setState(() {});
                      },
                    ),
                  ),
              ],
            ),
          ),
          FloatingNotetakerOverlay(state: ref.watch(notetakerStateProvider)),
        ],
      ),
    );
  }

  Widget _stageBody() {
    return switch (_stage) {
      _ListeningStage.firstListen => _firstListenView(),
      _ListeningStage.check => _checkView(),
      _ListeningStage.focus => _focusView(),
      _ListeningStage.dictation => _dictationView(),
      _ListeningStage.shadow => _shadowView(),
      _ListeningStage.recap => _recapView(),
    };
  }

  Widget _firstListenView() {
    return const SizedBox.shrink();
  }

  Widget _checkView() {
    if (_questions.isEmpty) {
      return _EmptyStage(
        eyebrow: '02 · Quick check',
        title: 'You are ready for the transcript.',
        body:
            'This story has no saved questions, so we will move to line-by-line listening.',
        buttonLabel: 'Open the lines',
        onPressed: () => setState(() {
          _tab = _ListeningTab.transcript;
          _stage = _ListeningStage.focus;
        }),
      );
    }
    final question = _questions[_questionIndex];
    final selected = _quizAnswers[_questionIndex];
    final answered = selected != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageEyebrow(
          label: '02 · Quick check',
          detail: 'No transcript yet',
        ),
        const SizedBox(height: 8),
        Text(
          'What stayed with you?',
          style: DesignTokens.display(
            28,
          ).copyWith(color: DesignTokens.nightText),
        ),
        const SizedBox(height: 16),
        _NightPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Question ${_questionIndex + 1} of ${_questions.length}',
                style: DesignTokens.label(
                  11,
                ).copyWith(color: DesignTokens.nightAccent),
              ),
              const SizedBox(height: 10),
              Text(
                question.q,
                style: DesignTokens.display(
                  19,
                ).copyWith(color: DesignTokens.nightText),
              ),
              if (question.qEn != null && question.qEn!.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  question.qEn!,
                  style: DesignTokens.body(
                    14,
                  ).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
              const SizedBox(height: 15),
              for (var index = 0; index < question.choices.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ChoiceButton(
                    label: question.choices[index],
                    secondaryLabel:
                        question.choicesEn != null &&
                            index < question.choicesEn!.length
                        ? question.choicesEn![index]
                        : null,
                    selected: selected == index,
                    correct: answered && index == question.answerIndex,
                    onTap: () => _selectQuizAnswer(index),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _NightPrimaryButton(
          label: _questionIndex == _questions.length - 1
              ? 'Open the focus lines'
              : 'Next question',
          icon: CupertinoIcons.arrow_right,
          onPressed: answered ? _advanceFromCheck : null,
        ),
      ],
    );
  }

  Widget _focusView() {
    final line = _focusLine;
    final words = _plainWords(line.fr);
    final selectedWord =
        _selectedWordIndex != null && _selectedWordIndex! < words.length
        ? words[_selectedWordIndex!]
        : null;
    final wordEntry = selectedWord == null
        ? null
        : _story.keywords.cast<VocabEntry?>().firstWhere(
            (entry) =>
                entry != null &&
                _plainWords(
                  _normalize(entry.fr),
                ).contains(_normalize(selectedWord)),
            orElse: () => null,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StageEyebrow(
          label: '03 · Tune your ear',
          detail: 'Line ${_focusSegment + 1} of ${_segments.length}',
        ),
        const SizedBox(height: 8),
        Text(
          'Hear it. See it. Replay it.',
          style: DesignTokens.display(
            28,
          ).copyWith(color: DesignTokens.nightText),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap a word for a quick meaning. Translation stays optional.',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 16),
        _NightPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LINE ${(_focusSegment + 1).toString().padLeft(2, '0')}',
                style: DesignTokens.label(
                  10,
                ).copyWith(color: DesignTokens.primarySoft),
              ),
              const SizedBox(height: 12),
              BilingualWordText(
                source: line.fr,
                translation: _showTranslation ? line.en : '',
                sourceStyle: DesignTokens.display(20 * _textScale).copyWith(
                  color: DesignTokens.nightText,
                  decoration: _underlineWords
                      ? TextDecoration.underline
                      : TextDecoration.none,
                  decorationColor: DesignTokens.nightAccent,
                ),
                translationStyle: DesignTokens.body(
                  14 * _textScale,
                ).copyWith(color: DesignTokens.nightMuted),
                keywords: _story.keywords,
                selectedSourceWord: _selectedWordIndex,
                onSourceWordTap: (index) => setState(
                  () => _selectedWordIndex = _selectedWordIndex == index
                      ? null
                      : index,
                ),
              ),
              const SizedBox(height: 18),
              _NightAudioIsland(
                isPlaying: _isPlaying,
                isLoading: _audioLoading,
                rate: _rate,
                onToggle: () => _playLine(_focusSegment),
                onReplay: () => _playLine(_focusSegment),
                onCycleRate: _cycleRate,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _showTranslation = !_showTranslation),
                  icon: const Icon(CupertinoIcons.globe, size: 17),
                  label: Text(
                    _showTranslation ? 'Hide translation' : 'Show translation',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: DesignTokens.nightAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _focusSegment == 0 ? null : () => _moveFocus(-1),
                icon: const Icon(CupertinoIcons.chevron_left, size: 17),
                label: const Text('Previous'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DesignTokens.nightText,
                  disabledForegroundColor: DesignTokens.nightMuted,
                  side: BorderSide(color: DesignTokens.nightHairline),
                  backgroundColor: DesignTokens.nightSurface,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusMedium,
                    ),
                  ),
                  textStyle: DesignTokens.body(13, weight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _focusSegment >= _segments.length - 1
                    ? null
                    : () => _moveFocus(1),
                icon: const Icon(CupertinoIcons.chevron_right, size: 17),
                label: const Text('Next'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DesignTokens.nightText,
                  disabledForegroundColor: DesignTokens.nightMuted,
                  side: BorderSide(color: DesignTokens.nightHairline),
                  backgroundColor: DesignTokens.nightSurface,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusMedium,
                    ),
                  ),
                  textStyle: DesignTokens.body(13, weight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        if (wordEntry != null) ...[
          const SizedBox(height: 12),
          _NightPanel(
            accent: DesignTokens.nightAccentSoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.textformat,
                  color: DesignTokens.nightAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wordEntry.fr,
                        style: DesignTokens.body(
                          15,
                          weight: FontWeight.w700,
                        ).copyWith(color: DesignTokens.nightText),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        wordEntry.en,
                        style: DesignTokens.body(
                          13,
                        ).copyWith(color: DesignTokens.nightMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _NightPrimaryButton(
          label: _focusSegment == _segments.length - 1
              ? 'Try a dictation line'
              : 'Next line',
          icon: CupertinoIcons.arrow_right,
          onPressed: _advanceFocus,
        ),
      ],
    );
  }

  Widget _dictationView() {
    final prompt = _dictationPrompt();
    final index = _dictationSegment;
    if (index == null || prompt.isEmpty) {
      return _EmptyStage(
        eyebrow: '04 · Active listening',
        title: 'Now say one line aloud.',
        body:
            'There is no clean cloze target in this story, so we will use shadowing instead.',
        buttonLabel: 'Start shadowing',
        onPressed: () => setState(() => _stage = _ListeningStage.shadow),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageEyebrow(
          label: '04 · Active listening',
          detail: 'Dictation',
        ),
        const SizedBox(height: 8),
        Text(
          'Can your ear fill the gap?',
          style: DesignTokens.display(
            28,
          ).copyWith(color: DesignTokens.nightText),
        ),
        const SizedBox(height: 8),
        Text(
          'Replay the line, then type the missing French word you hear.',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 16),
        _NightPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: 'Play dictation line',
                onPressed: _audioLoading ? null : () => _playLine(index),
                icon: _audioLoading
                    ? SizedBox(
                        width: 42,
                        height: 42,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            DesignTokens.nightAccent,
                          ),
                        ),
                      )
                    : Icon(
                        CupertinoIcons.play_circle_fill,
                        size: 42,
                        color: DesignTokens.nightAccent,
                      ),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
              const SizedBox(height: 14),
              Text(
                prompt,
                style: DesignTokens.display(
                  20,
                ).copyWith(color: DesignTokens.nightText),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _dictationController,
                enabled: !_dictationSubmitted,
                style: DesignTokens.body(
                  16,
                ).copyWith(color: DesignTokens.nightText),
                cursorColor: DesignTokens.nightAccent,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submitDictation(),
                decoration: InputDecoration(
                  labelText: 'Type the missing word',
                  labelStyle: TextStyle(color: DesignTokens.nightMuted),
                  hintText: 'écoute…',
                  hintStyle: TextStyle(color: DesignTokens.nightMuted),
                  filled: true,
                  fillColor: DesignTokens.nightSurfaceRaised,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: DesignTokens.nightHairline),
                    borderRadius: BorderRadius.all(
                      Radius.circular(DesignTokens.radiusMedium),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: DesignTokens.nightAccent),
                    borderRadius: BorderRadius.all(
                      Radius.circular(DesignTokens.radiusMedium),
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusMedium,
                    ),
                  ),
                ),
              ),
              if (_dictationSubmitted) ...[
                const SizedBox(height: 12),
                Text(
                  _dictationCorrect
                      ? 'Correct: ${_dictationTarget()}'
                      : 'The word was “${_dictationTarget()}”. Keep it for the next replay.',
                  style: DesignTokens.body(13, weight: FontWeight.w700)
                      .copyWith(
                        color: _dictationCorrect
                            ? DesignTokens.success
                            : DesignTokens.warning,
                      ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _NightPrimaryButton(
          label: 'Check the word',
          icon: CupertinoIcons.checkmark,
          onPressed:
              _dictationController.text.trim().isEmpty || _dictationSubmitted
              ? null
              : _submitDictation,
        ),
      ],
    );
  }

  Widget _shadowView() {
    final line = _focusLine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageEyebrow(
          label: '05 · Shadowing',
          detail: 'Optional voice check',
        ),
        const SizedBox(height: 8),
        Text(
          'Borrow the rhythm.',
          style: DesignTokens.display(
            28,
          ).copyWith(color: DesignTokens.nightText),
        ),
        const SizedBox(height: 8),
        Text(
          'Listen once, then repeat the whole line. We only judge the attempt, not perfection.',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 16),
        _NightPanel(
          accent: DesignTokens.nightAccentSoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.fr,
                style: DesignTokens.display(
                  20 * _textScale,
                ).copyWith(color: DesignTokens.nightText),
              ),
              const SizedBox(height: 7),
              Text(
                line.en,
                style: DesignTokens.body(
                  13 * _textScale,
                ).copyWith(color: DesignTokens.nightMuted),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Play target line',
                    onPressed: () => _playLine(_focusSegment),
                    icon: Icon(
                      CupertinoIcons.play_circle_fill,
                      size: 42,
                      color: DesignTokens.nightAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isRecording
                          ? 'Listening… tap stop when you finish.'
                          : 'Hear the line, then record your version.',
                      style: DesignTokens.body(12, weight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _toggleShadow,
                  icon: Icon(
                    _isRecording
                        ? CupertinoIcons.stop_fill
                        : CupertinoIcons.mic_fill,
                  ),
                  label: Text(
                    _isRecording ? 'Stop and check' : 'Record attempt',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DesignTokens.nightAccent,
                    side: BorderSide(
                      color: DesignTokens.nightAccent.withValues(alpha: 0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusMedium,
                      ),
                    ),
                  ),
                ),
              ),
              if (_shadowTranscript.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'I heard: “$_shadowTranscript”',
                  style: DesignTokens.body(12),
                ),
              ],
              if (_shadowFeedback != null) ...[
                const SizedBox(height: 10),
                Text(
                  _shadowFeedback!,
                  style: DesignTokens.body(13, weight: FontWeight.w700)
                      .copyWith(
                        color: _shadowCorrect
                            ? DesignTokens.success
                            : DesignTokens.warning,
                      ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _NightPrimaryButton(
          label: 'See my listening recap',
          icon: CupertinoIcons.arrow_right,
          onPressed: _shadowTranscript.isNotEmpty || _shadowFeedback != null
              ? () => setState(() => _stage = _ListeningStage.recap)
              : null,
        ),
      ],
    );
  }

  Widget _recapView() {
    final correct = _quizAnswers.entries
        .where(
          (entry) =>
              entry.key < _questions.length &&
              entry.value == _questions[entry.key].answerIndex,
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageEyebrow(label: 'Complete', detail: 'Listening recap'),
        const SizedBox(height: 8),
        Text(
          'Your ear did the work.',
          style: DesignTokens.display(
            28,
          ).copyWith(color: DesignTokens.nightText),
        ),
        const SizedBox(height: 8),
        Text(
          'Keep the phrases that were hard. They are the best next lesson.',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 16),
        _NightPanel(
          accent: DesignTokens.nightAccentSoft,
          child: Row(
            children: [
              Text(
                '$correct/${_questions.length}',
                style: DesignTokens.display(
                  30,
                ).copyWith(color: DesignTokens.nightAccent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'details caught\n${_dictationCorrect ? 'Dictation landed' : 'Dictation needs one more pass'}',
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.nightText),
                ),
              ),
              Icon(
                _shadowCorrect
                    ? CupertinoIcons.checkmark_seal_fill
                    : CupertinoIcons.headphones,
                color: _shadowCorrect
                    ? Colors.greenAccent
                    : DesignTokens.nightAccent,
                size: 30,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _NightPanel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(CupertinoIcons.lightbulb, color: DesignTokens.nightAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _shadowCorrect
                      ? 'Strong repeat. Next time, try the story once at normal speed before opening the transcript.'
                      : 'Replay the focus line tomorrow at 0.75×, then try it again at normal speed.',
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w600,
                  ).copyWith(color: DesignTokens.nightText),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _NightPrimaryButton(
          label: 'Finish listening',
          icon: CupertinoIcons.checkmark,
          onPressed: _finishAndPop,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StoryReaderScreen(story: _story),
              ),
            ),
            child: Text(
              'Open the full transcript',
              style: DesignTokens.body(
                13,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.nightAccent),
            ),
          ),
        ),
      ],
    );
  }
}

class _ListeningImmersiveBackground extends StatelessWidget {
  const _ListeningImmersiveBackground({
    required this.story,
    required this.dimmed,
  });

  final GeneratedStory story;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        StoryCoverImage(
          title: story.displayTitle,
          source: story.musicBackgroundUrl ?? story.coverUrl,
          fit: story.musicBackgroundUrl?.isNotEmpty == true
              ? BoxFit.cover
              : BoxFit.contain,
          fallbackIcon: CupertinoIcons.headphones,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.28),
                Colors.black.withValues(alpha: dimmed ? 0.24 : 0.06),
                Colors.black.withValues(alpha: dimmed ? 0.93 : 0.82),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
        if (dimmed)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.14),
                  Colors.black.withValues(alpha: 0.52),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ListeningTopBar extends StatelessWidget {
  const _ListeningTopBar({
    required this.isMarkedLearned,
    required this.onBack,
    required this.onMarkLearned,
    required this.onSettings,
    required this.onMore,
  });

  final bool isMarkedLearned;
  final VoidCallback onBack;
  final VoidCallback onMarkLearned;
  final VoidCallback onSettings;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ListeningRoundButton(
          icon: CupertinoIcons.chevron_left,
          tooltip: 'Back',
          onTap: onBack,
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onMarkLearned,
          icon: Icon(
            isMarkedLearned
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.checkmark_circle,
            size: 17,
          ),
          label: Text(isMarkedLearned ? 'Listened' : 'Mark as listened'),
          style: TextButton.styleFrom(
            foregroundColor: DesignTokens.nightAccent,
            backgroundColor: Colors.black.withValues(alpha: 0.28),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: Colors.white24),
            ),
            textStyle: DesignTokens.body(11, weight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        _ListeningRoundButton(
          icon: CupertinoIcons.slider_horizontal_3,
          tooltip: 'Listening settings',
          onTap: onSettings,
          accent: true,
        ),
        const SizedBox(width: 4),
        _ListeningRoundButton(
          icon: CupertinoIcons.ellipsis,
          tooltip: 'More listening options',
          onTap: onMore,
        ),
      ],
    );
  }
}

class _ListeningRoundButton extends StatelessWidget {
  const _ListeningRoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 22),
      color: accent ? DesignTokens.nightAccent : Colors.white,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.28),
        minimumSize: const Size(42, 42),
        side: const BorderSide(color: Colors.white24),
        shape: const CircleBorder(),
      ),
    );
  }
}

class _ListeningPlayerDock extends StatelessWidget {
  const _ListeningPlayerDock({
    required this.story,
    required this.audioClip,
    required this.segments,
    required this.currentSegment,
    required this.compact,
    required this.isLiked,
    required this.isPlaying,
    required this.isLoading,
    required this.rate,
    required this.playbackPosition,
    required this.playbackDuration,
    required this.onTogglePlayback,
    required this.onReplay,
    required this.onCycleRate,
    required this.onToggleLyrics,
    required this.onToggleTranslation,
    required this.onCycleTextSize,
    required this.onCopyLine,
    required this.onToggleFavorite,
  });

  final GeneratedStory story;
  final ElevenLabsAudioClip? audioClip;
  final List<ReadingSegment> segments;
  final int currentSegment;
  final bool compact;
  final bool isLiked;
  final bool isPlaying;
  final bool isLoading;
  final double rate;
  final Duration playbackPosition;
  final Duration playbackDuration;
  final VoidCallback onTogglePlayback;
  final VoidCallback onReplay;
  final VoidCallback onCycleRate;
  final VoidCallback onToggleLyrics;
  final VoidCallback onToggleTranslation;
  final VoidCallback onCycleTextSize;
  final VoidCallback onCopyLine;
  final VoidCallback onToggleFavorite;

  String get _formatLabel => switch (audioClip?.mode) {
    'podcast' => 'Podcast dialogue',
    'music' => 'Music lesson',
    'educational' => 'Educational',
    'story' => 'Story narration',
    'narration' => 'Story narration',
    'gemini_live_spoken' => 'Spoken lesson',
    _ => 'Narrated French',
  };

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _ListeningMiniPlayer(
        story: story,
        audioClip: audioClip,
        isPlaying: isPlaying,
        isLoading: isLoading,
        onTogglePlayback: onTogglePlayback,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.64),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: StoryCoverImage(
                        title: story.displayTitle,
                        source: story.coverUrl,
                        fallbackIcon: CupertinoIcons.person_fill,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          story.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesignTokens.body(
                            15,
                            weight: FontWeight.w800,
                          ).copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesignTokens.body(
                            11,
                          ).copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: isLiked ? 'Remove favorite' : 'Favorite',
                    onPressed: onToggleFavorite,
                    icon: Icon(
                      isLiked
                          ? CupertinoIcons.heart_fill
                          : CupertinoIcons.heart,
                      color: isLiked ? DesignTokens.nightAccent : Colors.white,
                      size: 22,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${story.levelBand} · ${segments.length} lines · ${story.readTimeMinutes} min',
                    style: DesignTokens.label(
                      10,
                    ).copyWith(color: Colors.white70),
                  ),
                  const Spacer(),
                  _ListeningUtilityButton(
                    icon: Icons.translate,
                    label: 'Translate',
                    onTap: onToggleTranslation,
                  ),
                  _ListeningUtilityButton(
                    icon: CupertinoIcons.textformat_size,
                    label: 'Text size',
                    onTap: onCycleTextSize,
                  ),
                  _ListeningUtilityButton(
                    icon: CupertinoIcons.doc_on_doc,
                    label: 'Copy French',
                    onTap: onCopyLine,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _ListeningProgressControls(
                segments: segments,
                currentSegment: currentSegment,
                isPlaying: isPlaying,
                isLoading: isLoading,
                rate: rate,
                playbackPosition: playbackPosition,
                playbackDuration: playbackDuration,
                onToggle: onTogglePlayback,
                onReplay: onReplay,
                onCycleRate: onCycleRate,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ListeningMiniPlayer extends StatelessWidget {
  const _ListeningMiniPlayer({
    required this.story,
    required this.audioClip,
    required this.isPlaying,
    required this.isLoading,
    required this.onTogglePlayback,
  });

  final GeneratedStory story;
  final ElevenLabsAudioClip? audioClip;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(29),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              width: 38,
              height: 38,
              child: StoryCoverImage(
                title: story.displayTitle,
                source: story.coverUrl,
                fallbackIcon: CupertinoIcons.headphones,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${story.displayTitle} · ${audioClip?.mode ?? 'listening'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.body(
                12,
                weight: FontWeight.w700,
              ).copyWith(color: Colors.white),
            ),
          ),
          IconButton(
            tooltip: isPlaying ? 'Pause' : 'Play',
            onPressed: isLoading ? null : onTogglePlayback,
            icon: Icon(
              isLoading
                  ? CupertinoIcons.hourglass
                  : isPlaying
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
              color: DesignTokens.nightAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class _ListeningUtilityButton extends StatelessWidget {
  const _ListeningUtilityButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(icon, size: 18, color: Colors.white),
    );
  }
}

class _ListeningMoreSheet extends StatelessWidget {
  const _ListeningMoreSheet({
    required this.isMarkedLearned,
    required this.isLyricsVisible,
    required this.sessionType,
  });

  final bool isMarkedLearned;
  final bool isLyricsVisible;
  final String sessionType;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isLyricsVisible
                    ? CupertinoIcons.xmark_circle
                    : CupertinoIcons.text_quote,
              ),
              title: Text(isLyricsVisible ? 'Hide lyrics' : 'Open lyrics'),
              onTap: () => Navigator.pop(context, 'lyrics'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.checkmark_square),
              title: const Text('Quiz'),
              onTap: () => Navigator.pop(context, 'quiz'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.textformat),
              title: const Text('Keywords'),
              onTap: () => Navigator.pop(context, 'keywords'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.book),
              title: const Text('Grammar'),
              onTap: () => Navigator.pop(context, 'grammar'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.speedometer),
              title: const Text('Playback speed'),
              onTap: () => Navigator.pop(context, 'speed'),
            ),
            ListTile(
              leading: Icon(
                isMarkedLearned
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.checkmark_circle,
              ),
              title: Text(isMarkedLearned ? 'Learned' : 'Mark as learned'),
              onTap: isMarkedLearned
                  ? null
                  : () => Navigator.pop(context, 'learn'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.square_pencil),
              title: const Text('Add a note'),
              onTap: () => Navigator.pop(context, 'notes'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.slider_horizontal_3),
              title: const Text('Player settings'),
              onTap: () => Navigator.pop(context, 'settings'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.flag),
              title: const Text('Report a problem'),
              trailing: ReportProblemButton(sessionType: sessionType),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListeningTranscriptLines extends StatelessWidget {
  const _ListeningTranscriptLines({
    required this.segments,
    required this.currentSegment,
    required this.currentWord,
    required this.selectedSegment,
    required this.selectedWord,
    required this.keywords,
    required this.highlightWords,
    required this.underlineWords,
    required this.onWordTap,
    required this.showTranslation,
    this.textScale = 1,
  });

  final List<ReadingSegment> segments;
  final int currentSegment;
  final int? currentWord;
  final int? selectedSegment;
  final int? selectedWord;
  final List<VocabEntry> keywords;
  final bool highlightWords;
  final bool underlineWords;
  final void Function(int segmentIndex, int wordIndex) onWordTap;
  final bool showTranslation;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return Text(
        'Transcript not ready yet.',
        style: DesignTokens.body(15).copyWith(color: Colors.white70),
      );
    }
    final active = currentSegment.clamp(0, segments.length - 1).toInt();
    final maxStart = segments.length > 4 ? segments.length - 4 : 0;
    final start = (active - 1).clamp(0, maxStart).toInt();
    final end = (start + 4).clamp(0, segments.length).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          audioClipLabel(showTranslation),
          style: DesignTokens.label(
            10,
          ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1),
        ),
        const SizedBox(height: 9),
        for (var index = start; index < end; index++) ...[
          BilingualWordText(
            source: segments[index].fr,
            translation: segments[index].en,
            sourceStyle:
                DesignTokens.display(
                  (index == active ? 28 : 19) * textScale,
                ).copyWith(
                  color: index == active ? Colors.white : Colors.white54,
                  fontWeight: index == active
                      ? FontWeight.w800
                      : FontWeight.w500,
                  height: 1.18,
                ),
            translationStyle: DesignTokens.body(17 * textScale).copyWith(
              color: index == active ? Colors.white70 : Colors.white38,
              height: 1.3,
            ),
            keywords: keywords,
            showTranslation: showTranslation,
            highlightSelected: highlightWords,
            underlineSelected: underlineWords,
            accentColor: DesignTokens.nightAccent,
            selectedSourceWord: selectedSegment == index ? selectedWord : null,
            playbackSourceWord: _isActive(index, active) ? currentWord : null,
            playbackTranslationWord: _isActive(index, active)
                ? _mapListeningTranslationWord(
                    currentWord: currentWord,
                    source: segments[index].fr,
                    translation: segments[index].en,
                  )
                : null,
            onSourceWordTap: (wordIndex) => onWordTap(index, wordIndex),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  String audioClipLabel(bool translated) => translated
      ? 'TRANSCRIPT · ENGLISH ON'
      : 'TRANSCRIPT · ${currentSegment + 1}/${segments.length}';

  bool _isActive(int index, int active) => index == active;
}

int? _mapListeningTranslationWord({
  required int? currentWord,
  required String source,
  required String translation,
}) {
  if (currentWord == null || translation.trim().isEmpty) return null;
  final sourceCount = _listeningWordParts(source).length;
  final translationCount = _listeningWordParts(translation).length;
  if (sourceCount == 0 || translationCount == 0) return null;
  return (currentWord * translationCount / sourceCount)
      .floor()
      .clamp(0, translationCount - 1)
      .toInt();
}

List<String> _listeningWordParts(String value) => value
    .split(RegExp(r'\s+'))
    .where((word) => word.trim().isNotEmpty)
    .toList();

class _ListeningFullscreenTranscript extends StatelessWidget {
  const _ListeningFullscreenTranscript({
    required this.segments,
    required this.currentSegment,
    required this.currentWord,
    required this.selectedSegment,
    required this.selectedWord,
    required this.keywords,
    required this.highlightWords,
    required this.underlineWords,
    required this.showTranslation,
    required this.textScale,
    required this.isPlaying,
    required this.isLoading,
    required this.rate,
    required this.playbackPosition,
    required this.playbackDuration,
    required this.onTogglePlayback,
    required this.onReplay,
    required this.onCycleRate,
    required this.onToggleLyrics,
    required this.onToggleTranslation,
    required this.onCycleTextSize,
    required this.onCopyLine,
    required this.onWordTap,
  });

  final List<ReadingSegment> segments;
  final int currentSegment;
  final int? currentWord;
  final int? selectedSegment;
  final int? selectedWord;
  final List<VocabEntry> keywords;
  final bool highlightWords;
  final bool underlineWords;
  final bool showTranslation;
  final double textScale;
  final bool isPlaying;
  final bool isLoading;
  final double rate;
  final Duration playbackPosition;
  final Duration playbackDuration;
  final VoidCallback onTogglePlayback;
  final VoidCallback onReplay;
  final VoidCallback onCycleRate;
  final VoidCallback onToggleLyrics;
  final VoidCallback onToggleTranslation;
  final VoidCallback onCycleTextSize;
  final VoidCallback onCopyLine;
  final void Function(int segmentIndex, int wordIndex) onWordTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 36, 18, 26),
              child: _ListeningTranscriptLines(
                segments: segments,
                currentSegment: currentSegment,
                currentWord: currentWord,
                selectedSegment: selectedSegment,
                selectedWord: selectedWord,
                keywords: keywords,
                highlightWords: highlightWords,
                underlineWords: underlineWords,
                onWordTap: onWordTap,
                showTranslation: showTranslation,
                textScale: textScale,
              ),
            ),
          ),
        ),
        Row(
          children: [
            _ListeningUtilityButton(
              icon: CupertinoIcons.chevron_down,
              label: 'Close lyrics',
              onTap: onToggleLyrics,
            ),
            const Spacer(),
            _ListeningUtilityButton(
              icon: Icons.translate,
              label: showTranslation ? 'Hide translation' : 'Show translation',
              onTap: onToggleTranslation,
            ),
            _ListeningUtilityButton(
              icon: CupertinoIcons.textformat_size,
              label: 'Text size',
              onTap: onCycleTextSize,
            ),
            _ListeningUtilityButton(
              icon: CupertinoIcons.doc_on_doc,
              label: 'Copy French',
              onTap: onCopyLine,
            ),
          ],
        ),
        _ListeningProgressControls(
          segments: segments,
          currentSegment: currentSegment,
          isPlaying: isPlaying,
          isLoading: isLoading,
          rate: rate,
          playbackPosition: playbackPosition,
          playbackDuration: playbackDuration,
          onToggle: onTogglePlayback,
          onReplay: onReplay,
          onCycleRate: onCycleRate,
        ),
      ],
    );
  }
}

class _ListeningStageIslandTabs extends StatelessWidget {
  const _ListeningStageIslandTabs({required this.current, required this.onTap});

  final _ListeningTab current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const labels = ['Lyrics', 'Quiz', 'Keywords', 'Grammar'];
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(index),
                child: AnimatedContainer(
                  duration: DesignTokens.durationFast,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: current.index == index
                        ? DesignTokens.nightAccent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      labels[index],
                      style: DesignTokens.body(11, weight: FontWeight.w700)
                          .copyWith(
                            color: current.index == index
                                ? Colors.black
                                : Colors.white70,
                          ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ListeningProgressControls extends StatelessWidget {
  const _ListeningProgressControls({
    required this.segments,
    required this.currentSegment,
    required this.isPlaying,
    required this.isLoading,
    required this.rate,
    required this.playbackPosition,
    required this.playbackDuration,
    required this.onToggle,
    required this.onReplay,
    required this.onCycleRate,
  });

  final List<ReadingSegment> segments;
  final int currentSegment;
  final bool isPlaying;
  final bool isLoading;
  final double rate;
  final Duration playbackPosition;
  final Duration playbackDuration;
  final VoidCallback onToggle;
  final VoidCallback onReplay;
  final VoidCallback onCycleRate;

  @override
  Widget build(BuildContext context) {
    final durationMs = playbackDuration.inMilliseconds;
    final positionMs = playbackPosition.inMilliseconds;
    final progress = durationMs > 0
        ? (positionMs / durationMs).clamp(0.0, 1.0)
        : segments.length <= 1
        ? 0.0
        : (currentSegment / (segments.length - 1)).clamp(0.0, 1.0);
    return Column(
      children: [
        Row(
          children: [
            Text(
              segments.isEmpty
                  ? 'LISTENING'
                  : 'LINE ${currentSegment.clamp(0, segments.length - 1) + 1} / ${segments.length}',
              style: DesignTokens.label(9).copyWith(color: Colors.white60),
            ),
            const Spacer(),
            Text(
              '${SessionSettings.playbackRateLabel(rate)}×',
              style: DesignTokens.label(9).copyWith(color: Colors.white60),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation(DesignTokens.nightAccent),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Replay',
              onPressed: onReplay,
              icon: const Icon(CupertinoIcons.gobackward),
              color: Colors.white,
            ),
            IconButton(
              tooltip: isPlaying ? 'Pause' : 'Play',
              onPressed: isLoading ? null : onToggle,
              icon: Icon(
                isLoading
                    ? CupertinoIcons.hourglass
                    : isPlaying
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
                size: 24,
              ),
              color: Colors.black,
              style: IconButton.styleFrom(
                backgroundColor: DesignTokens.nightAccent,
                minimumSize: const Size(54, 54),
                shape: const CircleBorder(),
              ),
            ),
            IconButton(
              tooltip: 'Playback speed',
              onPressed: onCycleRate,
              icon: const Icon(CupertinoIcons.speedometer),
              color: Colors.white,
            ),
          ],
        ),
      ],
    );
  }
}

class _NightPanel extends StatelessWidget {
  const _NightPanel({required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent ?? DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: child,
    );
  }
}

class _NightPrimaryButton extends StatelessWidget {
  const _NightPrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: DesignTokens.nightAccent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: DesignTokens.nightSurfaceRaised,
          disabledForegroundColor: DesignTokens.nightMuted,
          textStyle: DesignTokens.body(14, weight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
        ),
      ),
    );
  }
}

class _NightAudioIsland extends StatelessWidget {
  const _NightAudioIsland({
    required this.isPlaying,
    required this.isLoading,
    required this.rate,
    required this.onToggle,
    required this.onReplay,
    required this.onCycleRate,
  });

  final bool isPlaying;
  final bool isLoading;
  final double rate;
  final VoidCallback onToggle;
  final VoidCallback onReplay;
  final VoidCallback onCycleRate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: DesignTokens.nightSurfaceRaised.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IslandCircle(
              icon: isLoading
                  ? CupertinoIcons.hourglass
                  : isPlaying
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
              filled: true,
              onTap: isLoading ? null : onToggle,
            ),
            _IslandDivider(),
            _IslandText(
              value: '${rate.toStringAsFixed(2)}×',
              onTap: onCycleRate,
            ),
            _IslandDivider(),
            _IslandCircle(icon: CupertinoIcons.repeat, onTap: onReplay),
            _IslandDivider(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(
                CupertinoIcons.book,
                color: DesignTokens.nightAccent,
                size: 19,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IslandDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 24, color: DesignTokens.nightHairline);
}

class _IslandCircle extends StatelessWidget {
  const _IslandCircle({required this.icon, this.filled = false, this.onTap});

  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: 'Audio control',
      icon: Icon(icon, size: 17),
      color: filled ? Colors.black : DesignTokens.nightText,
      style: IconButton.styleFrom(
        backgroundColor: filled ? DesignTokens.nightAccent : Colors.transparent,
        minimumSize: const Size(38, 38),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _IslandText extends StatelessWidget {
  const _IslandText({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(
          value,
          style: DesignTokens.body(
            12,
            weight: FontWeight.w700,
          ).copyWith(color: DesignTokens.nightText),
        ),
      ),
    );
  }
}

class _ListeningSettingsSheet extends StatelessWidget {
  const _ListeningSettingsSheet({required this.settings});

  final SessionSettings settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => SafeArea(
        child: Container(
          constraints: const BoxConstraints(maxHeight: 650),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Listening settings',
                      style: DesignTokens.display(
                        22,
                      ).copyWith(color: DesignTokens.nightText),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      CupertinoIcons.xmark,
                      color: DesignTokens.nightMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _NightSettingChoice(
                label: 'Text size',
                value: _textSizeLabel(settings.textScale),
                choices: const ['Small', 'Medium', 'Large'],
                selected: settings.textScale < 0.95
                    ? 'Small'
                    : settings.textScale > 1.1
                    ? 'Large'
                    : 'Medium',
                onSelected: (value) => settings.setTextScale(
                  value == 'Small'
                      ? 0.9
                      : value == 'Large'
                      ? 1.25
                      : 1,
                ),
              ),
              _NightSettingChoice(
                label: 'Playback speed',
                value:
                    '${SessionSettings.playbackRateLabel(settings.playbackRate)}×',
                choices: const ['0.5×', '0.75×', '1×', '1.5×'],
                selected: settings.playbackRate == 0.5
                    ? '0.5×'
                    : settings.playbackRate < 0.8
                    ? '0.75×'
                    : settings.playbackRate > 1.1
                    ? '1.5×'
                    : '1×',
                onSelected: (value) => settings.setPlaybackRate(
                  value == '0.5×'
                      ? 0.5
                      : value == '0.75×'
                      ? 0.75
                      : value == '1.5×'
                      ? 1.5
                      : 1,
                ),
              ),
              _NightSwitchRow(
                label: 'Word translations',
                value: settings.translateSentences,
                onChanged: settings.setTranslateSentences,
              ),
              _NightSwitchRow(
                label: 'Highlight words',
                value: settings.highlightWords,
                onChanged: settings.setHighlightWords,
              ),
              _NightSwitchRow(
                label: 'Underline words',
                value: settings.underlineWords,
                onChanged: settings.setUnderlineWords,
              ),
              _NightSwitchRow(
                label: 'Auto-play word audio',
                value: settings.autoPlayWordAudio,
                onChanged: settings.setAutoPlayWordAudio,
              ),
              _NightSwitchRow(
                label: 'Dark mode',
                value: settings.darkMode,
                onChanged: settings.setDarkMode,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: DesignTokens.nightAccent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _textSizeLabel(double value) => value < 0.95
      ? 'Small'
      : value > 1.1
      ? 'Large'
      : 'Medium';
}

class _NightSettingChoice extends StatelessWidget {
  const _NightSettingChoice({
    required this.label,
    required this.value,
    required this.choices,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String value;
  final List<String> choices;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: DesignTokens.body(
                    14,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.nightText),
                ),
              ),
              Text(
                value,
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.nightAccent),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              for (final choice in choices)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(choice),
                      selected: selected == choice,
                      onSelected: (_) => onSelected(choice),
                      selectedColor: DesignTokens.nightAccent,
                      backgroundColor: DesignTokens.nightSurfaceRaised,
                      labelStyle: TextStyle(
                        color: selected == choice
                            ? Colors.black
                            : DesignTokens.nightMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NightSwitchRow extends StatelessWidget {
  const _NightSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: DesignTokens.body(
          14,
          weight: FontWeight.w600,
        ).copyWith(color: DesignTokens.nightText),
      ),
      value: value,
      activeThumbColor: DesignTokens.nightAccent,
      onChanged: onChanged,
    );
  }
}

class _StageEyebrow extends StatelessWidget {
  const _StageEyebrow({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: DesignTokens.label(
            11,
          ).copyWith(color: DesignTokens.nightAccent),
        ),
        Text(
          detail,
          style: DesignTokens.label(
            10,
          ).copyWith(color: DesignTokens.nightMuted),
        ),
      ],
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    this.secondaryLabel,
    required this.selected,
    required this.correct,
    required this.onTap,
  });

  final String label;
  final String? secondaryLabel;
  final bool selected;
  final bool correct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = selected || correct;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          foregroundColor: correct ? Colors.black : DesignTokens.nightText,
          backgroundColor: correct
              ? Colors.greenAccent
              : active
              ? DesignTokens.nightAccentSoft
              : DesignTokens.nightSurfaceRaised,
          side: BorderSide(
            color: correct
                ? Colors.greenAccent
                : selected
                ? DesignTokens.nightAccent
                : DesignTokens.nightHairline,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: DesignTokens.body(13, weight: FontWeight.w600).copyWith(
                color: correct ? Colors.black : DesignTokens.nightText,
              ),
            ),
            if (secondaryLabel != null &&
                secondaryLabel!.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                secondaryLabel!,
                style: DesignTokens.body(11.5).copyWith(
                  color: correct ? Colors.black87 : DesignTokens.nightMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StageEyebrow(label: eyebrow, detail: 'Continue'),
        const SizedBox(height: 8),
        Text(
          title,
          style: DesignTokens.display(
            28,
          ).copyWith(color: DesignTokens.nightText),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: DesignTokens.body(14).copyWith(color: DesignTokens.nightMuted),
        ),
        const SizedBox(height: 20),
        _NightPrimaryButton(
          label: buttonLabel,
          icon: CupertinoIcons.arrow_right,
          onPressed: onPressed,
        ),
      ],
    );
  }
}
