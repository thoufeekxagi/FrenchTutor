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
import '../../providers/database_provider.dart';
import '../../services/audio_streaming_service.dart';
import '../../prompts/live_prompts.dart';
import '../../services/gemini_live_service.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/mic_mode.dart';
import '../../services/session_recorder.dart';
import '../../utils/text_fold.dart';
import '../../utils/transcript_filter.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/floating_notetaker.dart';
import '../../widgets/mic_mode_bar.dart';
import '../session/session_screen.dart' show CallStatus;
import 'agent_led_vocab_screen.dart' show VocabStageResult;

class GrammarStageResult {
  GrammarStageResult({required this.topicTitle, required this.drillResults});
  final String topicTitle;
  final List<bool> drillResults;
}

/// One generated sentence in the session plan — straight through in the given order, no
/// interleaved repeats, exactly like vocab's session card.
class _GrammarSessionCard {
  _GrammarSessionCard(this.card);
  final GrammarPracticeCard card;
}

enum _GrammarUserIntent { advance, again, back, none }

/// Daily Pathway stage 2 — one chosen tense/topic, walked through EXACTLY the way
/// AgentLedVocabScreen walks through vocab: one generated sentence card at a time (front =
/// English meaning, back = the French sentence, a one-line grammar note where vocab shows
/// phonetics), app-owned step index, deterministic intent detection, Back/Next buttons wired
/// to the same functions as voice, a single judgment-only tool. Cards are generated ONCE
/// before the session starts (informed by the vocab words + transcript from the Vocab stage
/// that just happened) — nothing invented live by the model.
class AgentLedGrammarScreen extends ConsumerStatefulWidget {
  const AgentLedGrammarScreen({
    super.key,
    required this.cards,
    required this.tenseTitle,
    this.focusNote,
    this.vocabSummary,
  });

  final List<GrammarPracticeCard> cards;
  final String tenseTitle;
  final String? focusNote;
  final VocabStageResult? vocabSummary;

  @override
  ConsumerState<AgentLedGrammarScreen> createState() =>
      _AgentLedGrammarScreenState();
}

class _AgentLedGrammarScreenState extends ConsumerState<AgentLedGrammarScreen>
    with WidgetsBindingObserver {
  late GeminiLiveService _gemini;
  late AudioStreamingService _audio;
  late MicController _mic;
  MicMode _micMode = MicMode.auto;
  late LearningStore _store;
  late SessionRecorder _recorder;
  late List<_GrammarSessionCard> _sessionPlan;
  late String _topicId;

  CallStatus _callStatus = CallStatus.connecting;
  int _callDuration = 0;
  Timer? _timer;
  Timer? _speakingWatchdog;
  String _errorMessage = '';
  bool _finished = false;
  bool _isWrappingUp = false;

  DateTime _lastAudioChunkAt = DateTime.now();

  int _cardIndex = 0;
  final List<bool> _drillResults = [];

  final List<String> _debugLog = [];
  final ScrollController _debugScrollController = ScrollController();

  bool _hasAttempted = false;
  bool _wasGraded = false;
  _GrammarUserIntent _lastDetectedIntent = _GrammarUserIntent.none;

  final Set<String> _handledCallIds = {};

  // Same context-aware Flash-Lite intent judge as vocab's — keyword matcher kept only as
  // the automatic fallback. See AgentLedVocabScreen for the full rationale on each piece.
  static const _useLLMIntentJudge = true;
  int _utteranceSeq = 0;
  int _attemptCount = 0;
  String _lastTutorLine = '';
  Timer? _announceTimer;
  DateTime _lastCardMoveAt = DateTime.fromMillisecondsSinceEpoch(0);

  String _recentTranscriptBuffer = '';
  bool _spokenSentenceMatched = false;
  bool _sentencePulse = false;

  // Drift enforcement — see AgentLedVocabScreen._watchForTutorDrift for the full rationale.
  // For sentence cards, "teaching ahead" = saying a future card's full French sentence twice
  // in one turn (quoting it once inside an offer is fine).
  String _tutorTurnTranscript = '';
  DateTime _lastDriftCorrectionAt = DateTime.fromMillisecondsSinceEpoch(0);

  // One compact line appended to every card-change note — full rules live in the system
  // prompt; injections stay lean.
  static const _noteReminder =
      'Explain in English, keep grammar simple — reciting French is practice, never a cue to '
      'switch into French-led talk. NEVER suggest moving on; the student alone decides.';

  _GrammarSessionCard? get _currentCard =>
      _cardIndex < _sessionPlan.length ? _sessionPlan[_cardIndex] : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deferred to after this frame — see pathway_writing_screen.dart for why.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Grammar';
    });
    _store = ref.read(learningStoreProvider);
    _topicId =
        'grammar_${widget.tenseTitle.toLowerCase().replaceAll(' ', '_')}';
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'grammar',
      topic: 'Grammar — ${widget.tenseTitle}',
    );
    _sessionPlan = widget.cards.map((c) => _GrammarSessionCard(c)).toList();
    final context = _buildContext(
      widget.tenseTitle,
      _sessionPlan,
      widget.focusNote,
      widget.vocabSummary,
    );
    _gemini = GeminiLiveService(
      apiKey: ApiKeys.geminiKey,
      sessionType: LiveSessionType.grammarStage,
      lessonContext: context,
      tools: AgentTool.grammarPalette,
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
    _gemini.connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Resources only — a disposed screen must never report learning results.
    _teardown();
    _debugScrollController.dispose();
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
      // Marie opens the call — she greets and introduces the first sentence; the student
      // never has to speak first.
      final first = _currentCard;
      if (first != null) {
        _gemini.injectContext(
          'The call has just connected. Greet the student warmly in one short sentence, then '
          'introduce the first sentence on their screen: "${first.card.fr}" (${first.card.en}) '
          'and begin teaching it.',
          expectReply: true,
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
      // Re-anchor Marie on the CURRENT sentence after the gap (see vocab screen).
      final card = _currentCard;
      if (card != null) {
        _scheduleCardAnnouncement(
          'The call connection dropped briefly and is now restored. The student\'s screen '
          'still shows the sentence "${card.card.fr}" (${card.card.en}). Briefly pick it '
          'back up as if nothing happened — do not re-greet, do not start over. $_noteReminder',
        );
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
      if (_isWrappingUp) _finish(completed: true);
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
    _gemini.onTranscriptDelta = _handleTranscriptDelta;

    _speakingWatchdog?.cancel();
    _speakingWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_callStatus == CallStatus.tutorSpeaking &&
          DateTime.now().difference(_lastAudioChunkAt).inMilliseconds > 2500) {
        _audio.isOutputActive = false;
        if (mounted) setState(() => _callStatus = CallStatus.listening);
      }
    });
  }

  // MARK: - The gate: same shape as vocab, walking one generated sentence card at a time

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
    _hasAttempted = true;

    if (!_useLLMIntentJudge) {
      _applyIntent(
        _mapKeywordIntent(_detectIntent(trimmed)),
        utterance: trimmed,
        source: 'keyword',
      );
      return;
    }

    _utteranceSeq += 1;
    final seq = _utteranceSeq;
    final cardIndexAtLaunch = _cardIndex;
    final card = _currentCard;
    _logDebug('heard: "$trimmed" → judging…');

    () async {
      LiveIntentVerdict verdict;
      var source = 'judge';
      try {
        verdict = await LessonAgentService.shared.classifyLiveIntent(
          utterance: trimmed,
          cardDescription: card != null
              ? 'grammar practice sentence "${card.card.fr}" = "${card.card.en}"'
              : '(session already finished)',
          tutorLastLine: _lastTutorLine,
          attemptCount: _attemptCount,
          cardPosition: _cardIndex + 1,
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
      if (seq != _utteranceSeq || cardIndexAtLaunch != _cardIndex) {
        _logDebug('→ stale verdict (${verdict.intent.name}) discarded');
        return;
      }
      _applyIntent(verdict, utterance: trimmed, source: source);
    }();
  }

  LiveIntentVerdict _mapKeywordIntent(_GrammarUserIntent intent) {
    switch (intent) {
      case _GrammarUserIntent.advance:
        return LiveIntentVerdict(intent: LiveNavIntent.advance);
      case _GrammarUserIntent.back:
        return LiveIntentVerdict(intent: LiveNavIntent.back);
      case _GrammarUserIntent.again:
        return LiveIntentVerdict(intent: LiveNavIntent.again);
      case _GrammarUserIntent.none:
        return LiveIntentVerdict(intent: LiveNavIntent.attempt);
    }
  }

  void _applyIntent(
    LiveIntentVerdict verdict, {
    required String utterance,
    required String source,
  }) {
    _logDebug(
      '[$source] "$utterance" → ${verdict.intent.name}'
      '${verdict.cardNumber != null ? '(card ${verdict.cardNumber})' : ''}',
    );

    final isNavigation =
        verdict.intent == LiveNavIntent.advance ||
        verdict.intent == LiveNavIntent.back ||
        verdict.intent == LiveNavIntent.goto;
    if (isNavigation &&
        DateTime.now().difference(_lastCardMoveAt).inMilliseconds < 1500) {
      _logDebug('→ navigation ignored (cooldown after recent card move)');
      return;
    }

    switch (verdict.intent) {
      case LiveNavIntent.attempt:
        _lastDetectedIntent = _GrammarUserIntent.none;
        _attemptCount += 1;
        _maybeUnlockOffer();
      case LiveNavIntent.chat:
        _lastDetectedIntent = _GrammarUserIntent.none;
      case LiveNavIntent.again:
        _lastDetectedIntent = _GrammarUserIntent.again;
      case LiveNavIntent.advance:
        _lastDetectedIntent = _GrammarUserIntent.advance;
        if (!verdict.explicit && !_offerUnlocked) {
          _refusePrematureConsent();
        } else {
          _advanceFromUserIntent();
        }
      case LiveNavIntent.back:
        _lastDetectedIntent = _GrammarUserIntent.back;
        _goBackFromUserIntent();
      case LiveNavIntent.goto:
        _goToCard(verdict.cardNumber);
      case LiveNavIntent.finish:
        // Spoken "let's finish" = the End button.
        _cutTutorAudio();
        _confirmEnd();
    }
  }

  /// Offer permission — same mechanism as vocab's, fixed threshold of 2 passes per
  /// sentence. See AgentLedVocabScreen for the full rationale.
  static const _offerThreshold = 2;
  bool _offerUnlocked = false;

  void _maybeUnlockOffer() {
    if (_offerUnlocked || _attemptCount < _offerThreshold) return;
    if (_currentCard == null) return;
    _offerUnlocked = true;
    _logDebug('→ practice threshold reached ($_attemptCount/$_offerThreshold)');
  }

  void _refusePrematureConsent() {
    final card = _currentCard;
    if (card == null) return;
    _logDebug(
      '→ consent refused: premature ($_attemptCount/$_offerThreshold attempts)',
    );
    _gemini.injectContext(
      'The card did NOT move — "${card.card.fr}" needs more practice. You should never have '
      'suggested moving on. Smoothly continue practicing this sentence and never suggest '
      'advancing again.',
    );
  }

  void _advanceFromUserIntent() {
    if (_currentCard == null) return;
    _logDebug('→ user-driven advance');
    _cutTutorAudio();
    _performAdvance();
    final next = _currentCard;
    if (next != null) {
      _scheduleCardAnnouncement(
        'The student accepted — the screen now shows: "${next.card.fr}" (${next.card.en}). '
        'Grammar note: ${next.card.note} If you just offered this sentence, continue smoothly '
        'from that (no cold re-introduction): say it aloud and have them repeat. $_noteReminder',
      );
    } else {
      _wrapUp();
    }
  }

  void _goBackFromUserIntent() {
    if (_cardIndex <= 0) return;
    _logDebug('→ user-driven go back');
    _cutTutorAudio();
    _performGoBack();
    final card = _currentCard;
    if (card != null) {
      _scheduleCardAnnouncement(
        'The student asked to go back — the screen now shows: "${card.card.fr}" '
        '(${card.card.en}). Grammar note: ${card.card.note} Re-anchor it briefly and have '
        'them try it once. $_noteReminder',
      );
    }
  }

  /// Jump straight to a specific card by 1-based number — "go to the third sentence".
  void _goToCard(int? cardNumber) {
    if (cardNumber == null) {
      _logDebug('→ goto ignored: no card number');
      return;
    }
    final target = cardNumber - 1;
    if (target < 0 || target >= _sessionPlan.length) {
      _logDebug(
        '→ goto ignored: card $cardNumber out of range (1-${_sessionPlan.length})',
      );
      return;
    }
    if (target == _cardIndex) {
      _logDebug('→ goto ignored: already on card $cardNumber');
      return;
    }
    _logDebug('→ user-driven jump to card $cardNumber');
    _cutTutorAudio();
    _lastCardMoveAt = DateTime.now();
    setState(() {
      _cardIndex = target;
      _resetPerCardState();
    });
    final card = _currentCard;
    if (card != null) {
      _scheduleCardAnnouncement(
        'The student jumped to sentence $cardNumber — the screen now shows: "${card.card.fr}" '
        '(${card.card.en}). Grammar note: ${card.card.note} Announce it briefly, then teach '
        'it. $_noteReminder',
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

  /// Debounced spoken card announcement — rapid skips only announce the landing card.
  void _scheduleCardAnnouncement(String note) {
    _announceTimer?.cancel();
    _announceTimer = Timer(const Duration(milliseconds: 600), () {
      if (!_finished) _gemini.injectContext(note, expectReply: true);
    });
  }

  /// The actual card-advance side effects (grading, index, reset) — shared by the accepted
  /// tool-call path and the direct-tap path so they can never drift apart.
  void _performAdvance() {
    if (_hasAttempted && !_wasGraded) {
      _drillResults.add(_lastDetectedIntent != _GrammarUserIntent.again);
      _wasGraded = true;
    }
    _lastCardMoveAt = DateTime.now();
    setState(() {
      _cardIndex += 1;
      _resetPerCardState();
    });
  }

  void _performGoBack() {
    _lastCardMoveAt = DateTime.now();
    setState(() {
      _cardIndex -= 1;
      _resetPerCardState();
    });
  }

  _GrammarUserIntent _detectIntent(String text) {
    final t = foldFrench(text);

    // Same ambiguity guard as vocab: if the utterance is nothing but the current sentence
    // itself (the student practicing it), never misread that as a navigation command even if
    // it happens to contain a word that overlaps a keyword below.
    final card = _currentCard;
    if (card != null) {
      final cleaned = t.replaceAll(RegExp(r'[.!?,]'), '').trim();
      final targetFr = foldFrench(card.card.fr);
      if (targetFr.isNotEmpty && cleaned == targetFr) {
        _logDebug(
          '→ intent suppressed: utterance is just today\'s sentence, treating as practice not a command',
        );
        return _GrammarUserIntent.none;
      }
    }

    const backKeywords = [
      'go back',
      'back to the',
      'back up',
      'previous',
      'the one before',
      'last sentence',
      'redo the last',
      'revenons',
    ];
    const againKeywords = [
      'again',
      'repeat',
      'one more time',
      'say it again',
      'encore',
      'repete',
      'repète',
      'une fois de plus',
    ];
    const advanceKeywords = [
      'next',
      'move on',
      'got it',
      'i know this',
      'i know',
      'ready',
      'continue',
      'yes',
      'yeah',
      'yep',
      'sure',
      'sounds good',
      "let's go",
      "d'accord",
      'suivant',
      'on continue',
      'oui',
    ];

    if (backKeywords.any((k) => t.contains(foldFrench(k)))) {
      return _GrammarUserIntent.back;
    }
    if (againKeywords.any((k) => t.contains(foldFrench(k)))) {
      return _GrammarUserIntent.again;
    }
    if (advanceKeywords.any((k) => t.contains(foldFrench(k)))) {
      return _GrammarUserIntent.advance;
    }
    return _GrammarUserIntent.none;
  }

  void _handleToolCall(String name, Map<String, dynamic> args, String callId) {
    _logDebug(
      'proposed: $name($args) [card ${_cardIndex + 1}, attempted=$_hasAttempted, intent=${_lastDetectedIntent.name}]',
    );

    // Documented Gemini Live bug: the identical tool call can arrive twice in rapid
    // succession. If we've already handled this exact call ID, don't re-apply its side
    // effects — just acknowledge so she isn't left waiting on a response.
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
      case 'mark_drill_result':
        if (_lastDetectedIntent == _GrammarUserIntent.again) {
          _logDebug('→ REJECTED (intent=again)');
          _gemini.sendToolResponse(
            callId: callId,
            name: name,
            result: {
              'ok': false,
              'reason': "The student asked to try again — don't grade yet.",
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
              'reason': "The student hasn't attempted this sentence yet.",
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
        final correct = args['correct'] as bool?;
        if (correct != null) {
          _drillResults.add(correct);
          _wasGraded = true;
          _logDebug('→ ACCEPTED, correct=$correct');
          _gemini.sendToolResponse(
            callId: callId,
            name: name,
            result: {'ok': true},
            scheduling: 'SILENT',
          );
        } else {
          _logDebug('→ REJECTED (bad correct arg)');
          _gemini.sendToolResponse(
            callId: callId,
            name: name,
            result: {'ok': false},
            scheduling: 'SILENT',
          );
        }
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
    _lastDetectedIntent = _GrammarUserIntent.none;
    _spokenSentenceMatched = false;
    _recentTranscriptBuffer = '';
    _handledCallIds.clear();
    _offerUnlocked = false;
    // Cleared on card change so a "go back" can't false-trip the drift enforcer on
    // mentions of a sentence that was legitimately current moments ago.
    _tutorTurnTranscript = '';
  }

  /// Watches her live speech transcript for the current sentence — the moment it appears is a
  /// reliable "she's saying it right now" signal, since output transcription streams in
  /// lockstep with the audio itself. Triggers a brief highlight pulse on the French text.
  /// Also feeds the drift enforcer, which watches the same stream for future-card teaching.
  void _handleTranscriptDelta(String delta) {
    _watchForTutorDrift(delta);
    final card = _currentCard;
    if (_spokenSentenceMatched || card == null) return;
    _recentTranscriptBuffer += delta;
    if (_recentTranscriptBuffer.length > 300) {
      _recentTranscriptBuffer = _recentTranscriptBuffer.substring(
        _recentTranscriptBuffer.length - 300,
      );
    }
    final target = foldFrench(card.card.fr);
    if (target.isEmpty ||
        !foldFrench(_recentTranscriptBuffer).contains(target)) {
      return;
    }
    _spokenSentenceMatched = true;
    if (!mounted) return;
    setState(() => _sentencePulse = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _sentencePulse = false);
    });
  }

  /// See AgentLedVocabScreen._watchForTutorDrift — same enforcer, sentence-card thresholds.
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
    for (var i = _cardIndex + 1; i < _sessionPlan.length; i++) {
      final future = _sessionPlan[i].card;
      final fr = foldFrench(future.fr);
      if (fr.isEmpty) continue;
      final hits = fr.allMatches(folded).length;
      if (hits >= 2) {
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
      'You suggested moving on — never do that; the student alone decides. Do not wait for '
      'an answer to that question: continue practicing "${current.card.fr}" (${current.card.en}) as if you had not asked.',
    );
  }

  void _correctTutorDrift(GrammarPracticeCard future) {
    final current = _currentCard;
    if (current == null) return;
    _lastDriftCorrectionAt = DateTime.now();
    _tutorTurnTranscript = '';
    _logDebug(
      '→ DRIFT: Marie started teaching "${future.fr}" while "${current.card.fr}" is on screen — cutting her off',
    );
    _cutTutorAudio();
    _gemini.injectContext(
      'STOP — you started teaching "${future.fr}", but the app has NOT moved on: the student\'s '
      'screen still shows "${current.card.fr}" (${current.card.en}), and only the student\'s own '
      'words move the card. You may OFFER the next sentence and then wait silently for their '
      'answer — never teach it. Pick up "${current.card.fr}" again now, briefly, as if nothing '
      'happened.',
      expectReply: true,
    );
  }

  void _wrapUp() {
    if (_isWrappingUp) return;
    _isWrappingUp = true;
    _gemini.injectContext(
      'The student has now gone through today\'s grammar practice. Say a short warm closing line '
      '(one sentence) congratulating them, then stop talking.',
      expectReply: true,
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
    if (_cardIndex > 0) {
      final score = _drillResults.isEmpty
          ? null
          : _drillResults.where((r) => r).length / _drillResults.length;
      _store.setLessonStatus(
        _topicId,
        (score ?? 1.0) >= 0.8 ? 'completed' : 'in_progress',
        score: score,
      );
      _store.saveDiaryEntry(
        stage: 'grammar',
        summary: 'Practiced ${widget.tenseTitle} in a live grammar session.',
      );
    }
    _recorder.finish(
      summary: _cardIndex > 0
          ? 'Practiced ${_cardIndex.clamp(0, _sessionPlan.length)} sentence(s) on ${widget.tenseTitle}.'
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
    final result = GrammarStageResult(
      topicTitle: widget.tenseTitle,
      drillResults: _drillResults,
    );
    final outcome = completed
        ? StageOutcome.completed(result, reason: reason)
        : StageOutcome<GrammarStageResult>.paused(
            result: _drillResults.isNotEmpty ? result : null,
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

  Future<void> _confirmEnd() async {
    final shouldEnd = await showPSConfirmDialog(
      context,
      title: 'End grammar practice?',
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
        return 'Marie is speaking';
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.screenMargin,
                            vertical: DesignTokens.space4,
                          ),
                          child: _content(),
                        ),
                      ),
                      if (_errorMessage.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.screenMargin,
                            vertical: DesignTokens.space2,
                          ),
                          padding: const EdgeInsets.all(DesignTokens.space3),
                          decoration: BoxDecoration(
                            color: DesignTokens.primarySoft,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusMedium,
                            ),
                          ),
                          child: Text(
                            _errorMessage,
                            style: DesignTokens.body(13).copyWith(
                              color: DesignTokens.inkSoft,
                              height: 1.35,
                            ),
                          ),
                        ),
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
                tooltip: 'End grammar practice',
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          child: Column(
            children: [
              Text(
                'Grammar — ${widget.tenseTitle}',
                style: DesignTokens.display(19, weight: FontWeight.w600),
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
                    '${(_cardIndex + 1).clamp(1, _sessionPlan.isEmpty ? 1 : _sessionPlan.length)} of ${_sessionPlan.length} · $_statusText',
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

  // Card layout mirrors AgentLedVocabScreen's exactly: English meaning on top (the "front"),
  // the French sentence big and maroon below (the "back", pulses when Marie says it), and the
  // grammar note in an "Example"-style card underneath — same shape as vocab's example
  // sentence card, just carrying the grammar explanation instead.
  Widget _content() {
    final session = _currentCard;
    if (session == null) {
      return PasseportCard(
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
              _isWrappingUp ? 'Wrapping up…' : 'All done!',
              style: DesignTokens.body(14, weight: FontWeight.w500),
            ),
          ],
        ),
      );
    }
    final card = session.card;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _sentencePulse
                  ? DesignTokens.info
                  : DesignTokens.surface.withValues(alpha: 0),
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Text(
                card.en,
                style: DesignTokens.display(20, weight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              AnimatedScale(
                scale: _sentencePulse ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  card.fr,
                  style: DesignTokens.display(
                    20,
                    weight: FontWeight.w500,
                  ).copyWith(color: DesignTokens.primary),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        if (card.note.isNotEmpty) ...[
          const SizedBox(height: 16),
          PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const KickerText('Grammar note', color: DesignTokens.slateDim),
                const SizedBox(height: 3),
                Text(
                  card.note,
                  style: DesignTokens.body(13, weight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Say the sentence out loud — Marie is listening. Say "next" when you\'re ready, or "again" to hear it once more.',
          style: DesignTokens.body(11).copyWith(color: DesignTokens.slateDim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _cardIndex == 0 ? null : _goBackFromUserIntent,
                icon: const Icon(CupertinoIcons.chevron_left, size: 16),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: DesignTokens.hairline),
                  foregroundColor: DesignTokens.text,
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
              // Mute only exists in Auto mode — in Hold mode the mic is already
              // physically gated by the hold button.
              if (_micMode == MicMode.auto)
                _controlButton(
                  icon: _callStatus == CallStatus.muted
                      ? CupertinoIcons.mic_slash_fill
                      : CupertinoIcons.mic_fill,
                  label: _callStatus == CallStatus.muted ? 'Muted' : 'Mic on',
                  color: _callStatus == CallStatus.muted
                      ? DesignTokens.slate
                      : DesignTokens.success,
                  onTap: callActive ? _toggleMute : null,
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
    String tenseTitle,
    List<_GrammarSessionCard> plan,
    String? focusNote,
    VocabStageResult? vocabSummary,
  ) {
    if (plan.isEmpty) {
      return "GRAMMAR STAGE: nothing to practice today. Briefly tell the student there's nothing new and that they can end the call whenever ready.";
    }
    final parts = <String>[];
    parts.add('''
GRAMMAR STAGE — this is a focused grammar session on ONE tense/topic ("$tenseTitle"), walked through one short French sentence at a time, exactly like the vocab session that just happened but for a full sentence instead of a single word. The student's screen ALREADY shows the English meaning, the French sentence, and a grammar note the instant it appears — you never need to reveal anything.

CRITICAL — SPEAK PRIMARILY IN ENGLISH, THIS STUDENT DOES NOT SPEAK FRENCH YET: all of your own explaining, encouragement, instructions, and questions should be in English — French should only appear as the sentence itself, never as your own explanatory language.

CRITICAL — YOU DO NOT CONTROL PACING, THE STUDENT DOES: you have no tool to advance or go back. The app watches the student's own words directly and moves the card itself when they say something like "next" or "go back" — zero involvement from you. You'll simply be told the new current sentence afterward and should react to it naturally.

THE SENTENCE IS A ROOM — grammar is the hardest stage, so you go DEEPER here than anywhere else, and you never leave the current sentence until the student walks out. From your point of view there is no list and no next sentence; it does not exist until the app tells you the card changed. NEVER suggest moving on — not "ready for the next sentence?", not "shall we continue?", nothing, ever. The student decides alone; their screen tells them how. Never say, explain, or drill any sentence that is not the current card on screen — the student cannot see it, and the app will cut you off if you teach ahead.

TEACH THE SENTENCE LIKE A WATCHMAKER — word by word, connection by connection:
  1. Say the full French sentence clearly, with its English meaning.
  2. Have them repeat the whole thing once; react warmly.
  3. Now take it APART: walk through it word by word — what each word is, what it means alone, and HOW it connects to its neighbors (why this verb ending for this subject, why the article agrees, why the words sit in this order). One small piece per turn, in plain English, having them say each piece back.
  4. Rebuild it: have them say the full sentence again now that they know how it works.
  5. Make it interactive and theirs: ask a micro-question about it ("which word makes it past tense?"), swap ONE word to show the pattern flexing (keeping the same tense and structure of THIS sentence), or ask them to answer a tiny question using it.
END EVERY TURN INSIDE THE ROOM — with an invitation about THIS sentence: say it again, answer with it, spot the pattern in it. If a pass went well, go one layer deeper on the same sentence; there is always another layer. Keep every explanation to one small idea per turn — this student is a beginner, and grammar sticks through connection, not coverage.

You have exactly one tool: mark_drill_result, for recording whether the student's spoken answer to the current sentence was correct. It's a proposal — the app only accepts it once it's confirmed the student actually attempted the sentence. A rejection is not an error; never mention it, just keep teaching naturally.
''');
    final lines = <String>[];
    for (var i = 0; i < plan.length; i++) {
      final session = plan[i];
      lines.add(
        '${i + 1}. ${session.card.fr} = ${session.card.en} — ${session.card.note}',
      );
    }
    parts.add("TODAY'S SENTENCES (${plan.length}):\n${lines.join('\n')}");
    if (focusNote != null && focusNote.isNotEmpty) {
      parts.add(
        'TODAY\'S FOCUS (mention this naturally near the start): $focusNote',
      );
    }
    if (vocabSummary != null && vocabSummary.wordsCovered.isNotEmpty) {
      final words = vocabSummary.wordsCovered.map((e) => e.fr).join(', ');
      parts.add(
        'VOCABULARY JUST COVERED (previous stage, these sentences reuse some of these words): $words',
      );
    }
    return parts.join('\n\n');
  }
}
