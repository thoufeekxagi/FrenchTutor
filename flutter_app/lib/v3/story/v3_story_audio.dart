import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../data/database/learning_store.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../services/audio_streaming_service.dart';
import '../../services/inline_call_controller.dart';
import '../../utils/narration_alignment.dart';
import 'v3_story.dart';

/// What the reader needs to hear back from the audio engine.
class V3StoryAudioEvents {
  const V3StoryAudioEvents({
    required this.onSentence,
    required this.onWord,
    required this.onLoading,
    required this.onFinished,
    required this.onError,
  });

  /// A sentence started (also fires for a replay of one sentence).
  final void Function(int sentence) onSentence;

  /// The spoken word moved. [rawWord] numbers whitespace tokens of the French.
  final void Function(int sentence, int rawWord) onWord;
  final void Function(bool loading) onLoading;
  final void Function() onFinished;
  final void Function(String message) onError;
}

/// The story's voice. Production uses the selected tutor (Gemini Live), exactly like
/// the legacy reader. Tests use [V3FakeStoryAudio], which makes no network or
/// billing calls and records what was asked of it.
abstract class V3StoryAudio {
  /// Test-only record of requests, for assertions in device tests.
  static final debugLog = <String>[];

  static bool get useFake =>
      kDebugMode && const bool.fromEnvironment('E2E_FAKE_AUDIO');

  /// Plays from [from] to the end, or just sentence [from] when [only].
  Future<void> playSentences(int from, {bool only = false});
  Future<void> stop();

  /// Says one word or short phrase once.
  Future<void> speakWord(String text);
  void setRate(double rate);
  void handleLifecycle(AppLifecycleState state);
  void dispose();
}

class V3FakeStoryAudio implements V3StoryAudio {
  V3FakeStoryAudio({required this.story, required this.events});

  final V3Story story;
  final V3StoryAudioEvents events;
  int _generation = 0;

  @override
  Future<void> playSentences(int from, {bool only = false}) async {
    final gen = ++_generation;
    V3StoryAudio.debugLog.add('play:$from${only ? ':only' : ''}');
    final last = only ? from : story.sentences.length - 1;
    for (var i = from; i <= last; i++) {
      if (gen != _generation) return;
      events.onSentence(i);
      final raw = story.sentences[i].fr.split(RegExp(r'\s+')).length;
      for (var w = 0; w < raw; w++) {
        if (gen != _generation) return;
        events.onWord(i, w);
        await Future<void>.delayed(const Duration(milliseconds: 90));
      }
    }
    if (gen == _generation) events.onFinished();
  }

  @override
  Future<void> stop() async {
    _generation++;
    V3StoryAudio.debugLog.add('stop');
    events.onFinished();
  }

  @override
  Future<void> speakWord(String text) async {
    V3StoryAudio.debugLog.add('word:$text');
  }

  @override
  void setRate(double rate) => V3StoryAudio.debugLog.add('rate:$rate');

  @override
  void handleLifecycle(AppLifecycleState state) {}

  @override
  void dispose() => _generation++;
}

/// Live tutor narration, ported from the legacy story reader: one Gemini Live
/// connection, opened on the first play or word tap, speaks each sentence
/// exactly once on command. Nothing is cached or generated ahead of time.
class V3LiveStoryAudio implements V3StoryAudio {
  V3LiveStoryAudio({
    required this.story,
    required this.events,
    required this.learningStore,
    required this.contextProvider,
    required this.buildContext,
  }) {
    _audio = AudioStreamingService();
    _call = InlineCallController(
      sessionType: LiveSessionType.readingNarration,
      lessonContext: _lessonContext,
      learningStoreForProfile: learningStore,
      onChanged: () {},
    );
  }

  final V3Story story;
  final V3StoryAudioEvents events;
  final LearningStore learningStore;
  final String Function() contextProvider;
  final BuildContext? Function() buildContext;

  late final AudioStreamingService _audio;
  late final InlineCallController _call;
  int _generation = 0;
  double _rate = 1;
  Timer? _highlightTimer;
  String _transcript = '';
  int? _transcriptWord;

  String _lessonContext() => contextProvider();

  Future<bool> _ensureReady() async {
    final ctx = buildContext();
    if (!_call.isLive && ctx != null) {
      await _call.start(ctx, sendOpeningPrompt: false);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (!_call.isReadyForLearnerTurn && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return _call.isReadyForLearnerTurn;
  }

  String _friendly(Object error) {
    final raw = error.toString().toLowerCase();
    final tutor = ActiveTutor.current.displayName;
    if (error is TimeoutException || raw.contains('timeout')) {
      return '$tutor took too long to start. Tap play to try again.';
    }
    if (raw.contains('still finishing')) {
      return '$tutor is finishing the previous line. Tap play again in a moment.';
    }
    if (raw.contains('disconnected') || raw.contains('not connected')) {
      return '$tutor lost the connection. Tap play to reconnect.';
    }
    return '$tutor could not read this story. Tap play to try again.';
  }

  @override
  Future<void> playSentences(int from, {bool only = false}) async {
    if (!await _ensureReady()) {
      events.onError(
        '${ActiveTutor.current.displayName} is not connected yet. Tap play to reconnect.',
      );
      events.onFinished();
      return;
    }
    final gen = ++_generation;
    await _call.beginExternalPlayback();
    try {
      final last = only ? from : story.sentences.length - 1;
      for (var i = from; i <= last; i++) {
        if (gen != _generation) break;
        await _playOne(i, gen);
      }
    } catch (error) {
      if (gen == _generation) events.onError(_friendly(error));
    } finally {
      _highlightTimer?.cancel();
      _highlightTimer = null;
      await _audio.stopPlayback(hardStop: true);
      await _call.refreshAfterExternalPlayback();
      if (gen == _generation) events.onFinished();
    }
  }

  Future<void> _playOne(int index, int gen) async {
    final sentence = story.sentences[index];
    await _audio.waitForPlaybackDrained();
    _highlightTimer?.cancel();
    _audio.resetPlaybackTimeline();
    _transcript = '';
    _transcriptWord = null;
    var tail = Future<void>.value();
    var failed = false;
    var chunks = 0;
    var lastRaw = -1;
    events.onSentence(index);
    events.onLoading(true);
    _highlightTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (gen != _generation) return;
      if (_audio.playbackTimelineDuration <= Duration.zero) return;
      final next = NarrationAlignment.playbackWordIndex(
        sentence.fr,
        playbackPosition: _audio.playbackTimelinePosition,
        queuedAudioDuration: _audio.playbackTimelineDuration,
        transcriptWordIndex: _transcriptWord,
      );
      if (next != null && next > lastRaw) {
        lastRaw = next;
        events.onWord(index, next);
      }
    });
    await _call.narrateExternalText(
      instruction:
          'APP_NARRATION sentence_id=$index AUDIO_REQUIRED. Say this exact '
          'French sentence once and stop. Do not skip it, combine it with '
          'another sentence, or explain it: ${sentence.fr}',
      onAudioChunk: (bytes) {
        if (gen != _generation || bytes.isEmpty) return;
        chunks++;
        tail = tail.then((_) async {
          try {
            await _audio.playAudioChunk(bytes, playbackSpeed: _rate);
            if (gen == _generation) events.onLoading(false);
          } catch (error) {
            failed = true;
            debugPrint('V3 story audio feed failed: $error');
          }
        });
      },
      onTranscriptDelta: (delta) {
        if (gen != _generation) return;
        _transcript = NarrationAlignment.appendTranscriptDelta(
          _transcript,
          delta,
        );
        final next = NarrationAlignment.currentWordIndex(
          sentence.fr,
          _transcript,
        );
        if (next != null &&
            (_transcriptWord == null || next > _transcriptWord!)) {
          _transcriptWord = next;
        }
      },
    );
    await tail;
    if (gen != _generation) return;
    if (failed || chunks == 0) {
      throw StateError('Story narration audio could not be queued');
    }
    await _audio.waitForPlaybackDrained();
    _highlightTimer?.cancel();
    _highlightTimer = null;
    events.onLoading(false);
  }

  @override
  Future<void> stop() async {
    _generation++;
    _highlightTimer?.cancel();
    _highlightTimer = null;
    await _audio.stopPlayback(hardStop: true);
    await _call.endExternalPlayback();
    events.onLoading(false);
    events.onFinished();
  }

  @override
  Future<void> speakWord(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final ctx = buildContext();
    if (!_call.active && ctx != null) {
      try {
        await _call.start(ctx, sendOpeningPrompt: false);
      } catch (_) {
        events.onError(
          '${ActiveTutor.current.displayName} could not connect. Tap the word again to retry.',
        );
        return;
      }
    }
    if (!_call.active) {
      events.onError(
        '${ActiveTutor.current.displayName} is still connecting. Tap the word again.',
      );
      return;
    }
    _call.promptTutor(
      'APP_WORD Say only this French word or phrase once, clearly and '
      'naturally, then stop. Do not translate or explain it: "$trimmed"',
    );
  }

  @override
  void setRate(double rate) {
    _rate = rate;
    unawaited(_audio.setPlaybackSpeed(rate));
  }

  @override
  void handleLifecycle(AppLifecycleState state) =>
      _call.handleAppLifecycle(state);

  @override
  void dispose() {
    _generation++;
    _highlightTimer?.cancel();
    _call.dispose();
    unawaited(_audio.dispose());
  }
}
