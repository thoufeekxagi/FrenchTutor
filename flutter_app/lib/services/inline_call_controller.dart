import 'dart:async';

import 'package:flutter/widgets.dart';

import '../config/api_keys.dart';
import '../data/database/learning_store.dart';
import '../models/tutor_persona.dart';
import '../models/agent_tool.dart';
import '../prompts/live_prompts.dart';
import '../widgets/ai_voice_disclosure.dart';
import 'audio_streaming_service.dart';
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

  GeminiLiveService? gemini;
  AudioStreamingService? audio;
  bool connecting = false;
  bool active = false;
  bool muted = false;
  bool tutorSpeaking = false;
  bool reconnecting = false;
  Future<void>? _ending;
  Future<void>? _starting;
  bool _disposed = false;

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
    // Ending a live call closes native recorder/player handles asynchronously.
    // Wait for that teardown before opening narration or a new call, otherwise
    // the old tutor stream can bleed into the next lesson audio.
    final ending = _ending;
    if (ending != null) await ending;
    if (_disposed || !context.mounted) return;
    final accepted = await AiVoiceDisclosure.ensureAccepted(context);
    if (!accepted) return;
    // Narration and the inline call share the iOS audio session. This must be
    // awaited so a queued narration clip cannot race the call's first turn.
    await LessonSpeechService.shared.deactivate();
    if (_disposed) return;
    connecting = true;
    error = null;
    lastTutorLine = null;
    onChanged();
    final connected = await _connect();
    if (!connected) {
      connecting = false;
      error ??= "Couldn't connect. Check your connection and try again.";
      onChanged();
      return;
    }
    final granted = await audio!.requestPermission();
    if (!granted) {
      connecting = false;
      error = 'Microphone permission denied';
      gemini?.disconnect();
      gemini = null;
      onChanged();
      return;
    }
    if (manualLearnerTurns) {
      // Do not open the learner microphone for the idle/opening-prompt phase.
      // Guided speaking opens it only from startLearnerTurn(), after the user
      // taps Record. Gemini's output player is lazy and starts when Marie's
      // first audio chunk arrives.
      muted = true;
      onChanged();
    } else {
      await audio!.startStreaming(onChunk: gemini!.sendAudioChunk);
    }
    connecting = false;
    active = true;
    onChanged();
    final prompt = sendOpeningPrompt ? openingPrompt?.trim() : null;
    if (prompt != null && prompt.isNotEmpty) {
      gemini?.injectContext(prompt, expectReply: true);
    }
  }

  Future<bool> _connect() async {
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
      tools: tools,
    );
    audio = a;
    gemini = g;

    g.onConnected = () {
      if (!completer.isCompleted) completer.complete(true);
    };
    g.onReconnecting = (_) {
      a.stopPlayback();
      a.isOutputActive = false;
      reconnecting = true;
      error = null;
      onChanged();
    };
    g.onReconnected = () {
      reconnecting = false;
      onChanged();
    };
    g.onError = (msg) {
      error = msg;
      if (!completer.isCompleted) {
        completer.complete(false);
        return;
      }
      onChanged();
    };
    g.onDisconnected = () {
      if (!completer.isCompleted) {
        completer.complete(false);
        return;
      }
      active = false;
      reconnecting = false;
      onChanged();
    };
    g.onUserTranscript = (text) {
      onUserTranscript?.call(text);
    };
    g.onTutorTranscript = (text) {
      lastTutorLine = text;
      onChanged();
      onTutorTranscript?.call(text);
    };
    g.onAudioChunk = (bytes) {
      a.isOutputActive = true;
      tutorSpeaking = true;
      a.playAudioChunk(bytes);
    };
    g.onTurnComplete = () {
      a.isOutputActive = false;
      tutorSpeaking = false;
      onChanged();
      onTurnComplete?.call();
    };
    g.onToolCall = onToolCall;

    g.connect();
    // Token minting may use the full 10-second server timeout before the
    // Live socket sends setupComplete. Do not report a false connection error
    // while the proven legacy transport is still starting.
    final connected = await completer.future.timeout(
      const Duration(seconds: 22),
      onTimeout: () => false,
    );
    if (!connected) {
      g.disconnect();
      await a.dispose();
      gemini = null;
      audio = null;
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

  /// Refreshes the host screen's lesson context without opening a tutor turn.
  /// Scripted hosts call this when the learner advances to a new card while a
  /// call remains active. Marie absorbs the new context silently and only
  /// speaks again when the learner asks or starts a turn.
  void updateLessonContext() {
    if (!isLive) return;
    gemini?.injectContext(lessonContext(), expectReply: false);
  }

  Future<bool> startLearnerTurn() async {
    if (!isReadyForLearnerTurn || gemini == null || audio == null) {
      return false;
    }
    gemini!.beginAudioTurn();
    if (muted) {
      muted = false;
      onChanged();
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
    onChanged();
  }

  Future<void> toggleMute() async {
    if (audio == null) return;
    if (muted) {
      muted = false;
      onChanged();
      await audio!.startStreaming(onChunk: gemini!.sendAudioChunk);
    } else {
      await audio!.stopStreaming();
      muted = true;
      onChanged();
    }
  }

  Future<void> end() => _end(notify: true);

  Future<void> _end({required bool notify}) {
    final existing = _ending;
    if (existing != null) return existing;

    final currentAudio = audio;
    final currentGemini = gemini;
    audio = null;
    gemini = null;
    active = false;
    connecting = false;
    muted = false;
    tutorSpeaking = false;
    reconnecting = false;
    pausedForLifecycle = false;
    if (notify) onChanged();

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
    if (!active) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!muted) {
        audio?.stopPlayback();
        audio?.isOutputActive = false;
        audio?.stopStreaming();
        pausedForLifecycle = true;
      }
    } else if (state == AppLifecycleState.resumed) {
      if (pausedForLifecycle && !muted && audio != null && gemini != null) {
        pausedForLifecycle = false;
        audio!.startStreaming(onChunk: gemini!.sendAudioChunk);
      }
    }
  }

  /// Call from the host's own `dispose()` — does NOT call [onChanged] since
  /// the host is unmounting.
  void dispose() {
    _disposed = true;
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
