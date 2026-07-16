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
import '../../services/gemini_live_service.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/session_recorder.dart';
import '../../utils/text_fold.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/floating_notetaker.dart';
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

enum _ReadingUserIntent { advance, again, back, none }

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
    extends ConsumerState<AgentLedListeningScreen> {
  late GeminiLiveService _gemini;
  late AudioStreamingService _audio;
  late LearningStore _store;
  late SessionRecorder _recorder;
  late List<_ReadingSessionCard> _sessionPlan;

  CallStatus _callStatus = CallStatus.connecting;
  int _callDuration = 0;
  Timer? _timer;
  Timer? _speakingWatchdog;
  String _errorMessage = '';
  bool _finished = false;
  bool _isWrappingUp = false;

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

  // Same context-aware Flash-Lite intent judge as vocab's — keyword matcher kept only as
  // the automatic fallback. See AgentLedVocabScreen for the full rationale on each piece.
  static const _useLLMIntentJudge = true;
  int _utteranceSeq = 0;
  String _lastTutorLine = '';
  Timer? _announceTimer;
  DateTime _lastCardMoveAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Drift enforcement — see AgentLedVocabScreen._watchForTutorDrift for the full rationale.
  String _tutorTurnTranscript = '';
  DateTime _lastDriftCorrectionAt = DateTime.fromMillisecondsSinceEpoch(0);

  _ReadingSessionCard? get _currentCard =>
      _segmentIndex < _sessionPlan.length ? _sessionPlan[_segmentIndex] : null;

  @override
  void initState() {
    super.initState();
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
      lessonContext: context,
      tools: AgentTool.readingPalette,
      learningStoreForProfile: _store,
    );
    _audio = AudioStreamingService();
    _setupCallbacks();
    _gemini.connect();
  }

  @override
  void dispose() {
    // Resources only — a disposed screen must never report learning results.
    _teardown();
    _debugScrollController.dispose();
    super.dispose();
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
            await _audio.startStreaming(onChunk: _gemini.sendAudioChunk);
          } catch (e) {
            setState(() => _errorMessage = 'Mic error: $e');
          }
        } else {
          setState(() => _errorMessage = 'Microphone permission denied');
        }
      });
      // Marie opens the call — she greets and introduces the first segment; the student
      // never has to speak first.
      final first = _currentCard;
      if (first != null) {
        _gemini.injectContext(
          'The call has just connected. Greet the student warmly in one short sentence, then '
          'introduce the first part of the passage on their screen: "${first.segment.fr}"'
          '${first.segment.en.isEmpty ? '' : ' = ${first.segment.en}'} and begin teaching it.',
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

    _gemini.onError = (msg) {
      if (mounted) setState(() => _errorMessage = msg);
    };

    _gemini.onUserTranscript = (text) {
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
              ? 'passage segment "${card.segment.fr}" = "${card.segment.en}"'
              : '(session already finished)',
          tutorLastLine: _lastTutorLine,
          attemptCount: _attemptCount,
          cardPosition: _segmentIndex + 1,
          cardCount: _sessionPlan.length,
        );
      } catch (_) {
        verdict = _mapKeywordIntent(_detectIntent(trimmed));
        source = 'keyword-fallback';
      }
      if (!mounted || _finished) return;
      if (seq != _utteranceSeq || segmentIndexAtLaunch != _segmentIndex) {
        _logDebug('→ stale verdict (${verdict.intent.name}) discarded');
        return;
      }
      _applyIntent(verdict, utterance: trimmed, source: source);
    }();
  }

  LiveIntentVerdict _mapKeywordIntent(_ReadingUserIntent intent) {
    switch (intent) {
      case _ReadingUserIntent.advance:
        return LiveIntentVerdict(intent: LiveNavIntent.advance);
      case _ReadingUserIntent.back:
        return LiveIntentVerdict(intent: LiveNavIntent.back);
      case _ReadingUserIntent.again:
        return LiveIntentVerdict(intent: LiveNavIntent.again);
      case _ReadingUserIntent.none:
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
      '${verdict.cardNumber != null ? '(card ${verdict.cardNumber})' : ''}, attempts: $_attemptCount',
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
        _lastDetectedIntent = _ReadingUserIntent.none;
        _attemptCount += 1;
        _maybeUnlockOffer();
      case LiveNavIntent.chat:
        _lastDetectedIntent = _ReadingUserIntent.none;
      case LiveNavIntent.again:
        _lastDetectedIntent = _ReadingUserIntent.again;
      case LiveNavIntent.advance:
        _lastDetectedIntent = _ReadingUserIntent.advance;
        if (!verdict.explicit && !_offerUnlocked) {
          _refusePrematureConsent();
        } else {
          _advanceFromUserIntent();
        }
      case LiveNavIntent.back:
        _lastDetectedIntent = _ReadingUserIntent.back;
        _goBackFromUserIntent();
      case LiveNavIntent.goto:
        _goToCard(verdict.cardNumber);
    }
  }

  /// Offer permission — same mechanism as vocab's, fixed threshold of 2 passes per
  /// segment. See AgentLedVocabScreen for the full rationale.
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
      'The card did NOT move — "${card.segment.fr}" needs more practice. You should never have '
      'suggested moving on. Smoothly continue practicing this part and never suggest '
      'advancing again.',
    );
  }

  // One compact line appended to every card-change note — full rules live in the system
  // prompt; injections stay lean.
  static const _noteReminder =
      'Explain in English — reciting French is practice, never a cue to switch into '
      'French-led talk. NEVER suggest moving on; the student alone decides.';

  void _advanceFromUserIntent() {
    if (_currentCard == null) return;
    _logDebug('→ user-driven advance');
    _cutTutorAudio();
    _performAdvance();
    final next = _currentCard;
    if (next != null) {
      _scheduleCardAnnouncement(
        '${_contextNote(next.segment, 'The student accepted — the screen now shows')} '
        'If you just offered this part, continue smoothly from that (no cold '
        're-introduction): say it aloud and have them repeat.',
      );
    } else {
      _wrapUp();
    }
  }

  void _goBackFromUserIntent() {
    if (_segmentIndex <= 0) return;
    _logDebug('→ user-driven go back');
    _cutTutorAudio();
    _performGoBack();
    final card = _currentCard;
    if (card != null) {
      _scheduleCardAnnouncement(
        '${_contextNote(card.segment, 'The student asked to go back — the screen now shows')} '
        'Re-anchor it briefly and have them try it once.',
      );
    }
  }

  /// Jump straight to a specific segment by 1-based number — "go to the third part".
  void _goToCard(int? cardNumber) {
    if (cardNumber == null) {
      _logDebug('→ goto ignored: no card number');
      return;
    }
    final target = cardNumber - 1;
    if (target < 0 || target >= _sessionPlan.length) {
      _logDebug(
        '→ goto ignored: segment $cardNumber out of range (1-${_sessionPlan.length})',
      );
      return;
    }
    if (target == _segmentIndex) {
      _logDebug('→ goto ignored: already on segment $cardNumber');
      return;
    }
    _logDebug('→ user-driven jump to segment $cardNumber');
    _cutTutorAudio();
    _lastCardMoveAt = DateTime.now();
    setState(() {
      _segmentIndex = target;
      _resetPerCardState();
    });
    final card = _currentCard;
    if (card != null) {
      _scheduleCardAnnouncement(
        '${_contextNote(card.segment, 'The student jumped to part $cardNumber — the screen now shows')} '
        'Announce it briefly, then teach it.',
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

  /// Debounced spoken card announcement — rapid skips only announce the landing segment.
  void _scheduleCardAnnouncement(String note) {
    _announceTimer?.cancel();
    _announceTimer = Timer(const Duration(milliseconds: 600), () {
      if (!_finished) _gemini.injectContext(note, expectReply: true);
    });
  }

  static String _contextNote(ReadingSegment segment, String prefix) {
    final meaning = segment.en.isEmpty ? '' : ' = ${segment.en}';
    return '$prefix: "${segment.fr}"$meaning. Grammar note: ${segment.grammarNote} '
        'Pronunciation tip: ${segment.pronunciationTip} $_noteReminder';
  }

  /// The actual card-advance side effects (grading, index, reset) — shared by the accepted
  /// tool-call path and the direct-tap path so they can never drift apart.
  void _performAdvance() {
    if (_hasAttempted && !_wasGraded) _wasGraded = true;
    if (_currentCard != null) _reviewedCount += 1;
    _lastCardMoveAt = DateTime.now();
    setState(() {
      _segmentIndex += 1;
      _resetPerCardState();
    });
  }

  void _performGoBack() {
    _lastCardMoveAt = DateTime.now();
    setState(() {
      _segmentIndex -= 1;
      _resetPerCardState();
    });
  }

  _ReadingUserIntent _detectIntent(String text) {
    final t = foldFrench(text);

    // Same ambiguity guard as vocab: if the utterance is just today's segment itself, that's
    // a practice attempt, never navigation — even if the segment text happens to overlap a
    // nav keyword (e.g. a passage segment that is itself "oui").
    final card = _currentCard;
    if (card != null) {
      final cleaned = t.replaceAll(RegExp(r'[.!?,]'), '').trim();
      final targetFr = foldFrench(card.segment.fr);
      final targetEn = foldFrench(card.segment.en);
      final words = cleaned.split(' ').where((w) => w.isNotEmpty).toList();
      if (words.isNotEmpty &&
          targetFr.isNotEmpty &&
          words.every((w) => w == targetFr || w == targetEn)) {
        _logDebug(
          '→ intent suppressed: utterance is just the current segment ("${card.segment.fr}"), treating as practice not a command',
        );
        return _ReadingUserIntent.none;
      }
    }

    const backKeywords = [
      'go back',
      'back to the',
      'back up',
      'previous',
      'the one before',
      'last part',
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
      return _ReadingUserIntent.back;
    }
    if (againKeywords.any((k) => t.contains(foldFrench(k)))) {
      return _ReadingUserIntent.again;
    }
    if (advanceKeywords.any((k) => t.contains(foldFrench(k)))) {
      return _ReadingUserIntent.advance;
    }
    return _ReadingUserIntent.none;
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
              'reason':
                  "The student hasn't attempted this segment yet — listen for their attempt before grading.",
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
    _offerUnlocked = false;
    // Cleared on card change so a "go back" can't false-trip the drift enforcer on
    // mentions of a segment that was legitimately current moments ago.
    _tutorTurnTranscript = '';
  }

  /// See AgentLedVocabScreen._watchForTutorDrift — same enforcer. Passage segments are
  /// short words/phrases like vocab words, so the same repeated-drilling threshold applies:
  /// naming an upcoming segment once (an offer) is fine, saying it 3+ times is teaching it.
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
      if (hits >= 3) {
        _correctTutorDrift(future);
        return;
      }
    }
  }

  /// She suggested moving on — banned. Cut + corrective, same machinery as drift.
  void _correctIllegalOffer() {
    final current = _currentCard;
    if (current == null) return;
    _lastDriftCorrectionAt = DateTime.now();
    _tutorTurnTranscript = '';
    _logDebug('→ ILLEGAL OFFER: Marie suggested moving on — cutting her off');
    _cutTutorAudio();
    _gemini.injectContext(
      'STOP — you suggested moving on, which you must NEVER do. The student decides when to '
      'move, alone. Resume practicing the current part right now, warmly, as if you had '
      'never asked.',
      expectReply: true,
    );
  }

  void _correctTutorDrift(ReadingSegment future) {
    final current = _currentCard;
    if (current == null) return;
    _lastDriftCorrectionAt = DateTime.now();
    _tutorTurnTranscript = '';
    _logDebug(
      '→ DRIFT: Marie started teaching "${future.fr}" while "${current.segment.fr}" is on screen — cutting her off',
    );
    _cutTutorAudio();
    _gemini.injectContext(
      'STOP — you started teaching "${future.fr}", but the app has NOT moved on: the student\'s '
      'screen still shows "${current.segment.fr}"'
      '${current.segment.en.isEmpty ? '' : ' = "${current.segment.en}"'}, and only the student\'s '
      'own words move the segment. You may OFFER the next part and then wait silently for their '
      'answer — never teach it. Pick up "${current.segment.fr}" again now, briefly, as if nothing '
      'happened.',
      expectReply: true,
    );
  }

  void _wrapUp() {
    if (_isWrappingUp) return;
    _isWrappingUp = true;
    _gemini.injectContext(
      "The student has now gone through the whole passage. Say a short warm closing line (one "
      "sentence) congratulating them, then stop talking.",
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
    if (_reviewedCount > 0) {
      _store.saveDiaryEntry(
        stage: 'reading',
        summary:
            'Read through $_reviewedCount part(s) of "${widget.passage.title}" in a live reading/listening session.',
      );
    }
    _recorder.finish(
      summary: _reviewedCount > 0
          ? 'Read through $_reviewedCount part(s) of "${widget.passage.title}".'
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
        await _audio.startStreaming(onChunk: _gemini.sendAudioChunk);
        setState(() => _callStatus = CallStatus.listening);
      } catch (e) {
        setState(() => _errorMessage = 'Failed to unmute: $e');
      }
    } else {
      await _audio.stopStreaming();
      setState(() => _callStatus = CallStatus.muted);
    }
  }

  Future<void> _confirmEnd() async {
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

  Widget _content() {
    final card = _currentCard;
    return Column(
      children: [
        PasseportCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KickerText(widget.passage.title, color: DesignTokens.slateDim),
              const SizedBox(height: 4),
              Text(
                widget.passage.fullText,
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.slateDim),
              ),
            ],
          ),
        ),
        if (card != null) ...[
          const SizedBox(height: 14),
          PasseportCard(
            padding: 24,
            child: Column(
              children: [
                Text(
                  card.segment.fr,
                  style: DesignTokens.display(
                    22,
                    weight: FontWeight.w500,
                  ).copyWith(color: DesignTokens.primary),
                ),
                if (card.segment.en.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    card.segment.en,
                    style: DesignTokens.display(16, weight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const KickerText(
                      'Grammar note',
                      color: DesignTokens.slateDim,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      card.segment.grammarNote,
                      style: DesignTokens.body(13),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const KickerText(
                      'Pronunciation',
                      color: DesignTokens.slateDim,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      card.segment.pronunciationTip,
                      style: DesignTokens.body(13),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Repeat it out loud — Marie is listening. Say "next" when you\'re ready, or "again" to hear it once more.',
            style: DesignTokens.body(11).copyWith(color: DesignTokens.slateDim),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          // Same guaranteed navigation fallback as vocab — Back/Next always work, no
          // dependency on speech recognition or the model.
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
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PasseportPrimaryButton(
                  label: 'Next segment',
                  icon: CupertinoIcons.arrow_right,
                  onPressed: _advanceFromUserIntent,
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 14),
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
                  _isWrappingUp ? 'Wrapping up…' : 'All done!',
                  style: DesignTokens.body(14, weight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: PasseportPrimaryButton(
                    label: 'Continue',
                    icon: CupertinoIcons.arrow_right,
                    onPressed: () => _finish(completed: true),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _controlButton(
            icon: _callStatus == CallStatus.muted
                ? CupertinoIcons.mic_slash_fill
                : CupertinoIcons.mic_fill,
            label: _callStatus == CallStatus.muted ? 'Muted' : 'Mic on',
            color: _callStatus == CallStatus.muted
                ? DesignTokens.slate
                : DesignTokens.success,
            onTap:
                (_callStatus == CallStatus.connecting ||
                    _callStatus == CallStatus.ended)
                ? null
                : _toggleMute,
          ),
          _controlButton(
            icon: CupertinoIcons.phone_down_fill,
            label: 'End',
            color: DesignTokens.inkSoft,
            onTap: _confirmEnd,
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
READING & LISTENING STAGE — walking through a short French passage, one word or short phrase at a time, exactly the way the vocab stage teaches one word at a time. The student's screen ALREADY shows the current segment's French text and English meaning the instant it appears — you never need to reveal anything.

CRITICAL — SPEAK PRIMARILY IN ENGLISH, THIS STUDENT DOES NOT SPEAK FRENCH YET: all of your own explaining, encouragement, instructions, and questions should be in English — French should only ever appear as the current segment itself, never as your own explanatory language. Never answer in French only, including when they ask you to repeat something. If you catch yourself explaining something in French, stop and say it in English instead.

CRITICAL — YOU DO NOT CONTROL PACING, THE STUDENT DOES: you are NOT in charge of deciding when to move to the next segment or go back, and you have no tool to do that yourself. The app is watching the student's own words directly, and when they say something like "next", "got it", or "go back", the app moves the segment itself — with zero involvement from you. You'll simply be told the new current segment afterward and should react to it naturally, as if you'd just turned the page together. Never say things like "let's move on" as an announcement of an action you're about to take.

ABSOLUTE RULE — NEVER SUGGEST MOVING ON: not "ready for the next part?", not "shall we continue?" — nothing of the kind, ever. The student decides alone; their screen tells them how. Your only job is practicing the current segment until the app tells you it changed. The app monitors your speech and will cut you off and correct you if you suggest advancing. Never explain, drill, or walk through any segment that is not the current one on screen — the student cannot see it yet.

You have exactly one tool: mark_segment_result, for recording how well the student did with the current segment (grade: again/good/easy). It's a proposal — the app only accepts it once it's confirmed the student actually attempted it. A rejection is not an error; never mention it to the student, just keep teaching naturally.

CRITICAL — FOLLOW THIS EXACT ORDER FOR EVERY SINGLE SEGMENT, DO NOT SKIP OR REORDER STEPS:
  1. Read the French word/phrase slowly and clearly, pairing it with its English meaning.
  2. Ask the student to repeat it, and give them a real beat of silence to actually try.
  3. React briefly to their attempt (encouragement, or a light correction).
  4. THEN explain the grammar note already shown on their screen (why this word/word order is used) AND the pronunciation tip already shown, in your own words, briefly.
  5. ONLY NOW ask a genuine question about moving on — e.g. "Ready for the next part, or want to try it once more?" — and wait for their actual answer next turn.
This student is a true beginner: do at least 2 full passes of steps 1-4 before step 5, not one. Keep grammar explanations SIMPLE — no conjugation tables, no advanced tense talk, this is intentionally basic; a harder version comes later.
''');
    final lines = <String>[];
    for (var i = 0; i < plan.length; i++) {
      final segment = plan[i].segment;
      final meaning = segment.en.isEmpty ? '' : ' = ${segment.en}';
      lines.add(
        '${i + 1}. ${segment.fr}$meaning — grammar note: ${segment.grammarNote} pronunciation tip: ${segment.pronunciationTip}',
      );
    }
    parts.add('FULL PASSAGE TEXT: ${passage.fullText}');
    parts.add('SEGMENTS IN ORDER (${plan.length}):\n${lines.join('\n')}');
    if (vocabSummary != null && vocabSummary.wordsCovered.isNotEmpty) {
      final words = vocabSummary.wordsCovered.map((e) => e.fr).join(', ');
      parts.add(
        'VOCABULARY JUST COVERED (in the previous stage, feel free to note the connection naturally if relevant): $words',
      );
    }
    return parts.join('\n\n');
  }
}
