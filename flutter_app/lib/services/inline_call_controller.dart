import 'dart:async';

import 'package:flutter/widgets.dart';

import '../config/api_keys.dart';
import '../data/database/learning_store.dart';
import '../models/tutor_persona.dart';
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

  GeminiLiveService? gemini;
  AudioStreamingService? audio;
  bool connecting = false;
  bool active = false;
  bool muted = false;
  bool tutorSpeaking = false;
  bool reconnecting = false;

  // P0.4 pocket/lock-screen handling (same contract as SessionScreen): the
  // mic stream stops on pause so a pocket never gets recorded and sent, and
  // resumes on foreground — but only if the student hadn't muted on
  // purpose, so backgrounding never silently un-mutes them.
  bool pausedForLifecycle = false;

  String? error;
  String? lastTutorLine;

  bool get isLive => active || connecting;

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
  Future<void> start(
    BuildContext context, {
    bool sendOpeningPrompt = true,
  }) async {
    final accepted = await AiVoiceDisclosure.ensureAccepted(context);
    if (!accepted) return;
    LessonSpeechService.shared.deactivate();
    connecting = true;
    error = null;
    lastTutorLine = null;
    onChanged();
    final connected = await _connect();
    if (!connected) {
      connecting = false;
      error = "Couldn't connect. Check your connection and try again.";
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
    await audio!.startStreaming(onChunk: gemini!.sendAudioChunk);
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
      if (!completer.isCompleted) {
        completer.complete(false);
        return;
      }
      error = msg;
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
    };

    g.connect();
    final connected = await completer.future.timeout(
      const Duration(seconds: 6),
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

  /// Gives the live helper an app-owned coaching instruction. This is kept
  /// separate from [sendText] so a scripted lesson never treats its own
  /// current prompt as learner input.
  void promptTutor(String instruction) {
    final trimmed = instruction.trim();
    if (!isLive || trimmed.isEmpty) return;
    gemini?.injectContext(trimmed, expectReply: true);
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

  Future<void> end() async {
    audio?.stopStreaming();
    audio?.dispose();
    gemini?.disconnect();
    audio = null;
    gemini = null;
    active = false;
    connecting = false;
    muted = false;
    tutorSpeaking = false;
    reconnecting = false;
    pausedForLifecycle = false;
    onChanged();
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
    audio?.stopStreaming();
    audio?.dispose();
    gemini?.disconnect();
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
