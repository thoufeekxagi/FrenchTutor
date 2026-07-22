import '../../widgets/adaptive/adaptive.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/api_keys.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../data/database/learning_store.dart';
import '../../models/agent_tool.dart';
import '../../models/content_models.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../services/audio_streaming_service.dart';
import '../../prompts/live_prompts.dart';
import '../../services/gemini_live_service.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/mic_mode.dart';
import '../../services/session_recorder.dart';
import '../../utils/text_fold.dart';
import '../../utils/transcript_filter.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/ai_voice_disclosure.dart';
import '../../widgets/report_problem_button.dart';
import '../../widgets/error_notice.dart';
import '../../widgets/floating_notetaker.dart';
import '../../widgets/mic_mode_bar.dart';
import '../session/session_screen.dart' show CallStatus;
import 'agent_led_vocab_screen.dart' show VocabStageResult;

class ListeningStageResult {
  ListeningStageResult({
    required this.grammarDrillResults,
    required this.listeningCorrect,
    required this.listeningAttempted,
  });
  final List<bool> grammarDrillResults;
  final int listeningCorrect;
  final int listeningAttempted;
}

/// One segment of the passage in the session plan — straight through in the given order, one
/// card per segment, exactly like vocab's session card.
class _ReadingSessionCard {
  _ReadingSessionCard(this.segment);
  final ReadingSegment segment;
}

enum _ReadingUserIntent { again, none }

/// Daily Pathway stage 2 — rebuilt against the same rule as AgentLedVocabScreen: Marie
/// teaches, the app owns every navigation decision. Walks through a pre-built ReadingPassage
/// (either LLM-assembled once from the vocab just practiced, or mapped offline from an
/// existing lab script) one word/phrase segment at a time, the exact same way vocab walks
/// through one word at a time. This used to give the model show_conjugation/ask_drill/
/// show_question as tools it called on its own initiative, which had the same pacing/desync
/// problems vocab had before its own fix.
class AgentLedListeningScreen extends ConsumerStatefulWidget {
  const AgentLedListeningScreen({
    super.key,
    required this.passage,
    this.vocabSummary,
  });

  final ReadingPassage passage;
  final VocabStageResult? vocabSummary;

  @override
  ConsumerState<AgentLedListeningScreen> createState() =>
      _AgentLedListeningScreenState();
}

class _AgentLedListeningScreenState
    extends ConsumerState<AgentLedListeningScreen>
    with WidgetsBindingObserver {
  late GeminiLiveService _gemini;
  late AudioStreamingService _audio;
  late MicController _mic;
  MicMode _micMode = MicMode.auto;
  late LearningStore _store;
  late SessionRecorder _recorder;
  late List<_ReadingSessionCard> _sessionPlan;

  CallStatus _callStatus = CallStatus.connecting;
  int _callDuration = 0;
  Timer? _timer;
  Timer? _speakingWatchdog;
  String _errorMessage = '';
  bool _finished = false;

  DateTime _lastAudioChunkAt = DateTime.now();

  int _segmentIndex = 0;
  int _reviewedCount = 0;

  // Same live debug log as vocab's — every gate decision and detected intent, visible in
  // real time rather than a black box.
  final List<String> _debugLog = [];
  final ScrollController _debugScrollController = ScrollController();

  bool _hasAttempted = false;
  int _attemptCount = 0;
  bool _wasGraded = false;
  _ReadingUserIntent _lastDetectedIntent = _ReadingUserIntent.none;

  // Documented Gemini Live bug: dedupe identical tool calls fired in rapid succession.
  final Set<String> _handledCallIds = {};

  // Same context-aware Flash-Lite intent judge as vocabulary.
  int _utteranceSeq = 0;
  String _lastTutorLine = '';
  Timer? _announceTimer;
  DateTime _lastCardMoveAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Drift enforcement — see AgentLedVocabScreen._watchForTutorDrift for the full rationale.
  String _tutorTurnTranscript = '';
  DateTime _lastDriftCorrectionAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Transcript reveal: the scene accumulates as a scrollable conversation. Beats up to
  // this index have been reached and stay visible forever (scroll back anytime); future
  // beats stay hidden until earned — the scene isn't spoiled by reading ahead.
  int _revealedThrough = 0;
  final ScrollController _sceneScrollController = ScrollController();

  // Per-line natural-voice replay: Gemini TTS (Marie's voice family), synthesized once
  // per line and cached — tap a bubble's speaker to rehear it instantly, long-press for
  // a slow beginner-paced rendition. No round trip to the live session. Cached through
  // LessonSpeechService's shared, persisted store (not a screen-local map) so a line
  // heard in an earlier session is instant here too, instead of re-synthesizing.
  final Set<String> _ttsLoading = {};

  Future<void> _speakLine(String text, {bool slow = false}) async {
    if (text.isEmpty) return;
    final key = '$slow|$text';
    if (_ttsLoading.contains(key)) return;
    _ttsLoading.add(key);
    if (mounted) setState(() {});
    final bytes = await LessonSpeechService.shared.synthesizeWithRetry(
      text,
      voiceName: ActiveTutor.current.voiceName,
      slow: slow,
    );
    _ttsLoading.remove(key);
    if (mounted) setState(() {});
    if (bytes == null) {
      _logDebug('→ TTS failed for "$text"');
      return;
    }
    // Don't talk over Marie — cut whatever she's saying, then play the line
    // through the same 24kHz pipeline her voice uses.
    _cutTutorAudio();
    _audio.isOutputActive = true;
    await _audio.playAudioChunk(bytes);
    final playbackMs = (bytes.length / 2 / 24000 * 1000).round() + 250;
    Timer(Duration(milliseconds: playbackMs), () {
      _audio.isOutputActive = false;
    });
  }

  _ReadingSessionCard? get _currentCard =>
      _segmentIndex < _sessionPlan.length ? _sessionPlan[_segmentIndex] : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deferred to after this frame — see pathway_writing_screen.dart for why.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Listening';
    });
    _store = ref.read(learningStoreProvider);
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'reading_listening',
      topic: 'Reading & Listening',
    );
    _sessionPlan = widget.passage.segments
        .map((s) => _ReadingSessionCard(s))
        .toList();
    final context = _buildContext(
      widget.passage,
      _sessionPlan,
      widget.vocabSummary,
    );
    _gemini = GeminiLiveService(
      apiKey: ApiKeys.geminiKey,
      sessionType: LiveSessionType.listeningScene,
      lessonContext: context,
      tools: AgentTool.readingPalette,
      learningStoreForProfile: _store,
    );
    _audio = AudioStreamingService();
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
    _startCallWithConsent();
  }

  Future<void> _startCallWithConsent() async {
    final accepted = await AiVoiceDisclosure.ensureAccepted(context);
    if (!mounted) return;
    if (!accepted) {
      Navigator.of(context).maybePop();
      return;
    }
    _gemini.connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Resources only — a disposed screen must never report learning results.
    _teardown();
    _debugScrollController.dispose();
    _sceneScrollController.dispose();
    super.dispose();
  }

  /// P0.4 — same contract as SessionScreen's: mic never streams from a
  /// backgrounded app, and restarts on return unless the student muted
  /// deliberately.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_finished) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _mic.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      _mic.onAppResumed().catchError((e) {
        if (mounted) setState(() => _errorMessage = 'Mic error: $e');
      });
    }
  }

  // MARK: - Callbacks

  void _setupCallbacks() {
    _gemini.onConnected = () {
      if (!mounted) return;
      setState(() => _callStatus = CallStatus.listening);
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _callDuration += 1);
      });
      _audio.requestPermission().then((granted) async {
        if (!mounted) return;
        if (granted) {
          try {
            await _mic.onConnected();
          } catch (e) {
            setState(() => _errorMessage = 'Mic error: $e');
          }
        } else {
          setState(() => _errorMessage = 'Microphone permission denied');
        }
      });
      // The app directs from the very first turn — and the SCENE speaks first:
      // one English sentence of scene-setting, then the CHARACTER's opening
      // French line (the shopkeeper asks first, like real life), and only then
      // the coach explains and hands the student their reply. The student never
      // has to speak first.
      final first = _currentCard;
      if (first != null) {
        _direct(
          'As the COACH, in ONE short English sentence, set the scene '
          '(scenario: "${widget.passage.title}", where the student is and who you\'ll play). '
          'Then IMMEDIATELY become the CHARACTER and ${_characterLineDirection(first.segment)} '
          'Then, as the COACH in English: in one short sentence say what the character just '
          'said, give the student their reply line, "${first.segment.fr}"'
          '${first.segment.en.isEmpty ? '' : ' = "${first.segment.en}"'}, and ask them to '
          'try it.',
        );
      }
    };

    _gemini.onDisconnected = () {
      if (!_finished) {
        _errorMessage = 'Connection lost';
        _finish(completed: false, reason: 'disconnected');
      }
    };

    _gemini.onReconnecting = (attempt) {
      if (!mounted || _finished) return;
      _audio.stopPlayback();
      _audio.isOutputActive = false;
      _logDebug('→ connection lost, reconnecting (attempt $attempt)');
      setState(() {
        _callStatus = CallStatus.reconnecting;
        _errorMessage = '';
      });
    };

    _gemini.onReconnected = () {
      if (!mounted || _finished) return;
      _logDebug('→ reconnected');
      setState(() {
        if (_callStatus == CallStatus.reconnecting) {
          _callStatus = CallStatus.listening;
        }
        _errorMessage = '';
      });
      // Re-anchor the scene: re-direct the current beat/phase (or the finale beat)
      // so Marie knows exactly where the script stands even on a fresh session.
      if (_finaleBeat != null) {
        final beat = _finaleBeat!;
        if (beat < _sessionPlan.length) {
          // Re-deliver the character line the student was answering.
          _finaleBeat = beat - 1;
          _advanceFinale();
        }
      } else {
        _directCurrentPhase();
      }
    };

    _gemini.onError = (msg) {
      if (mounted) setState(() => _errorMessage = msg);
    };

    _gemini.onUserTranscript = (text) {
      // French/English only (P0.1): other-language speech is omitted entirely —
      // never displayed, never logged, never sent to the intent judge (it could
      // only misfire on it).
      if (!isFrenchEnglishTranscript(text)) {
        _logDebug('→ omitted: non-French/English speech');
        return;
      }
      _recorder.logUser(text);
      _handleUserTranscript(text);
    };

    _gemini.onTutorTranscript = (text) {
      _recorder.logTutor(text);
      _lastTutorLine = text;
    };

    _gemini.onAudioChunk = (data) {
      _lastAudioChunkAt = DateTime.now();
      _audio.isOutputActive = true;
      _audio.playAudioChunk(data);
      if (mounted && _callStatus != CallStatus.tutorSpeaking) {
        setState(() => _callStatus = CallStatus.tutorSpeaking);
      }
    };

    _gemini.onTurnComplete = () {
      _audio.isOutputActive = false;
      _tutorTurnTranscript = '';
      if (mounted && _callStatus != CallStatus.muted) {
        setState(() => _callStatus = CallStatus.listening);
      }
    };

    _gemini.onInterrupted = () {
      _audio.isOutputActive = false;
      _audio.stopPlayback();
      _tutorTurnTranscript = '';
      if (mounted && _callStatus != CallStatus.muted) {
        setState(() => _callStatus = CallStatus.listening);
      }
    };

    _gemini.onToolCall = _handleToolCall;
    _gemini.onTranscriptDelta = _watchForTutorDrift;

    _speakingWatchdog?.cancel();
    _speakingWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_callStatus == CallStatus.tutorSpeaking &&
          DateTime.now().difference(_lastAudioChunkAt).inMilliseconds > 2500) {
        _audio.isOutputActive = false;
        if (mounted) setState(() => _callStatus = CallStatus.listening);
      }
    });
  }

  // MARK: - The gate: identical shape to AgentLedVocabScreen's, walking segments instead of words

  void _handleUserTranscript(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // Deterministic echo guard (see looksLikeTutorEcho): Marie's own voice picked up by the
    // mic must never count as the student speaking — let alone as navigation consent.
    if (looksLikeTutorEcho(trimmed, _lastTutorLine) ||
        looksLikeTutorEcho(trimmed, _tutorTurnTranscript)) {
      _logDebug('→ ignored: "$trimmed" echoes Marie\'s own speech');
      return;
    }
    // No voice navigation in the roleplay: the student's speech here IS the
    // scene (their lines could legitimately contain any command phrase), so
    // moving forward is button-only — tap Next sentence.
    _hasAttempted = true;

    _utteranceSeq += 1;
    final seq = _utteranceSeq;
    final segmentIndexAtLaunch = _segmentIndex;
    final card = _currentCard;
    _logDebug('heard: "$trimmed" → judging…');

    () async {
      LiveIntentVerdict verdict;
      var source = 'judge';
      try {
        verdict = await LessonAgentService.shared.classifyLiveIntent(
          utterance: trimmed,
          cardDescription: card != null
              ? 'the student\'s line at this beat of a roleplay scene they are acting out: '
                    '"${card.segment.fr}" = "${card.segment.en}", saying this line (even '
                    'imperfectly) is them performing the scene, an attempt, never a command'
              : '(scene already finished, a finale run-through may be in progress; the '
                    'student speaking French lines is performing, not commanding)',
          tutorLastLine: _lastTutorLine,
          attemptCount: _attemptCount,
          cardPosition: _segmentIndex + 1,
          cardCount: _sessionPlan.length,
        );
      } catch (_) {
        // Judge unavailable (P1.3 noise rule): when we cannot confidently read
        // intent, NOTHING navigates — garbled bus noise must never move a card.
        // The on-screen Back/Next buttons remain the manual path.
        verdict = LiveIntentVerdict(intent: LiveNavIntent.chat);
        source = 'judge-failed-no-nav';
      }
      if (!mounted || _finished) return;
      if (seq != _utteranceSeq || segmentIndexAtLaunch != _segmentIndex) {
        _logDebug('→ stale verdict (${verdict.intent.name}) discarded');
        return;
      }
      _applyIntent(verdict, utterance: trimmed, source: source);
    }();
  }

  /// Navigation (advance/back/goto) is strictly button-only in the roleplay —
  /// Back/Next sentence are the only way to move a card, full stop; nothing
  /// spoken, however phrased, ever moves it. Only attempt/chat/again/finish
  /// are ever acted on here.
  void _applyIntent(
    LiveIntentVerdict verdict, {
    required String utterance,
    required String source,
  }) {
    _logDebug(
      '[$source] "$utterance" → ${verdict.intent.name}, attempts: $_attemptCount',
    );

    switch (verdict.intent) {
      case LiveNavIntent.attempt:
        _lastDetectedIntent = _ReadingUserIntent.none;
        _attemptCount += 1;
        // During the finale the app runs the script: each learner line the
        // student delivers advances the runner to the next character line.
        if (_finaleBeat != null) _advanceFinale();
      case LiveNavIntent.chat:
        _lastDetectedIntent = _ReadingUserIntent.none;
      case LiveNavIntent.again:
        _lastDetectedIntent = _ReadingUserIntent.again;
        // Replay the current phase: re-teach the line, or re-deliver the
        // character's side — app-directed either way.
        _cutTutorAudio();
        _directCurrentPhase();
      case LiveNavIntent.advance:
      case LiveNavIntent.back:
      case LiveNavIntent.goto:
        _logDebug('→ ignored: navigation is button-only, tap Back/Next');
      case LiveNavIntent.finish:
        // Spoken "let's finish" = the End button.
        _cutTutorAudio();
        _confirmEnd();
    }
  }

  // ---------------------------------------------------------------------------
  // The scene director: the app owns the script; Marie executes one
  // instruction per turn. All structure transitions flow through here.
  // ---------------------------------------------------------------------------

  /// Finale runner: non-null once every beat is rehearsed and the whole scene
  /// plays through. Value = the beat whose character line was just delivered;
  /// each learner attempt advances it. Deterministic — no model discretion.
  int? _finaleBeat;

  /// Sends Marie her next single-turn instruction (debounced, same as card
  /// announcements were, so rapid navigation only directs the landing state).
  void _direct(String instruction) {
    _announceTimer?.cancel();
    _announceTimer = Timer(const Duration(milliseconds: 600), () {
      if (_finished) return;
      _gemini.injectContext(
        'YOUR NEXT TURN, EXACTLY THIS AND NOTHING MORE: $instruction '
        'Then stop completely and wait for the student.',
        expectReply: true,
      );
    });
  }

  void _directCurrentPhase() {
    final card = _currentCard;
    if (card == null) return;
    _directLearn(card.segment);
  }

  /// The character's opening move for a beat: their scripted French line, or an
  /// improvised prompt when the script has no character side for this beat.
  String _characterLineDirection(ReadingSegment segment) {
    final character = segment.characterFr;
    if (character != null && character.isNotEmpty) {
      final characterMeaning = (segment.characterEn?.isNotEmpty ?? false)
          ? ' (meaning: ${segment.characterEn})'
          : '';
      return 'say exactly this French line and nothing else: "$character"$characterMeaning.';
    }
    return 'improvise ONE short, simple French line that naturally prompts the student\'s '
        'reply "${segment.fr}", and say only that.';
  }

  /// Every beat OPENS with the character's French line — the scene speaks
  /// first, coaching comes second. This order is the product: hear the
  /// shopkeeper, then learn what to say back.
  void _directLearn(ReadingSegment segment) {
    final meaning = segment.en.isEmpty ? '' : ' = "${segment.en}"';
    _direct(
      'Beat ${_segmentIndex + 1} of the scene. As the CHARACTER, '
      '${_characterLineDirection(segment)} '
      'Then, as the COACH in English: in one short sentence say what the character just '
      'said, give the student their reply line, "${segment.fr}"$meaning, and ask them '
      'to try it.',
    );
  }

  /// One tap = one whole beat: the character's line AND the student's reply
  /// line arrive together (that's what _directLearn instructs), then the
  /// next tap moves to the next beat. No second "play it again" click.
  void _advanceFromUserIntent() {
    final card = _currentCard;
    if (card == null) return;
    _cutTutorAudio();
    _logDebug('→ user-driven advance to next beat');
    _performAdvance();
    final next = _currentCard;
    if (next != null) {
      _directLearn(next.segment);
    } else {
      _wrapUp();
    }
  }

  void _goBackFromUserIntent() {
    _cutTutorAudio();
    if (_segmentIndex <= 0) return;
    _logDebug('→ user-driven go back');
    _performGoBack();
    final card = _currentCard;
    if (card != null) _directLearn(card.segment);
  }

  /// The finale runner — the app walks the whole script: character line,
  /// student's line, next character line… until the scene is done.
  void _advanceFinale() {
    final next = (_finaleBeat ?? -1) + 1;
    if (next < _sessionPlan.length) {
      _finaleBeat = next;
      _logDebug('→ finale: beat ${next + 1}/${_sessionPlan.length}');
      final segment = _sessionPlan[next].segment;
      final character = segment.characterFr;
      if (character != null && character.isNotEmpty) {
        _direct(
          'FINALE, stay in CHARACTER, no coaching: say exactly this French line and nothing '
          'else: "$character".',
        );
      } else {
        _direct(
          'FINALE, stay in CHARACTER, no coaching: say ONE short simple French line that '
          'prompts the student\'s line "${segment.fr}", and only that.',
        );
      }
    } else {
      _finaleBeat = _sessionPlan.length;
      _logDebug('→ finale complete');
      _direct(
        'The scene is complete! As the COACH, in English: congratulate the student warmly on '
        'performing a whole real French conversation, and tell them to say "finish" whenever '
        'they\'re ready to end.',
      );
    }
  }

  /// See AgentLedVocabScreen._cutTutorAudio — flushing local playback silences her instantly.
  void _cutTutorAudio() {
    // Discard the REST of her in-flight reply too (audio still streaming from the server),
    // not just what's queued locally — otherwise the user hears one second of her answering
    // the old card, a chop, then the announcement: the stutter. One clean reply instead.
    _gemini.suppressCurrentReply();
    _audio.stopPlayback();
    _audio.isOutputActive = false;
    if (mounted && _callStatus == CallStatus.tutorSpeaking) {
      setState(() => _callStatus = CallStatus.listening);
    }
  }

  /// The actual card-advance side effects (grading, index, reset) — shared by the accepted
  /// tool-call path and the direct-tap path so they can never drift apart.
  void _performAdvance() {
    if (_hasAttempted && !_wasGraded) _wasGraded = true;
    if (_currentCard != null) _reviewedCount += 1;
    _lastCardMoveAt = DateTime.now();
    setState(() {
      _segmentIndex += 1;
      if (_segmentIndex > _revealedThrough) _revealedThrough = _segmentIndex;
      _resetPerCardState();
    });
    _scrollSceneToBottom();
  }

  /// New beats appear at the bottom of the transcript — follow them.
  void _scrollSceneToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sceneScrollController.hasClients) return;
      _sceneScrollController.animateTo(
        _sceneScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  void _performGoBack() {
    _lastCardMoveAt = DateTime.now();
    setState(() {
      _segmentIndex -= 1;
      _resetPerCardState();
    });
  }

  void _handleToolCall(String name, Map<String, dynamic> args, String callId) {
    _logDebug(
      'proposed: $name($args) [segment ${_segmentIndex + 1}, attempted=$_hasAttempted, intent=${_lastDetectedIntent.name}]',
    );

    if (_handledCallIds.contains(callId)) {
      _logDebug('→ DUPLICATE call ID, ignoring side effects');
      _gemini.sendToolResponse(
        callId: callId,
        name: name,
        result: {'ok': true},
        scheduling: 'SILENT',
      );
      return;
    }
    _handledCallIds.add(callId);

    switch (name) {
      case 'mark_segment_result':
        if (_lastDetectedIntent == _ReadingUserIntent.again) {
          _logDebug('→ REJECTED (intent=again)');
          _gemini.sendToolResponse(
            callId: callId,
            name: name,
            result: {
              'ok': false,
              'reason': "The student asked to try again, don't grade yet.",
            },
          );
          return;
        }
        if (!_hasAttempted || _currentCard == null) {
          _logDebug('→ REJECTED (no attempt yet)');
          _gemini.sendToolResponse(
            callId: callId,
            name: name,
            result: {
              'ok': false,
              'reason':
                  "The student hasn't attempted this segment yet, listen for their attempt before grading.",
            },
          );
          return;
        }
        if (_wasGraded) {
          _logDebug('→ already graded this instance, acknowledging only');
          _gemini.sendToolResponse(
            callId: callId,
            name: name,
            result: {'ok': true},
            scheduling: 'SILENT',
          );
          return;
        }
        _wasGraded = true;
        _logDebug('→ ACCEPTED');
        _gemini.sendToolResponse(
          callId: callId,
          name: name,
          result: {'ok': true},
          scheduling: 'SILENT',
        );
      default:
        _logDebug('→ unknown tool $name');
        _gemini.sendToolResponse(
          callId: callId,
          name: name,
          result: {'ok': false, 'error': 'unknown tool'},
        );
    }
  }

  void _logDebug(String message) {
    final time = DateFormat.Hms().format(DateTime.now());
    setState(() {
      _debugLog.add('[$time] $message');
      if (_debugLog.length > 40) {
        _debugLog.removeRange(0, _debugLog.length - 40);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_debugScrollController.hasClients) return;
      _debugScrollController.animateTo(
        _debugScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _resetPerCardState() {
    _hasAttempted = false;
    _attemptCount = 0;
    _wasGraded = false;
    _lastDetectedIntent = _ReadingUserIntent.none;
    _handledCallIds.clear();
    // Cleared on card change so a "go back" can't false-trip the drift enforcer on
    // mentions of a segment that was legitimately current moments ago.
    _tutorTurnTranscript = '';
  }

  /// See AgentLedVocabScreen._watchForTutorDrift — same enforcer. A verbal
  /// *offer* to move on ("ready for the next?") is handled separately by
  /// `_correctIllegalOffer`; actually saying an upcoming segment's line is
  /// corrected the first time it happens, not after a repeated pattern.
  void _watchForTutorDrift(String delta) {
    if (_currentCard == null) return;
    _tutorTurnTranscript += delta;
    if (_tutorTurnTranscript.length > 1500) {
      _tutorTurnTranscript = _tutorTurnTranscript.substring(
        _tutorTurnTranscript.length - 1500,
      );
    }
    if (DateTime.now().difference(_lastDriftCorrectionAt).inMilliseconds <
        8000) {
      return;
    }
    final folded = foldFrench(_tutorTurnTranscript);
    if (DateTime.now().difference(_lastCardMoveAt).inMilliseconds > 12000) {
      const offerPhrases = [
        'next word',
        'next one',
        'move on',
        'moving on',
        'ready for the next',
        'try the next',
        'shall we continue',
        'want to continue',
        'ready to continue',
        'mot suivant',
        'passons au',
        'on passe au',
        'prochain mot',
        'next sentence',
        'next part',
        'next segment',
      ];
      if (offerPhrases.any(folded.contains)) {
        _correctIllegalOffer();
        return;
      }
    }
    for (var i = _segmentIndex + 1; i < _sessionPlan.length; i++) {
      final future = _sessionPlan[i].segment;
      final fr = foldFrench(future.fr);
      if (fr.isEmpty) continue;
      final hits = RegExp(
        '\\b${RegExp.escape(fr)}\\b',
      ).allMatches(folded).length;
      // Any single utterance of a future beat's line is corrected
      // immediately — waiting for a repeated pattern let the very first,
      // reported slip ("the agent assumed the next phrase") sail through.
      if (hits >= 1) {
        _correctTutorDrift(future);
        return;
      }
    }
  }

  /// She suggested moving on — GENTLY corrected: no audio cut (audible/wobbly), just a
  /// silent note; a reflexive "yes" to the slipped offer is refused anyway. The drift
  /// enforcer still hard-cuts real teaching-ahead.
  void _correctIllegalOffer() {
    final current = _currentCard;
    if (current == null) return;
    _lastDriftCorrectionAt = DateTime.now();
    _tutorTurnTranscript = '';
    _logDebug('→ offer slipped: silent correction, no cut');
    _gemini.injectContext(
      'You suggested moving on, never do that; the student alone decides. Do not wait for '
      'an answer to that question: continue practicing "${current.segment.fr}"  as if you had not asked.',
    );
  }

  void _correctTutorDrift(ReadingSegment future) {
    final current = _currentCard;
    if (current == null) return;
    _lastDriftCorrectionAt = DateTime.now();
    _tutorTurnTranscript = '';
    _logDebug(
      '→ DRIFT: Marie started teaching "${future.fr}" while "${current.segment.fr}" is on screen, cutting her off',
    );
    _cutTutorAudio();
    _gemini.injectContext(
      'STOP, you started teaching "${future.fr}", but the app has NOT moved on: the student\'s '
      'screen still shows "${current.segment.fr}"'
      '${current.segment.en.isEmpty ? '' : ' = "${current.segment.en}"'}, and only a tap on '
      'their own "Next sentence" button moves the segment, never anything you say. Do not '
      'mention or offer "${future.fr}" at all. Pick up "${current.segment.fr}" again now, '
      'briefly, as if nothing happened.',
      expectReply: true,
    );
  }

  /// The finale — the shareable moment: every beat is rehearsed, so now the whole scene
  /// runs start to finish in character, no coaching, the student performing for real.
  /// Deliberately NOT `_isWrappingUp` (which would end the call at the next turn
  /// boundary): the finale is a real multi-turn conversation, and the student ends it
  /// themselves by saying "finish" or tapping End — which now counts as completion since
  /// every beat has been practiced.
  bool _finaleStarted = false;

  /// Every beat is rehearsed → the app now runs the whole script start to finish.
  /// One combined first instruction (announce + first character line), then each
  /// learner attempt advances `_advanceFinale` deterministically through the script.
  void _wrapUp() {
    if (_finaleStarted) return;
    _finaleStarted = true;
    _finaleBeat = 0;
    _logDebug('→ finale: full scene run-through (app-directed)');
    final first = _sessionPlan.first.segment;
    final opener = (first.characterFr?.isNotEmpty ?? false)
        ? 'then switch to the CHARACTER and say exactly: "${first.characterFr}"'
        : 'then switch to the CHARACTER and say one short French line prompting '
              '"${first.fr}"';
    _direct(
      'As the COACH, in English, one sentence: every line is rehearsed, now we play the '
      'whole scene for real, no coaching; $opener.',
    );
  }

  void _teardown() {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    _speakingWatchdog?.cancel();
    _announceTimer?.cancel();
    _audio.stopStreaming();
    _audio.dispose();
    _gemini.disconnect();
    if (_reviewedCount > 0) {
      _store.saveDiaryEntry(
        stage: 'reading',
        summary:
            'Read through $_reviewedCount part(s) of "${widget.passage.displayTitle}" in a live reading/listening session.',
      );
    }
    _recorder.finish(
      summary: _reviewedCount > 0
          ? 'Read through $_reviewedCount part(s) of "${widget.passage.displayTitle}".'
          : 'Ended early.',
    );
  }

  /// The only exit — pops exactly once with a typed outcome; the
  /// PathwayCoordinator decides what it means for the day.
  void _finish({required bool completed, String reason = 'finished'}) {
    final alreadyDone = _finished;
    _teardown();
    if (!mounted || alreadyDone) return;
    setState(() => _callStatus = CallStatus.ended);
    final result = ListeningStageResult(
      grammarDrillResults: const [],
      listeningCorrect: _reviewedCount,
      listeningAttempted: _reviewedCount,
    );
    final outcome = completed
        ? StageOutcome.completed(result, reason: reason)
        : StageOutcome<ListeningStageResult>.paused(
            result: _reviewedCount > 0 ? result : null,
            reason: reason,
          );
    Navigator.of(context).pop(outcome);
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

  /// State-aware End, mirroring vocab's: ending after the last beat (or during the
  /// finale) IS completion — the student did the work; no quit-confirmation for that.
  Future<void> _confirmEnd() async {
    final onLastWithAttempt =
        _segmentIndex >= _sessionPlan.length - 1 && _hasAttempted;
    if (_finaleStarted ||
        _segmentIndex >= _sessionPlan.length ||
        onLastWithAttempt) {
      _finish(completed: true, reason: 'finished');
      return;
    }
    final shouldEnd = await showPSConfirmDialog(
      context,
      title: 'End this section?',
      message: "Your progress so far is saved.",
      confirmLabel: 'End',
      destructive: true,
    );
    if (shouldEnd && mounted) _finish(completed: false, reason: 'cancelled');
  }

  String _formatDuration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  Color get _statusColor {
    switch (_callStatus) {
      case CallStatus.connecting:
      case CallStatus.reconnecting:
        return DesignTokens.info;
      case CallStatus.listening:
        return DesignTokens.success;
      case CallStatus.tutorSpeaking:
        return DesignTokens.primary;
      case CallStatus.muted:
        return DesignTokens.slate;
      case CallStatus.ended:
        return DesignTokens.slate.withValues(alpha: 0.5);
    }
  }

  String get _statusText {
    switch (_callStatus) {
      case CallStatus.connecting:
        return 'connecting…';
      case CallStatus.reconnecting:
        return 'reconnecting…';
      case CallStatus.listening:
        return 'listening';
      case CallStatus.tutorSpeaking:
        return '${_gemini.persona.displayName} is speaking';
      case CallStatus.muted:
        return 'muted';
      case CallStatus.ended:
        return 'ended';
    }
  }

  @override
  Widget build(BuildContext context) {
    final notetaker = ref.watch(notetakerStateProvider);
    // Matches iOS's fullScreenCover (no swipe-to-dismiss). See session_screen.dart for why
    // canPop stays permanently false — _confirmEnd()'s own Navigator.pop() still works since
    // it's a direct pop, not a system-initiated one.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmEnd();
      },
      child: Scaffold(
        backgroundColor: DesignTokens.canvas,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: DesignTokens.contentMaxWidth,
                  ),
                  child: Column(
                    children: [
                      _header(),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _sceneScrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.screenMargin,
                            vertical: DesignTokens.space4,
                          ),
                          child: _content(),
                        ),
                      ),
                      if (_errorMessage.isNotEmpty)
                        ErrorNotice(message: _errorMessage),
                      _debugPanel(),
                      _controls(),
                    ],
                  ),
                ),
              ),
              FloatingNotetakerOverlay(state: notetaker),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'End listening practice',
                onPressed: _confirmEnd,
                icon: const Icon(
                  CupertinoIcons.xmark,
                  size: 20,
                  color: DesignTokens.ink,
                ),
              ),
              const Spacer(),
              Text(
                _formatDuration(_callDuration),
                style: DesignTokens.mono(
                  13,
                  weight: FontWeight.w500,
                ).copyWith(color: DesignTokens.slateDim),
              ),
              const Spacer(),
              SizedBox(
                width: DesignTokens.minTapTarget,
                height: DesignTokens.minTapTarget,
                child: Semantics(
                  label: _statusText,
                  child: Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              ReportProblemButton(
                sessionType: 'Listening practice',
                personaName: _gemini.persona.displayName,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          child: Column(
            children: [
              Text(
                'Reading & Listening',
                style: DesignTokens.display(20, weight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${(_segmentIndex + 1).clamp(1, _sessionPlan.isEmpty ? 1 : _sessionPlan.length)} of ${_sessionPlan.length} · $_statusText',
                    style: DesignTokens.mono(
                      11.5,
                    ).copyWith(color: DesignTokens.slateDim),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The scene as a scrollable conversation: beats accumulate as chat bubbles
  /// (character left, learner right), past beats stay re-readable forever,
  /// future beats stay hidden until earned. Every bubble carries a speaker —
  /// tap to rehear the line in Marie's voice, long-press for a slow rendition.
  Widget _content() {
    final card = _currentCard;
    final visibleThrough = _revealedThrough.clamp(0, _sessionPlan.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PasseportCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KickerText(
                'Scene · ${widget.passage.displayTitle}',
                color: DesignTokens.slateDim,
              ),
              const SizedBox(height: 4),
              Text(
                card != null
                    ? 'Line ${_segmentIndex + 1} of ${_sessionPlan.length}'
                    : _finaleStarted
                    ? 'Finale, play the whole scene through!'
                    : 'Scene complete',
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.slateDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i <= visibleThrough && i < _sessionPlan.length; i++)
          _beatBubbles(i),
        if (card == null) ...[
          const SizedBox(height: 8),
          PasseportCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  size: 30,
                  color: DesignTokens.success,
                ),
                const SizedBox(height: 10),
                Text(
                  _finaleStarted
                      ? 'Scene finale, play it through, then tap "Finish scene"!'
                      : 'All done!',
                  style: DesignTokens.body(14, weight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: PasseportPrimaryButton(
                    label: 'Finish scene',
                    icon: CupertinoIcons.arrow_right,
                    onPressed: () => _finish(completed: true),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          // Buttons are the ONLY navigation in the roleplay — no dependency
          // on speech recognition or the model.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _segmentIndex == 0 ? null : _goBackFromUserIntent,
                  icon: const Icon(CupertinoIcons.chevron_left, size: 16),
                  label: const Text('Back'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: DesignTokens.hairline),
                    foregroundColor: DesignTokens.text,
                    // Match PasseportPrimaryButton's corner radius so Back and
                    // Next read as one control pair, not two design systems.
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PasseportPrimaryButton(
                  label: 'Next sentence',
                  icon: CupertinoIcons.arrow_right,
                  onPressed: _advanceFromUserIntent,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// One beat of the transcript: the character's bubble (left), the learner's
  /// bubble (right), and — on the current beat only — the grammar/pronunciation
  /// notes tucked underneath.
  Widget _beatBubbles(int index) {
    final segment = _sessionPlan[index].segment;
    final isCurrent = index == _segmentIndex && _currentCard != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (segment.characterFr?.isNotEmpty ?? false)
            Align(
              alignment: Alignment.centerLeft,
              child: _bubble(
                fr: segment.characterFr!,
                en: segment.characterEn,
                isLearner: false,
                isCurrent: isCurrent,
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: _bubble(
              fr: segment.fr,
              en: segment.en.isEmpty ? null : segment.en,
              isLearner: true,
              isCurrent: isCurrent,
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(height: 6),
            Text(
              '${segment.grammarNote} ${segment.pronunciationTip}',
              style: DesignTokens.body(
                11.5,
              ).copyWith(color: DesignTokens.slateDim, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bubble({
    required String fr,
    String? en,
    required bool isLearner,
    required bool isCurrent,
  }) {
    final bg = isLearner ? DesignTokens.primarySoft : DesignTokens.surface;
    final frColor = isLearner ? DesignTokens.primaryDeep : DesignTokens.text;
    final loading = _ttsLoading.contains('false|$fr');
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent
              ? (isLearner ? DesignTokens.primary : DesignTokens.hairline)
              : Colors.transparent,
          width: isCurrent && isLearner ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fr,
                  style: DesignTokens.body(
                    15,
                    weight: FontWeight.w500,
                  ).copyWith(color: frColor),
                ),
                if (en != null && en.isNotEmpty)
                  Text(
                    en,
                    style: DesignTokens.body(
                      11.5,
                    ).copyWith(color: DesignTokens.slateDim),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Tap = rehear in Marie's voice (cached after first play); hold = slow.
          GestureDetector(
            onTap: () => _speakLine(fr),
            onLongPress: () => _speakLine(fr, slow: true),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      CupertinoIcons.speaker_2_fill,
                      size: 16,
                      color: isLearner
                          ? DesignTokens.primary
                          : DesignTokens.slateDim,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _debugPanel() {
    if (_debugLog.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      height: 110,
      color: DesignTokens.ink.withValues(alpha: 0.94),
      child: ListView.builder(
        controller: _debugScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        itemCount: _debugLog.length,
        itemBuilder: (context, i) => Text(
          _debugLog[i],
          style: DesignTokens.body(11).copyWith(color: DesignTokens.slateDim),
        ),
      ),
    );
  }

  Widget _controls() {
    final callActive =
        _callStatus != CallStatus.connecting &&
        _callStatus != CallStatus.reconnecting &&
        _callStatus != CallStatus.ended;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MicModeBar(
            mode: _micMode,
            isHolding: _mic.isHeld,
            enabled: callActive,
            onModeChanged: _setMicMode,
            onHoldStart: _pttDown,
            onHoldEnd: _pttUp,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 76),
              MicPrimaryButton(
                mode: _micMode,
                isHolding: _mic.isHeld,
                isMuted: _callStatus == CallStatus.muted,
                enabled: callActive,
                onAutoTap: _toggleMute,
                onHoldStart: _pttDown,
                onHoldEnd: _pttUp,
              ),
              _controlButton(
                icon: CupertinoIcons.phone_down_fill,
                label: 'End',
                color: DesignTokens.inkSoft,
                onTap: _confirmEnd,
              ),
            ],
          ),
        ],
      ),
    );
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
        child: Opacity(
          opacity: onTap == null ? 0.45 : 1,
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: DesignTokens.surface, size: 22),
              ),
              const SizedBox(height: DesignTokens.space2),
              Text(
                label,
                style: DesignTokens.body(
                  11,
                ).copyWith(color: DesignTokens.slateDim),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _buildContext(
    ReadingPassage passage,
    List<_ReadingSessionCard> plan,
    VocabStageResult? vocabSummary,
  ) {
    if (plan.isEmpty) {
      return "READING & LISTENING STAGE: no passage available today. Briefly tell the student there's nothing to read right now and that they can end the call whenever ready.";
    }
    final parts = <String>[];
    parts.add('''
ROLEPLAY SCENE STAGE, "${passage.title}". You are a DIRECTED ACTOR-COACH in a scripted scene the app runs beat by beat. The student plays themselves (the customer/visitor); you play two registers: the COACH (English, teaches, reacts, encourages) and the CHARACTER (French, the other role in the scene, one scripted line at a time).

THE CONTRACT: THE APP DIRECTS, YOU PERFORM:
1. The app sends you an instruction for your next turn ("YOUR NEXT TURN, EXACTLY THIS..."). Execute exactly that instruction, in the exact ORDER it gives, when it has several parts, then STOP COMPLETELY and wait for the student. Never add extra steps, never continue past the instruction, never decide what happens next in the scene: the app decides.
1b. THE SCENE SPEAKS FIRST: every beat opens with the CHARACTER's French line, and only AFTER it do you coach in English. Never explain a beat before the character has spoken it, the student must hear the French first, like real life. When an instruction says "as the CHARACTER ... then as the COACH", the character line always comes out of your mouth first.
2. When the student speaks and there is NO new app instruction, respond as the COACH in ONE short English sentence, react to their attempt, fix gently if needed, encourage, then stop and wait. During the finale, react in CHARACTER with one short French line instead if their line fits the scene. Moving to the next beat is a button on screen (labeled "Next sentence"), never something you tell the student to say or do — never mention it, hint at it, or remind them it exists.
3. You do NOT have the script, the app hands you each line exactly when it's time, and sometimes a hint of what's coming (marked "if asked"). Never invent lines, never say more than the single line the app asked for, never claim a learner line as yours.
4. NEVER suggest moving on or ask what's next, pacing belongs to the student and the app alone.
5. If the student freezes after a character line (long silence), whisper a rescue in English: "psst, your line is: ..." with their current line, then stop.
6. English is the coaching language; this student is a beginner. Their reciting of French lines is practice, never a cue to switch into French-led coaching.

You have exactly one tool: mark_segment_result, for recording how well the student did with the current beat (grade: again/good/easy). It's a proposal, the app only accepts it once it's confirmed the student actually attempted it. A rejection is not an error; never mention it, just keep going.
''');
    // Deliberately NO script here — Marie receives each line just-in-time from
    // the app's per-turn instructions. She cannot read ahead, spoil, or replay
    // beats she was never given; the app is the only holder of the scene.
    parts.add(
      'The scene has ${plan.length} beats. That count is all you know in advance.',
    );
    if (vocabSummary != null && vocabSummary.wordsCovered.isNotEmpty) {
      final words = vocabSummary.wordsCovered.map((e) => e.fr).join(', ');
      parts.add(
        'VOCABULARY JUST COVERED (in the previous stage, feel free to note the connection naturally if relevant): $words',
      );
    }
    return parts.join('\n\n');
  }
}
