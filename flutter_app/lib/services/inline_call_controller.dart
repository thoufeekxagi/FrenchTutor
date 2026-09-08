import 'dart:async';

import 'package:flutter/widgets.dart';

import '../config/api_keys.dart';
import '../data/database/learning_store.dart';
import '../models/tutor_persona.dart';
import '../models/agent_tool.dart';
import '../prompts/live_prompts.dart';
import '../widgets/ai_voice_disclosure.dart';
import 'audio_streaming_service.dart';
import 'ai_cost_tracker.dart';
import 'gemini_live_service.dart';
import 'lesson_speech_service.dart';

/// Runs Marie's live call INLINE within whatever screen owns it — the
/// reading/exercise/editor content stays visible and interactive the whole
/// time the call is live, exactly like the Writing lab's "Talk with Marie"
/// button always has. This is deliberately NOT `MarieToolbarButton` (which
/// pushes a fullscreen `SessionScreen` route): that pattern yanks the
/// learner away from the material they were just looking at into a separate
/// window, which is the opposite of what a "help me understand this" call
/// should feel like.
///
/// One instance per host screen. The host's `State` must:
///   - mix in `WidgetsBindingObserver`, add/remove itself in
///     initState/dispose, and forward `didChangeAppLifecycleState` to
///     [handleAppLifecycle];
///   - call [dispose] from its own `dispose()`;
///   - call `setState(() {})` from [onChanged] to reflect state changes.
class InlineCallController {
  InlineCallController({
    required this.sessionType,
    required this.lessonContext,
    required this.learningStoreForProfile,
    required this.onChanged,
    this.openingPrompt,
    this.onUserTranscript,
    this.onTutorTranscript,
    this.onTurnComplete,
    this.tools = const [],
    this.onToolCall,
    this.manualLearnerTurns = false,
    this.compactGuidedContext = false,
  });

  final LiveSessionType sessionType;

  /// Rebuilt on every connect — some hosts (the Writing editor) need the
  /// LATEST content (draft, existing feedback) at connect time, not a
  /// snapshot taken when the controller was constructed.
  final String Function() lessonContext;

  final LearningStore learningStoreForProfile;

  /// Called after any field below changes — call `setState(() {})` here.
  final VoidCallback onChanged;

  /// Optional first turn for contexts where Marie should open the call
  /// instead of waiting for the learner to speak. The writing screen uses
  /// this for a short, reassuring offer of help after the phone connection
  /// is ready.
  final String? openingPrompt;

  /// Forwards Marie's transcript turns to the host — without this, an inline
  /// call's conversation was silently never logged anywhere (not even for
  /// the auto-generated review note), unlike `SessionScreen`'s calls. Hosts
  /// that own a `SessionRecorder` should wire these straight to
  /// `logUser`/`logTutor` so the call counts toward that session's recap.
  final void Function(String text)? onUserTranscript;
  final void Function(String text)? onTutorTranscript;
  final VoidCallback? onTurnComplete;

  /// Optional structured events emitted by Gemini during a Live turn.
  final List<AgentTool> tools;
  final void Function(String name, Map<String, dynamic> args, String callId)?
  onToolCall;

  /// Gives a host explicit tap-to-record boundaries instead of server-side
  /// silence detection. This is important for short beginner phrases, where a
  /// pause inside the sentence must not trigger an early Murray reply.
  final bool manualLearnerTurns;

  /// Guided speaking cards need only the current visible step. When enabled,
  /// GeminiLiveService uses the compact guided prompt and smaller compression
  /// window without changing the existing local transcript/matching path.
  final bool compactGuidedContext;

  GeminiLiveService? gemini;
  AudioStreamingService? audio;
  bool connecting = false;
  bool active = false;
  bool muted = false;
  bool tutorSpeaking = false;
  bool reconnecting = false;
  Future<void>? _ending;
  Future<void>? _starting;
  Timer? _manualIdleTimer;
  // Story/lesson narration uses a separate AudioStreamingService from this
  // call. Keep an explicit bridge between the two so narration is never sent
  // back to Marie as if it were learner speech.
  bool _externalPlaybackPaused = false;
  bool _externalPlaybackShouldResume = false;
  int _externalNarrationGeneration = 0;
  void Function(List<int>)? _externalNarrationAudio;
  void Function(String)? _externalNarrationTranscript;
  Completer<void>? _externalNarrationCompletion;
  Timer? _externalNarrationFirstAudioTimer;
  Timer? _externalNarrationAudioIdleTimer;
  bool _externalNarrationReceivedAudio = false;
  // A connect can finish after the learner has already tapped the phone to
  // stop.  Keep a monotonically increasing intent id so a late Live callback
  // cannot resurrect the UI or leave an orphaned socket marked active.
  int _connectionGeneration = 0;
  bool _disposed = false;

  static const _manualIdleLimit = Duration(seconds: 45);

  /// Every callback into the host (state changes, transcripts, tool calls)
  /// must go through here once [dispose] has run. `dispose()` starts the
  /// Gemini/audio teardown asynchronously (`unawaited`) and returns
  /// immediately, so a socket callback such as `GeminiLiveService.disconnect`
  /// can still fire after the host widget has fully unmounted. Relying on the
  /// host's own `mounted` check is not enough to catch that race, so the
  /// controller itself must refuse to call back out after disposal.
  void _notify() {
    if (_disposed) return;
    onChanged();
  }

  bool _isCurrentGeneration(int generation) =>
      !_disposed && generation == _connectionGeneration;

  // P0.4 pocket/lock-screen handling (same contract as SessionScreen): the
  // mic stream stops on pause so a pocket never gets recorded and sent, and
  // resumes on foreground — but only if the student hadn't muted on
  // purpose, so backgrounding never silently un-mutes them.
  bool pausedForLifecycle = false;

  String? error;
  String? lastTutorLine;

  bool get isLive => active || connecting;

  /// A learner turn must only open after setup has completed. [isLive] also
  /// includes the connecting/reconnecting states, which are valid for the
  /// status UI but cannot accept audio yet.
  bool get isReadyForLearnerTurn =>
      active &&
      !connecting &&
      !reconnecting &&
      gemini?.isConnected == true &&
      audio != null;

  /// Whether the previous tutor reply is still being generated or played.
  bool get tutorTurnActive =>
      tutorSpeaking || gemini?.isModelGenerating == true;

  /// Waits briefly for an in-flight tutor reply to finish before a guided
  /// retry opens a new learner turn. This prevents the old reply's completion
  /// event from being mistaken for the retry's result.
  Future<bool> waitForTutorTurnToFinish({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final live = gemini;
    if (live != null) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero ||
          !await live.waitForTurnToComplete(timeout: remaining)) {
        return false;
      }
    }
    while (tutorTurnActive && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return !tutorTurnActive;
  }

  Future<void> toggle(BuildContext context) async {
    if (active || connecting) {
      await end();
      return;
    }
    await start(context);
  }

  /// Starts the inline helper without changing the existing toggle contract.
  /// Hosts that temporarily pause the helper while they capture a learner
  /// answer can restart the same live stream without making Marie repeat her
  /// opening line.
  Future<void> start(BuildContext context, {bool sendOpeningPrompt = true}) {
    final existing = _starting;
    if (existing != null) return existing;
    late Future<void> starting;
    starting = _start(context, sendOpeningPrompt: sendOpeningPrompt)
        .whenComplete(() {
          if (identical(_starting, starting)) _starting = null;
        });
    _starting = starting;
    return starting;
  }

  Future<void> _start(
    BuildContext context, {
    bool sendOpeningPrompt = true,
  }) async {
    final generation = ++_connectionGeneration;
    unawaited(
      AiCostTracker.event(
        feature: sessionType.name,
        event: 'inline_live_start_requested',
        extra: {'manual_activity_boundaries': manualLearnerTurns},
      ),
    );
    // Ending a live call closes native recorder/player handles asynchronously.
    // Wait for that teardown before opening narration or a new call, otherwise
    // the old tutor stream can bleed into the next lesson audio.
    final ending = _ending;
    if (ending != null) await ending;
    if (!_isCurrentGeneration(generation) || !context.mounted) return;
    final accepted = await AiVoiceDisclosure.ensureAccepted(context);
    if (!accepted || !_isCurrentGeneration(generation)) return;
    // Narration and the inline call share the iOS audio session. This must be
    // awaited so a queued narration clip cannot race the call's first turn.
    await LessonSpeechService.shared.deactivate();
    if (!_isCurrentGeneration(generation)) return;
    connecting = true;
    error = null;
    lastTutorLine = null;
    _notify();
    final connected = await _connect(generation);
    if (!connected) {
      if (!_isCurrentGeneration(generation)) return;
      connecting = false;
      error ??= "Couldn't connect. Check your connection and try again.";
      _notify();
      unawaited(
        AiCostTracker.event(
          feature: sessionType.name,
          event: 'inline_live_start_failed',
        ),
      );
      return;
    }
    if (!_isCurrentGeneration(generation) || audio == null || gemini == null) {
      return;
    }
    final granted = await audio!.requestPermission();
    if (!_isCurrentGeneration(generation) || audio == null || gemini == null) {
      return;
    }
    if (!granted) {
      connecting = false;
      error = 'Microphone permission denied';
      gemini?.disconnect();
      gemini = null;
      _notify();
      unawaited(
        AiCostTracker.event(
          feature: sessionType.name,
          event: 'inline_live_microphone_denied',
        ),
      );
      return;
    }
    if (manualLearnerTurns) {
      // Do not open the learner microphone for the idle/opening-prompt phase.
      // Guided speaking opens it only from startLearnerTurn(), after the user
      // taps Record. Gemini's output player is lazy and starts when Marie's
      // first audio chunk arrives.
      muted = true;
      _notify();
    } else if (!_externalPlaybackPaused) {
      await audio!.startStreaming(onChunk: gemini!.sendAudioChunk);
    }
    connecting = false;
    active = true;
    _scheduleManualIdleLimit();
    unawaited(
      AiCostTracker.event(
        feature: sessionType.name,
        event: 'inline_live_active',
        extra: {'manual_activity_boundaries': manualLearnerTurns},
      ),
    );
    _notify();
    final prompt = sendOpeningPrompt ? openingPrompt?.trim() : null;
    if (prompt != null && prompt.isNotEmpty) {
      gemini?.injectContext(prompt, expectReply: true);
    }
  }

  Future<bool> _connect(int generation) async {
    final completer = Completer<bool>();
    final a = AudioStreamingService();
    final g = GeminiLiveService(
      apiKey: ApiKeys.geminiKey,
      sessionType: sessionType,
      lessonContext: lessonContext(),
      learningStoreForProfile: learningStoreForProfile,
      // Keep Gemini on the proven legacy audioStreamEnd/automatic-VAD
      // protocol. manualLearnerTurns only gates the local microphone; it must
      // not switch the Live socket to the newer activityStart/activityEnd
      // protocol, which is what caused guided sessions to close.
      manualActivityBoundaries: false,
      // Speaking screens consume Gemini's input transcript as it settles so
      // their UI can resolve independently of Marie's spoken-output duration.
      deferUserTranscriptUntilTurnComplete: false,
      compactGuidedContext: compactGuidedContext,
      tools: tools,
    );
    audio = a;
    gemini = g;

    g.onConnected = () {
      if (_isCurrentGeneration(generation) && !completer.isCompleted) {
        completer.complete(true);
      }
    };
    g.onReconnecting = (_) {
      if (!_isCurrentGeneration(generation)) return;
      a.stopPlayback();
      a.isOutputActive = false;
      reconnecting = true;
      error = null;
      _notify();
    };
    g.onReconnected = () {
      if (!_isCurrentGeneration(generation)) return;
      reconnecting = false;
      _notify();
    };
    g.onError = (msg) {
      if (!_isCurrentGeneration(generation)) return;
      final narration = _externalNarrationCompletion;
      if (narration != null && !narration.isCompleted) {
        narration.completeError(StateError(msg));
      }
      error = msg;
      if (!completer.isCompleted) {
        completer.complete(false);
        return;
      }
      _notify();
    };
    g.onDisconnected = () {
      if (!_isCurrentGeneration(generation)) return;
      final narration = _externalNarrationCompletion;
      if (narration != null && !narration.isCompleted) {
        narration.completeError(
          StateError('Marie disconnected during narration'),
        );
      }
      if (!completer.isCompleted) {
        completer.complete(false);
        return;
      }
      active = false;
      reconnecting = false;
      _notify();
    };
    g.onUserTranscript = (text) {
      if (!_isCurrentGeneration(generation)) return;
      // A stale transcript can arrive just after the recorder is stopped for
      // external story narration. It belongs to the speaker output, never to
      // the learner, so discard it at the controller boundary.
      if (_externalPlaybackPaused) return;
      onUserTranscript?.call(text);
    };
    g.onTutorTranscript = (text) {
      if (!_isCurrentGeneration(generation)) return;
      if (_externalNarrationCompletion != null) return;
      lastTutorLine = text;
      _notify();
      onTutorTranscript?.call(text);
    };
    g.onAudioChunk = (bytes) {
      if (!_isCurrentGeneration(generation)) return;
      final externalAudio = _externalNarrationAudio;
      if (_externalPlaybackPaused && externalAudio != null) {
        externalAudio(bytes);
        return;
      }
      // Suppress any already-buffered tutor reply while the story player owns
      // the phone speaker. Without this guard a late Live chunk can reopen
      // the call's player over the narration we are trying to play.
      if (_externalPlaybackPaused) return;
      a.isOutputActive = true;
      tutorSpeaking = true;
      a.playAudioChunk(bytes);
    };
    g.onTranscriptDelta = (delta) {
      if (!_isCurrentGeneration(generation)) return;
      _externalNarrationTranscript?.call(delta);
    };
    g.onInterrupted = () {
      if (!_isCurrentGeneration(generation)) return;
      final narration = _externalNarrationCompletion;
      if (narration != null && !narration.isCompleted) {
        narration.completeError(
          StateError('Marie narration was interrupted before completion'),
        );
      }
    };
    g.onTurnComplete = () {
      if (!_isCurrentGeneration(generation)) return;
      a.isOutputActive = false;
      tutorSpeaking = false;
      _scheduleManualIdleLimit();
      _notify();
      final narration = _externalNarrationCompletion;
      if (narration != null) {
        _completeExternalNarration();
        if (narration.isCompleted) {
          _externalNarrationAudioIdleTimer?.cancel();
          _externalNarrationAudioIdleTimer = null;
          return;
        }
      }
      if (_disposed) return;
      onTurnComplete?.call();
    };
    g.onToolCall = (name, args, callId) {
      if (!_isCurrentGeneration(generation)) return;
      onToolCall?.call(name, args, callId);
    };

    g.connect();
    // Token minting may use the full 10-second server timeout before the
    // Live socket sends setupComplete. Do not report a false connection error
    // while the proven legacy transport is still starting.
    final connected = await completer.future.timeout(
      const Duration(seconds: 22),
      onTimeout: () => false,
    );
    if (!connected || !_isCurrentGeneration(generation)) {
      g.disconnect();
      await a.dispose();
      if (identical(gemini, g)) gemini = null;
      if (identical(audio, a)) audio = null;
      return false;
    }
    return connected;
  }

  void sendText(String text) {
    final trimmed = text.trim();
    if (!isLive || trimmed.isEmpty) return;
    gemini?.sendText(trimmed);
  }

  void sendToolResponse({
    required String callId,
    required String name,
    required Map<String, dynamic> result,
    String? scheduling,
  }) {
    gemini?.sendToolResponse(
      callId: callId,
      name: name,
      result: result,
      scheduling: scheduling,
    );
  }

  /// Gives the live helper an app-owned coaching instruction. This is kept
  /// separate from [sendText] so a scripted lesson never treats its own
  /// current prompt as learner input.
  void promptTutor(String instruction) {
    final trimmed = instruction.trim();
    if (!isLive || trimmed.isEmpty) return;
    // If Murray is still finishing the previous phrase, queue this instruction
    // behind that turn. Sending it immediately would interrupt the old audio and
    // make the new phrase sound like a cut-off/restart.
    gemini?.queueSpokenContext(trimmed);
  }

  /// Drops any stale tutor audio before a host screen replaces its current
  /// card, without closing the persistent socket.
  void suppressCurrentReply() {
    gemini?.suppressCurrentReply();
  }

  /// Refreshes the host screen's lesson context without opening a tutor turn.
  /// Scripted hosts call this when the learner advances to a new card while a
  /// call remains active. Marie absorbs the new context silently and only
  /// speaks again when the learner asks or starts a turn.
  void updateLessonContext() {
    if (!isLive) return;
    gemini?.injectContext(lessonContext(), expectReply: false);
  }

  Future<bool> startLearnerTurn() async {
    if (_externalPlaybackPaused ||
        !isReadyForLearnerTurn ||
        gemini == null ||
        audio == null) {
      return false;
    }
    gemini!.beginAudioTurn();
    _manualIdleTimer?.cancel();
    _manualIdleTimer = null;
    if (muted) {
      muted = false;
      _notify();
      await audio!.startStreaming(onChunk: gemini!.sendAudioChunk);
    }
    return true;
  }

  Future<void> endLearnerTurn() async {
    if (!isLive || gemini == null || audio == null) return;
    // Signal the server before closing the local recorder so the final PCM
    // bytes remain part of the same learner turn.
    gemini!.endAudioTurn();
    await audio!.stopStreaming();
    muted = true;
    _scheduleManualIdleLimit();
    _notify();
  }

  void _scheduleManualIdleLimit() {
    _manualIdleTimer?.cancel();
    _manualIdleTimer = null;
    if (!manualLearnerTurns || !active || _disposed) return;
    _manualIdleTimer = Timer(_manualIdleLimit, () {
      _manualIdleTimer = null;
      if (_disposed || !isLive || !muted) return;
      if (tutorTurnActive) {
        _scheduleManualIdleLimit();
        return;
      }
      // A connected manual-turn helper with no learner audio is idle spend.
      // Close it locally; the learner can explicitly reconnect when ready.
      unawaited(_end(notify: false));
      error = 'Tutor paused after 45 seconds without a learner turn.';
      _notify();
    });
  }

  Future<void> toggleMute() async {
    if (audio == null) return;
    if (muted) {
      muted = false;
      _notify();
      if (!_externalPlaybackPaused) {
        await audio!.startStreaming(onChunk: gemini!.sendAudioChunk);
      }
    } else {
      await audio!.stopStreaming();
      muted = true;
      _notify();
    }
  }

  /// Pauses learner microphone capture while another lesson surface (for
  /// example the Reading story Live narrator) owns the phone speaker. This is
  /// deliberately separate from [muted]: the user did not mute Marie, and the
  /// mic should resume automatically when the external playback finishes.
  Future<void> beginExternalPlayback() async {
    if (!isLive || _externalPlaybackPaused) return;
    _externalPlaybackPaused = true;
    final currentAudio = audio;
    _externalPlaybackShouldResume =
        currentAudio?.isStreaming == true || (!manualLearnerTurns && !muted);
    // Only arm Gemini's stale-reply suppression while it is actually
    // generating. Calling suppressCurrentReply while Marie is idle sets a
    // pre-injection flag that would otherwise swallow her next natural
    // learner response after narration ends.
    if (gemini?.isModelGenerating == true) suppressCurrentReply();
    if (currentAudio != null) {
      await currentAudio.stopStreaming();
      // A tutor reply may already be queued in the Live player. Drop it so a
      // late chunk cannot bleed into the story narration.
      await currentAudio.stopPlayback(hardStop: true);
    }
    tutorSpeaking = false;
    _notify();
  }

  /// Sends one app-owned narration command through the already-connected Marie
  /// socket. The caller must hold [beginExternalPlayback] while this runs; the
  /// microphone is then stopped and only this callback receives model audio.
  /// No generated PCM/cache path is involved.
  Future<void> narrateExternalText({
    required String instruction,
    required void Function(List<int>) onAudioChunk,
    required void Function(String) onTranscriptDelta,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!_externalPlaybackPaused || !isLive || gemini == null) {
      throw StateError('Marie is not ready for story narration');
    }
    if (gemini!.isModelGenerating) {
      final previousTurnFinished = await waitForTutorTurnToFinish(
        timeout: const Duration(seconds: 3),
      );
      if (!previousTurnFinished) {
        throw StateError('Marie is still finishing the previous reply');
      }
    }
    final previous = _externalNarrationCompletion;
    if (previous != null && !previous.isCompleted) {
      throw StateError('A story narration is already in progress');
    }
    final generation = ++_externalNarrationGeneration;
    final completion = Completer<void>();
    _externalNarrationCompletion = completion;
    _externalNarrationFirstAudioTimer?.cancel();
    _externalNarrationAudioIdleTimer?.cancel();
    _externalNarrationReceivedAudio = false;
    _externalNarrationFirstAudioTimer = Timer(const Duration(seconds: 6), () {
      if (generation == _externalNarrationGeneration &&
          !_externalNarrationReceivedAudio &&
          !completion.isCompleted) {
        completion.completeError(
          TimeoutException('Marie returned no narration audio'),
        );
      }
    });
    _externalNarrationAudio = (bytes) {
      if (generation == _externalNarrationGeneration) {
        _externalNarrationFirstAudioTimer?.cancel();
        _externalNarrationFirstAudioTimer = null;
        onAudioChunk(bytes);
        _externalNarrationReceivedAudio = true;
        _externalNarrationAudioIdleTimer?.cancel();
        _externalNarrationAudioIdleTimer = Timer(
          const Duration(milliseconds: 1400),
          () {
            if (generation != _externalNarrationGeneration ||
                !_externalNarrationReceivedAudio) {
              return;
            }
            _completeExternalNarration();
          },
        );
      }
    };
    _externalNarrationTranscript = (delta) {
      if (generation == _externalNarrationGeneration) {
        onTranscriptDelta(delta);
      }
    };
    try {
      gemini!.sendText(instruction);
      await completion.future.timeout(
        timeout,
        onTimeout: () {
          // A small number of Live turns deliver all audio but omit the final
          // turnComplete event. Once audio has arrived, treating that missing
          // bookkeeping event as success is safer than showing a false error;
          // the story player still waits for its own audio queue to drain.
          if (_externalNarrationReceivedAudio) {
            _completeExternalNarration();
            return;
          }
          throw TimeoutException('Marie narration timed out');
        },
      );
      // A Live turn can occasionally close cleanly without carrying a model
      // audio chunk (or deliver that first chunk just after turnComplete).
      // Treating that as success made the story player silently advance and
      // skip a sentence. Give the ordered WebSocket callbacks a short grace
      // window, then fail the current sentence instead of moving past it.
      if (!_externalNarrationReceivedAudio) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!_externalNarrationReceivedAudio) {
          throw StateError('Marie returned no narration audio');
        }
      }
    } finally {
      _externalNarrationFirstAudioTimer?.cancel();
      _externalNarrationFirstAudioTimer = null;
      _externalNarrationAudioIdleTimer?.cancel();
      _externalNarrationAudioIdleTimer = null;
      if (generation == _externalNarrationGeneration) {
        _externalNarrationAudio = null;
        _externalNarrationTranscript = null;
        _externalNarrationCompletion = null;
      }
    }
  }

  void _completeExternalNarration() {
    final completion = _externalNarrationCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
  }

  /// Releases the external-playback gate and restores the mic only when it was
  /// actually open before narration started. Repeated calls are harmless, so
  /// both the story completion callback and a tab change can call this safely.
  Future<void> endExternalPlayback() async {
    if (!_externalPlaybackPaused) return;
    final shouldResume = _externalPlaybackShouldResume;
    _externalNarrationGeneration++;
    _externalNarrationAudio = null;
    _externalNarrationTranscript = null;
    _externalNarrationFirstAudioTimer?.cancel();
    _externalNarrationFirstAudioTimer = null;
    final narration = _externalNarrationCompletion;
    if (narration != null && !narration.isCompleted) {
      narration.completeError(StateError('Story narration stopped'));
    }
    _externalNarrationAudioIdleTimer?.cancel();
    _externalNarrationAudioIdleTimer = null;
    _externalNarrationCompletion = null;
    _externalPlaybackPaused = false;
    _externalPlaybackShouldResume = false;
    if (!_disposed &&
        shouldResume &&
        active &&
        audio != null &&
        gemini != null &&
        !muted &&
        !audio!.isStreaming) {
      await audio!.startStreaming(onChunk: gemini!.sendAudioChunk);
    }
  }

  Future<void> end() => _end(notify: true);

  Future<void> _end({required bool notify}) {
    final existing = _ending;
    if (existing != null) return existing;

    // Invalidate callbacks before clearing references.  Gemini can deliver
    // setupComplete/onConnected on the same event loop turn as disconnect;
    // those callbacks must not turn a stopped helper back on.
    _connectionGeneration++;
    final currentAudio = audio;
    final currentGemini = gemini;
    _manualIdleTimer?.cancel();
    _manualIdleTimer = null;
    unawaited(
      AiCostTracker.event(
        feature: sessionType.name,
        event: 'inline_live_end_requested',
        extra: {
          'notify': notify,
          'was_active': active,
          'was_connecting': connecting,
        },
      ),
    );
    audio = null;
    gemini = null;
    active = false;
    connecting = false;
    muted = false;
    tutorSpeaking = false;
    reconnecting = false;
    pausedForLifecycle = false;
    _externalPlaybackPaused = false;
    _externalPlaybackShouldResume = false;
    _externalNarrationGeneration++;
    _externalNarrationAudio = null;
    _externalNarrationTranscript = null;
    _externalNarrationCompletion = null;
    if (notify) _notify();

    // Disconnect first so no new model chunks are accepted, then await the
    // native audio disposal. AudioStreamingService.dispose() drains all
    // in-flight playback/feed operations before closing the player; making
    // that ordering explicit prevents a stale tutor phrase from being heard
    // when the learner taps Listen on the next/final card.
    late Future<void> ending;
    ending =
        (() async {
          currentGemini?.disconnect();
          try {
            await currentAudio?.dispose();
          } catch (_) {
            // Teardown is best-effort; the UI is already safely out of the call.
          }
        })().whenComplete(() {
          if (identical(_ending, ending)) _ending = null;
        });
    _ending = ending;
    return ending;
  }

  /// Forward from the host's `didChangeAppLifecycleState`.
  void handleAppLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // A Live socket is billable even while the app is backgrounded and the
      // learner is muted. End it at the lifecycle boundary; resuming the app
      // must require an explicit tutor tap. This also prevents an IndexedStack
      // child or a stale route from keeping a session alive indefinitely.
      if (isLive) unawaited(_end(notify: false));
    }
  }

  /// Call from the host's own `dispose()` — does NOT call [onChanged] since
  /// the host is unmounting.
  void dispose() {
    _disposed = true;
    _manualIdleTimer?.cancel();
    _manualIdleTimer = null;
    unawaited(_end(notify: false));
  }

  String statusText({required String listeningLabel}) {
    final tutorName =
        gemini?.persona.displayName ?? ActiveTutor.current.displayName;
    if (error != null) return error!;
    if (connecting) return 'Connecting to $tutorName…';
    if (reconnecting) return 'Reconnecting…';
    if (pausedForLifecycle) return 'Paused while backgrounded';
    if (tutorSpeaking) return '$tutorName is speaking…';
    return listeningLabel;
  }
}
