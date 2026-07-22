import '../../widgets/adaptive/adaptive.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../data/database/learning_store.dart';
import '../../models/chat_message.dart';
import '../../flow/stage_outcome.dart';
import '../../models/session.dart';
import '../../providers/database_provider.dart';
import '../../prompts/live_prompts.dart';
import '../../utils/transcript_filter.dart';
import '../../services/audio_streaming_service.dart';
import '../../services/gemini_live_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/app_tour.dart';
import '../../services/mic_mode.dart';
import '../../services/pilot_access_service.dart';
import '../../services/referral_service.dart';
import '../../widgets/ai_voice_disclosure.dart';
import '../../widgets/error_notice.dart';
import '../../widgets/floating_notetaker.dart';
import '../../widgets/mic_mode_bar.dart';
import '../../widgets/report_problem_button.dart';
import '../../widgets/speaking_session_result.dart';

enum CallStatus {
  connecting,
  reconnecting,
  listening,
  tutorSpeaking,
  muted,
  ended,
}

/// Free-form (or context-seeded) live voice call with Marie. Ported from SessionView.swift.
/// `stage` is null for the unstructured "Just talk to Marie" call, or e.g. "speaking" for the
/// Daily Pathway's closing roleplay stage — it only affects how the saved session is tagged.
class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({
    super.key,
    required this.apiKey,
    this.lessonContext,
    this.stage,
    this.dailySessionId,
    this.examMode = false,
    this.kickoffMessage,
    this.durationLimitSeconds,
    this.wrapUpNote,
    this.wrapUpLeadSeconds = 30,
    this.popResultImmediately = false,
  });

  final String apiKey;
  final String? lessonContext;
  final String? stage;
  final bool examMode;
  final String? kickoffMessage;
  final int? durationLimitSeconds;

  /// Optional app-injected context note sent [wrapUpLeadSeconds] before the
  /// [durationLimitSeconds] cutoff, so the tutor lands the goodbye instead of
  /// being cut mid-sentence. Only meaningful with a duration limit.
  final String? wrapUpNote;
  final int wrapUpLeadSeconds;

  /// Pop with the [SpeakingResult] the moment the call ends instead of showing
  /// the standard result view — for flows (the onboarding trial) that render
  /// their own recap.
  final bool popResultImmediately;

  /// Set when this call is the Daily Pathway's speaking stage — links the
  /// ai_sessions record to today's pathway row.
  final String? dailySessionId;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen>
    with WidgetsBindingObserver {
  final List<ChatMessage> _messages = [];
  CallStatus _callStatus = CallStatus.connecting;
  String _errorMessage = '';
  bool _sessionSaved = false;
  int _callDuration = 0;
  bool _isSpeakerOn = true;

  // Real evidence for the coordinator's completion threshold (P0.3) and for
  // honest history (the old code saved startedAt == endedAt == save time).
  DateTime? _connectedAt;
  int _userUtteranceCount = 0;
  String _endedReason = 'cancelled';
  String? _aiSessionRecordId;

  Timer? _timer;
  final ScrollController _scrollController = ScrollController();

  late final GeminiLiveService _gemini;
  late final AudioStreamingService _audio;
  late final MicController _mic;
  MicMode _micMode = MicMode.auto;
  final String _sessionId = const Uuid().v4();

  bool get _isRoleplay => widget.stage == 'speaking';

  @override
  void initState() {
    super.initState();
    LessonSpeechService.shared.deactivate();
    WidgetsBinding.instance.addObserver(this);
    // Deferred to after this frame — see pathway_writing_screen.dart for why.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Speaking';
    });
    _audio = AudioStreamingService();
    _gemini = GeminiLiveService(
      apiKey: widget.apiKey,
      sessionType: widget.examMode
          ? LiveSessionType.speakingExam
          : _isRoleplay
          ? LiveSessionType.speakingRoleplay
          : LiveSessionType.freeTalk,
      lessonContext: widget.lessonContext,
      learningStoreForProfile: ref.read(learningStoreProvider),
    );
    _mic = MicController(
      startStream: () => _audio.startStreaming(onChunk: _gemini.sendAudioChunk),
      stopStream: _audio.stopStreaming,
      sendAudio: _gemini.sendAudioChunk,
    );
    MicModePrefs.load().then((saved) {
      if (!mounted) return;
      _mic.adoptSavedMode(saved);
      setState(() => _micMode = saved);
    });
    _setupCallbacks();
    _startCall();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _endCall();
    _scrollController.dispose();
    super.dispose();
  }

  /// P0.4 — phone calls, app switches, lock screen. On pause the mic stops (never
  /// stream a pocket recording); on resume it restarts unless the student had muted
  /// deliberately. If the socket died in the background, the service's auto-reconnect
  /// picks it up on its own.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_callStatus == CallStatus.ended || _sessionSaved) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _mic.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      _mic.onAppResumed().catchError((e) {
        if (mounted) setState(() => _errorMessage = 'Mic error: $e');
      });
    }
  }

  Future<void> _startCall() async {
    final accepted = await AiVoiceDisclosure.ensureAccepted(context);
    if (!mounted) return;
    if (!accepted) {
      Navigator.of(context).maybePop();
      return;
    }
    _gemini.connect();
  }

  void _endCall() {
    if (_sessionSaved) return;
    _sessionSaved = true;

    _timer?.cancel();
    _audio.stopStreaming();
    _audio.dispose();
    _gemini.disconnect();
    if (mounted) setState(() => _callStatus = CallStatus.ended);

    final recordId = _aiSessionRecordId;
    if (recordId != null) {
      final store = ref.read(learningStoreProvider);
      final usedSecondsBefore = store.aiSecondsUsedToday();
      store.endAiSession(
        recordId,
        endedReason: _endedReason,
        learnerUtteranceCount: _userUtteranceCount,
        transcriptJson: jsonEncode(
          _messages
              .map(
                (message) => {
                  'role': message.isUser ? 'user' : 'assistant',
                  'content': message.content,
                },
              )
              .toList(growable: false),
        ),
      );
      _consumeBonusMinutesIfNeeded(store, usedSecondsBefore);
    }
    _saveSessionLocally();
  }

  /// Whatever this session used beyond the base free daily allowance was
  /// drawn from the invite-code bonus balance (see referral_service.dart) —
  /// draw it down server-side to match. Fire-and-forget: worst case the
  /// balance is very slightly stale until the next successful call.
  void _consumeBonusMinutesIfNeeded(
    LearningStore store,
    int usedSecondsBefore,
  ) {
    final usedSecondsAfter = store.aiSecondsUsedToday();
    final entitlement = ref.read(pilotAccessServiceProvider).snapshot().entitlement;
    final baseLimit = PilotAccessService.baseDailyLimitSeconds(entitlement);
    final overageBefore = (usedSecondsBefore - baseLimit).clamp(
      0,
      usedSecondsBefore,
    );
    final overageAfter = (usedSecondsAfter - baseLimit).clamp(
      0,
      usedSecondsAfter,
    );
    final bonusSecondsUsed = overageAfter - overageBefore;
    if (bonusSecondsUsed > 0) {
      unawaited(ReferralService.shared.consumeBonusSeconds(bonusSecondsUsed));
    }
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    _audio.setSpeakerEnabled(_isSpeakerOn);
  }

  Future<void> _toggleMute() async {
    if (_callStatus == CallStatus.muted) {
      try {
        await _mic.setMuted(false);
        setState(() => _callStatus = CallStatus.listening);
      } catch (e) {
        setState(() => _errorMessage = 'Failed to unmute: $e');
      }
    } else {
      await _mic.setMuted(true);
      setState(() => _callStatus = CallStatus.muted);
    }
  }

  Future<void> _setMicMode(MicMode mode) async {
    await _mic.setMode(mode);
    if (!mounted) return;
    setState(() {
      _micMode = mode;
      if (_callStatus == CallStatus.muted) _callStatus = CallStatus.listening;
    });
  }

  void _pttDown() {
    _mic.pttDown();
    if (mounted) setState(() {});
  }

  void _pttUp() {
    _mic.pttUp();
    if (mounted) setState(() {});
  }

  void _setupCallbacks() {
    _gemini.onConnected = () async {
      if (!mounted) return;
      _connectedAt = DateTime.now();
      _aiSessionRecordId = ref
          .read(learningStoreProvider)
          .startAiSession(
            dailySessionId: widget.dailySessionId,
            stage: widget.stage,
            topic: widget.lessonContext != null ? 'lesson' : 'free_talk',
          );
      setState(() => _callStatus = CallStatus.listening);
      _startTimer();

      // First-call walkthrough: Auto/Hold, the mic button, and End — shown
      // once the call is actually live so every control is on screen.
      if (!await AppTour.hasSeenCall()) {
        if (mounted) AppTour.playCall(context);
      }

      final granted = await _audio.requestPermission();
      if (!mounted) return;
      if (granted) {
        try {
          await _mic.onConnected();
          // Stage-aware kickoff (P0.3): the roleplay opens IN the scene — generic
          // "what do you want to practice?" greetings broke the roleplay contract.
          _gemini.sendText(
            widget.kickoffMessage ??
                (_isRoleplay
                    ? '(Note from the app, not the student: the student just joined the '
                          'roleplay call. Open the scene NOW exactly as your role rules say, '
                          'one short English sentence to set the scene from today\'s material, '
                          'then your first line in French, in character. Do not greet '
                          'generically, do not ask what they want to practice.)'
                    : "(Le student vient de rejoindre l'appel. Salue-le chaleureusement en français et demande ce qu'il veut pratiquer aujourd'hui.)"),
          );
        } catch (e) {
          setState(() => _errorMessage = 'Mic error: $e');
        }
      } else {
        setState(() => _errorMessage = 'Microphone permission denied');
      }
    };

    // With service-level auto-reconnect (P0.4), onDisconnected now means the
    // connection is gone for good (retries exhausted) — end the call FOR the user:
    // save the transcript and show the result screen, never a dead call UI they
    // have to fight their way out of.
    _gemini.onDisconnected = () {
      if (!mounted || _sessionSaved) return;
      _endedReason = 'disconnected';
      _errorMessage = 'Connection lost';
      _endCall();
    };

    _gemini.onReconnecting = (attempt) {
      if (!mounted) return;
      // Don't play stale audio over the gap.
      _audio.stopPlayback();
      _audio.isOutputActive = false;
      setState(() {
        _callStatus = CallStatus.reconnecting;
        _errorMessage = '';
      });
    };

    _gemini.onReconnected = () {
      if (!mounted) return;
      setState(() {
        if (_callStatus != CallStatus.muted) {
          _callStatus = CallStatus.listening;
        }
        _errorMessage = '';
      });
    };

    _gemini.onError = (msg) {
      if (!mounted) return;
      setState(() => _errorMessage = msg);
    };

    _gemini.onUserTranscript = (text) {
      // French/English only (P0.1): other-language speech is omitted entirely —
      // not displayed, not saved, not counted as practice.
      if (!isFrenchEnglishTranscript(text)) return;
      _userUtteranceCount += 1;
      if (!mounted) return;
      _appendMessage(ChatMessage(role: 'user', content: text));
    };

    _gemini.onTutorTranscript = (text) {
      if (!mounted) return;
      _appendMessage(ChatMessage(role: 'tutor', content: text));
    };

    _gemini.onAudioChunk = (audioData) {
      _audio.isOutputActive = true;
      _audio.playAudioChunk(audioData);
      if (mounted && _callStatus != CallStatus.tutorSpeaking) {
        setState(() => _callStatus = CallStatus.tutorSpeaking);
      }
    };

    _gemini.onTurnComplete = () {
      _audio.isOutputActive = false;
      // A mute pressed while the tutor was mid-turn must stick — this fires
      // a few seconds later, whenever that turn happens to finish, and was
      // unconditionally overwriting the user's mute back to "listening"
      // without them touching anything.
      if (mounted && _callStatus != CallStatus.muted) {
        setState(() => _callStatus = CallStatus.listening);
      }
    };

    _gemini.onInterrupted = () {
      _audio.isOutputActive = false;
      _audio.stopPlayback();
      if (mounted && _callStatus != CallStatus.muted) {
        setState(() => _callStatus = CallStatus.listening);
      }
    };
  }

  void _appendMessage(ChatMessage message) {
    setState(() => _messages.add(message));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _callDuration += 1);
      final limit = widget.durationLimitSeconds;
      if (limit == null) return;
      final note = widget.wrapUpNote;
      if (note != null && _callDuration == limit - widget.wrapUpLeadSeconds) {
        _gemini.sendText(note);
      }
      if (_callDuration >= limit) {
        _endedReason = 'completed';
        _endCall();
      }
    });
  }

  void _saveSessionLocally() {
    final now = DateTime.now();
    final summary = _generateLocalSummary();

    final session = Session(
      id: _sessionId,
      startedAt:
          (_connectedAt ?? now.subtract(Duration(seconds: _callDuration)))
              .toIso8601String(),
      endedAt: now.toIso8601String(),
      summary: summary,
      stage: widget.stage,
    );
    final storage = ref.read(storageServiceProvider);
    storage.saveSession(session);
    for (final msg in _messages) {
      storage.saveMessage(
        sessionId: _sessionId,
        role: msg.isUser ? 'user' : 'assistant',
        content: msg.content,
      );
    }

    if (_callDuration >= 45) {
      ref
          .read(learningStoreProvider)
          .markHabit(
            'speaking',
            minutes: (_callDuration / 60).clamp(1, 999).round(),
          );
    }
  }

  SpeakingResult get _result => SpeakingResult(
    connected: _connectedAt != null,
    durationSeconds: _callDuration,
    learnerUtteranceCount: _userUtteranceCount,
    endedReason: _endedReason,
    frenchWordsUsed: _learnerFrenchWords(),
  );

  /// Known French words the LEARNER actually said, for the trial recap.
  /// Elisions are split ("m'appelle" → "appelle") and 1-letter matches are
  /// dropped — 'a' is also an English word and reads as noise on a recap.
  List<String> _learnerFrenchWords() {
    final words = <String>{};
    for (final message in _messages.where((m) => m.isUser)) {
      for (var word in message.content.toLowerCase().split(
        RegExp(r"[^a-zà-ÿ']+"),
      )) {
        final apostrophe = word.indexOf("'");
        if (apostrophe >= 0) word = word.substring(apostrophe + 1);
        if (word.length >= 2 && _frenchKeywords.contains(word)) words.add(word);
      }
    }
    return words.toList()..sort();
  }

  void _finishResult() => Navigator.of(context).pop(_result);

  String _generateLocalSummary() {
    if (_messages.isEmpty) return 'No conversation recorded.';

    final userMessages = _messages.where((m) => m.isUser).length;
    final tutorMessages = _messages.where((m) => !m.isUser).length;
    final duration = _formatDuration(_callDuration);

    var summary = 'Session lasted $duration. ';
    summary +=
        '$userMessages exchanges from you, $tutorMessages responses from tutor. ';

    final allText = _messages.map((m) => m.content).join(' ').toLowerCase();
    final words = allText.split(' ').toSet();
    final frenchUsed = words.intersection(_frenchKeywords).toList()..sort();
    if (frenchUsed.isNotEmpty) {
      summary += 'French words used: ${frenchUsed.take(10).join(', ')}. ';
    }

    summary += userMessages > 3
        ? 'Good practice session, keep going!'
        : 'Try speaking more next time for better practice.';
    return summary;
  }

  static const _frenchKeywords = {
    'bonjour',
    'merci',
    'oui',
    'non',
    'je',
    'vous',
    'le',
    'la',
    'les',
    'comment',
    'avec',
    'pour',
    'suis',
    'appelle',
    'salut',
    'ça',
    'va',
    'très',
    'bien',
    'mal',
    'aussi',
    'mais',
    'et',
    'ou',
    'ne',
    'pas',
    'ai',
    'as',
    'a',
    'avons',
    'avez',
    'ont',
    'sont',
    'être',
    'avoir',
    'aller',
    'faire',
    'dire',
    'voir',
    'savoir',
    'pouvoir',
    'vouloir',
    'devoir',
    'falloir',
    'venir',
    'prendre',
    'donner',
    'parler',
    'écouter',
    'regarder',
    'aimer',
    'manger',
    'boire',
    'acheter',
    'vendre',
    'habiter',
    'travailler',
    'étudier',
    'apprendre',
    'comprendre',
    'répéter',
    'corriger',
    'expliquer',
    'traduire',
    // Trial-lesson goodbye ("au revoir") — recap needs it to register.
    'revoir',
  };

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Color get _statusColor {
    switch (_callStatus) {
      case CallStatus.connecting:
      case CallStatus.reconnecting:
        return Passeport.brass;
      case CallStatus.listening:
        return Passeport.sage;
      case CallStatus.tutorSpeaking:
        return Passeport.sky;
      case CallStatus.muted:
        return Passeport.slate;
      case CallStatus.ended:
        return Passeport.slate.withValues(alpha: 0.5);
    }
  }

  String get _statusText {
    switch (_callStatus) {
      case CallStatus.connecting:
        return 'Connecting…';
      case CallStatus.reconnecting:
        return 'Reconnecting…';
      case CallStatus.listening:
        return 'Listening. Speak in French';
      case CallStatus.tutorSpeaking:
        return '${_gemini.persona.displayName} is speaking…';
      case CallStatus.muted:
        return 'Microphone muted';
      case CallStatus.ended:
        return 'Call ended';
    }
  }

  Future<void> _confirmEnd() async {
    final shouldEnd = await showPSConfirmDialog(
      context,
      title: 'End Call?',
      message: "Your session transcript and summary will be saved.",
      confirmLabel: 'End Call',
      destructive: true,
    );
    if (shouldEnd) {
      _endedReason = 'completed';
      _endCall();
    }
  }

  bool _poppedResult = false;

  @override
  Widget build(BuildContext context) {
    if (_callStatus == CallStatus.ended && _sessionSaved) {
      if (widget.popResultImmediately) {
        // The hosting flow (onboarding trial) renders its own recap — hand the
        // result straight back. Post-frame: popping during build is illegal.
        if (!_poppedResult) {
          _poppedResult = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _finishResult();
          });
        }
        return const Scaffold(
          backgroundColor: Passeport.parchment,
          body: SizedBox.expand(),
        );
      }
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _finishResult();
        },
        child: SpeakingSessionResultView(
          durationSeconds: _callDuration,
          learnerTurns: _userUtteranceCount,
          meetsCompletionThreshold: _result.meetsThreshold,
          isDailyPath: widget.stage == 'speaking',
          onDone: _finishResult,
        ),
      );
    }
    final notetaker = ref.watch(notetakerStateProvider);
    // Matches iOS's fullScreenCover, which has no swipe-to-dismiss gesture at all — without
    // this, Flutter's iOS edge-swipe-back gesture (still active even on a fullscreenDialog
    // MaterialPageRoute) can silently end the call, bypassing the "End Call?" confirmation
    // entirely. canPop stays false permanently: the confirmation dialog's own Navigator.pop()
    // call bypasses canPop since it's a direct pop, not a system-initiated one, so confirming
    // still works normally.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmEnd();
      },
      child: Scaffold(
        backgroundColor: Passeport.parchment,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _callHeader(),
                  Expanded(child: _transcriptView()),
                  if (_errorMessage.isNotEmpty)
                    ErrorNotice(message: _errorMessage),
                  _callControls(),
                ],
              ),
              FloatingNotetakerOverlay(state: notetaker),
            ],
          ),
        ),
      ),
    );
  }

  Widget _callHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: 'End session',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _confirmEnd,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      CupertinoIcons.xmark,
                      size: 20,
                      color: Passeport.ink,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                widget.durationLimitSeconds == null
                    ? _formatDuration(_callDuration)
                    : _formatDuration(
                        (widget.durationLimitSeconds! - _callDuration).clamp(
                          0,
                          widget.durationLimitSeconds!,
                        ),
                      ),
                style: Passeport.body(14, weight: FontWeight.w700).copyWith(
                  color: Passeport.slateDim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              ReportProblemButton(
                sessionType: widget.stage ?? 'Free talk',
                personaName: _gemini.persona.displayName,
              ),
            ],
          ),
          const SizedBox(height: 4),
          _avatarWithCountdownRing(),
          const SizedBox(height: 9),
          Text(_gemini.persona.displayName, style: Passeport.display(22)),
          const SizedBox(height: 7),
          AnimatedContainer(
            duration: DesignTokens.durationFast,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  _statusText,
                  style: Passeport.body(
                    12,
                    weight: FontWeight.w600,
                  ).copyWith(color: Passeport.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The tutor avatar. On time-limited calls (trial, exam) a live ring drains
  /// around it — calm in the app's primary color, warning-tinted for the final
  /// stretch — so the limit is always visible without reading the clock.
  Widget _avatarWithCountdownRing() {
    final limit = widget.durationLimitSeconds;
    final avatar = Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: Passeport.infoSoft,
        shape: BoxShape.circle,
        border: Border.all(
          color: _statusColor.withValues(alpha: 0.32),
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          _gemini.persona.initial,
          style: const TextStyle(
            color: Passeport.sky,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    if (limit == null) return avatar;
    final remaining = (limit - _callDuration).clamp(0, limit);
    final closing = remaining <= widget.wrapUpLeadSeconds;
    return SizedBox(
      width: 66,
      height: 66,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(seconds: 1),
            curve: Curves.linear,
            tween: Tween(end: remaining / limit),
            builder: (context, value, _) => SizedBox(
              width: 66,
              height: 66,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
                color: closing ? Passeport.warning : Passeport.primary,
                backgroundColor: Passeport.hairline,
              ),
            ),
          ),
          avatar,
        ],
      ),
    );
  }

  Widget _transcriptView() {
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: Passeport.successSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.waveform,
                  size: 24,
                  color: Passeport.sage,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _callStatus == CallStatus.connecting
                    ? 'Preparing your session'
                    : '${_gemini.persona.displayName} is listening',
                textAlign: TextAlign.center,
                style: Passeport.body(16, weight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _callStatus == CallStatus.connecting
                    ? 'This usually takes a moment.'
                    : 'Speak naturally. You can pause, correct yourself, or ask for help.',
                textAlign: TextAlign.center,
                style: Passeport.body(
                  13.5,
                ).copyWith(color: Passeport.slateDim, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _MessageBubble(message: _messages[index]),
      ),
    );
  }

  Widget _callControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: Passeport.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Passeport.ink.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(
            key: AppTour.micModeKey,
            child: MicModeBar(
              mode: _micMode,
              isHolding: _mic.isHeld,
              enabled:
                  _callStatus != CallStatus.connecting &&
                  _callStatus != CallStatus.reconnecting &&
                  _callStatus != CallStatus.ended,
              onModeChanged: _setMicMode,
              onHoldStart: _pttDown,
              onHoldEnd: _pttUp,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _controlButton(
                icon: _isSpeakerOn
                    ? CupertinoIcons.speaker_2_fill
                    : CupertinoIcons.ear,
                label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                color: Passeport.ink,
                onTap: _callStatus == CallStatus.connecting
                    ? null
                    : _toggleSpeaker,
              ),
              KeyedSubtree(
                key: AppTour.micButtonKey,
                child: MicPrimaryButton(
                  mode: _micMode,
                  isHolding: _mic.isHeld,
                  isMuted: _callStatus == CallStatus.muted,
                  enabled:
                      _callStatus != CallStatus.connecting &&
                      _callStatus != CallStatus.reconnecting &&
                      _callStatus != CallStatus.ended,
                  onAutoTap: _toggleMute,
                  onHoldStart: _pttDown,
                  onHoldEnd: _pttUp,
                ),
              ),
              KeyedSubtree(
                key: AppTour.endCallKey,
                child: _controlButton(
                  icon: CupertinoIcons.phone_down_fill,
                  label: 'End',
                  color: Passeport.maroon,
                  onTap: _confirmEnd,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              AnimatedContainer(
                duration: DesignTokens.durationFast,
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: onTap == null
                      ? Passeport.slate.withValues(alpha: 0.35)
                      : color,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 23),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                style: Passeport.body(
                  11.5,
                  weight: FontWeight.w600,
                ).copyWith(color: Passeport.slateDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Row(
      mainAxisAlignment: isUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser) _avatar(false),
        if (!isUser) const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: isUser ? Passeport.ink : Passeport.infoSoft,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
            ),
            child: Text(
              message.content,
              style: Passeport.body(14).copyWith(
                color: isUser ? Colors.white : Passeport.text,
                height: 1.35,
              ),
            ),
          ),
        ),
        if (isUser) const SizedBox(width: 8),
        if (isUser) _avatar(true),
      ],
    );
  }

  Widget _avatar(bool isUser) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: (isUser ? Passeport.maroon : Passeport.brass).withValues(
          alpha: 0.15,
        ),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isUser ? CupertinoIcons.person_fill : CupertinoIcons.book_fill,
        size: 14,
        color: isUser ? Passeport.maroon : Passeport.brass,
      ),
    );
  }
}
