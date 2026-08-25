import 'dart:async';

import 'package:flutter/widgets.dart';

import '../config/api_keys.dart';
import '../data/database/learning_store.dart';
import '../models/agent_tool.dart';
import '../prompts/live_prompts.dart';
import '../widgets/ai_voice_disclosure.dart';
import 'audio_streaming_service.dart';
import 'gemini_live_service.dart';
import 'lesson_speech_service.dart';

/// The three speaking surfaces share the same explicit learner-turn contract,
/// but keep their own Live session identity and prompt/tool palette.
enum SpeakingLiveSessionMode { guided, freeTalk, roleplay }

/// Dedicated Live transport for speaking lessons.
///
/// This controller intentionally does not use automatic voice activity
/// detection. The speaking screen owns the learner boundary:
///
///   Record -> activityStart + microphone stream
///   Stop   -> activityEnd + microphone stream closed
///
/// Marie may open the lesson and speak her prompt, but she cannot receive idle
/// microphone audio or answer until the learner explicitly records and stops.
class SpeakingLiveSessionController {
  SpeakingLiveSessionController({
    required this.mode,
    required this.lessonContext,
    required this.learningStoreForProfile,
    required this.onChanged,
    required this.onUserTranscript,
    required this.onTutorTranscript,
    required this.onTurnComplete,
    required this.onToolCall,
    this.openingPrompt,
    this.tools = const [],
  });

  final SpeakingLiveSessionMode mode;
  final String Function() lessonContext;
  final LearningStore learningStoreForProfile;
  final VoidCallback onChanged;
  final void Function(String text) onUserTranscript;
  final void Function(String text) onTutorTranscript;
  final VoidCallback onTurnComplete;
  final void Function(String name, Map<String, dynamic> args, String callId)
  onToolCall;
  final String? openingPrompt;
  final List<AgentTool> tools;

  GeminiLiveService? _gemini;
  AudioStreamingService? _audio;
  bool connecting = false;
  bool active = false;
  bool muted = true;
  bool tutorSpeaking = false;
  bool reconnecting = false;
  bool _learnerTurnOpen = false;

  String? error;
  String? lastTutorLine;

  bool get isLive => active || connecting;

  LiveSessionType get _liveSessionType => switch (mode) {
    SpeakingLiveSessionMode.freeTalk => LiveSessionType.freeTalk,
    SpeakingLiveSessionMode.guided => LiveSessionType.speakingGuided,
    SpeakingLiveSessionMode.roleplay => LiveSessionType.speakingRoleplay,
  };

  Future<void> start(
    BuildContext context, {
    bool sendOpeningPrompt = true,
  }) async {
    if (isLive) return;
    final accepted = await AiVoiceDisclosure.ensureAccepted(context);
    if (!accepted) return;

    await LessonSpeechService.shared.deactivate();
    connecting = true;
    error = null;
    lastTutorLine = null;
    onChanged();

    final connected = await _connect();
    if (!connected) {
      connecting = false;
      error ??= "Couldn't connect to the tutor. Please try again.";
      onChanged();
      return;
    }

    final granted = await _audio!.requestPermission();
    if (!granted) {
      connecting = false;
      error = 'Microphone permission denied';
      _closeTransport();
      onChanged();
      return;
    }

    // Keep the microphone closed. The output player is lazy and starts when
    // Gemini sends Marie's first audio chunk.
    muted = true;
    connecting = false;
    active = true;
    onChanged();

    final prompt = sendOpeningPrompt ? openingPrompt?.trim() : null;
    if (prompt != null && prompt.isNotEmpty) {
      _gemini!.injectContext(prompt, expectReply: true);
    }
  }

  Future<bool> _connect() async {
    final completer = Completer<bool>();
    final audio = AudioStreamingService();
    final gemini = GeminiLiveService(
      apiKey: ApiKeys.geminiKey,
      sessionType: _liveSessionType,
      lessonContext: lessonContext(),
      learningStoreForProfile: learningStoreForProfile,
      // This is the key contract: Gemini's server-side VAD is disabled for
      // every dedicated speaking session.
      manualActivityBoundaries: true,
      deferUserTranscriptUntilTurnComplete: true,
      tools: tools,
    );
    _audio = audio;
    _gemini = gemini;

    gemini.onConnected = () {
      if (!completer.isCompleted) completer.complete(true);
    };
    gemini.onReconnecting = (_) {
      reconnecting = true;
      error = null;
      audio.stopPlayback();
      audio.isOutputActive = false;
      onChanged();
    };
    gemini.onReconnected = () {
      reconnecting = false;
      // A reconnect never opens the learner microphone. If a turn was active,
      // the learner must tap Record again rather than sending a partial turn.
      if (_learnerTurnOpen) {
        _learnerTurnOpen = false;
        muted = true;
      }
      onChanged();
    };
    gemini.onError = (message) {
      error = message;
      if (!completer.isCompleted) {
        completer.complete(false);
      } else {
        onChanged();
      }
    };
    gemini.onDisconnected = () {
      if (!completer.isCompleted) {
        completer.complete(false);
        return;
      }
      active = false;
      reconnecting = false;
      if (!_learnerTurnOpen) muted = true;
      onChanged();
    };
    gemini.onUserTranscript = onUserTranscript;
    gemini.onTutorTranscript = (text) {
      lastTutorLine = text;
      onTutorTranscript(text);
      onChanged();
    };
    gemini.onAudioChunk = (bytes) {
      audio.isOutputActive = true;
      tutorSpeaking = true;
      audio.playAudioChunk(bytes);
    };
    gemini.onTurnComplete = () {
      audio.isOutputActive = false;
      tutorSpeaking = false;
      onTurnComplete();
      onChanged();
    };
    gemini.onToolCall = onToolCall;

    unawaited(gemini.connect());
    // Token minting allows 10 seconds and Gemini setup has its own 10-second
    // guard. The old generic controller timed out after 6 seconds, producing
    // a false connection error while startup was still in progress.
    final connected = await completer.future.timeout(
      const Duration(seconds: 22),
      onTimeout: () => false,
    );
    if (!connected) {
      _closeTransport();
    }
    return connected;
  }

  Future<void> startLearnerTurn() async {
    if (!isLive || _gemini == null || _audio == null || _learnerTurnOpen) {
      return;
    }
    _learnerTurnOpen = true;
    muted = false;
    _gemini!.beginAudioTurn();
    onChanged();
    try {
      await _audio!.startStreaming(onChunk: _gemini!.sendAudioChunk);
    } catch (exception) {
      _gemini!.endAudioTurn();
      _learnerTurnOpen = false;
      muted = true;
      error = 'Microphone could not start: $exception';
      onChanged();
    }
  }

  Future<void> endLearnerTurn() async {
    if (!isLive || _gemini == null || _audio == null || !_learnerTurnOpen) {
      return;
    }
    // Close the server turn before stopping the recorder so the final PCM
    // frames remain inside the same Gemini Live activity.
    _gemini!.endAudioTurn();
    _learnerTurnOpen = false;
    await _audio!.stopStreaming();
    muted = true;
    onChanged();
  }

  void promptTutor(String instruction) {
    if (!isLive || instruction.trim().isEmpty) return;
    _gemini!.queueSpokenContext(instruction.trim());
  }

  void sendToolResponse({
    required String callId,
    required String name,
    required Map<String, dynamic> result,
    String? scheduling,
  }) {
    _gemini?.sendToolResponse(
      callId: callId,
      name: name,
      result: result,
      scheduling: scheduling,
    );
  }

  Future<void> end() async {
    _learnerTurnOpen = false;
    muted = true;
    await _audio?.stopStreaming();
    _closeTransport();
    onChanged();
  }

  void handleAppLifecycle(AppLifecycleState state) {
    if (!active) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_learnerTurnOpen) unawaited(endLearnerTurn());
      _audio?.stopPlayback();
      _audio?.isOutputActive = false;
    }
  }

  void dispose() {
    _learnerTurnOpen = false;
    muted = true;
    _closeTransport();
  }

  void _closeTransport() {
    _audio?.stopStreaming();
    _audio?.dispose();
    _gemini?.disconnect();
    _audio = null;
    _gemini = null;
    active = false;
    connecting = false;
    tutorSpeaking = false;
    reconnecting = false;
  }
}
