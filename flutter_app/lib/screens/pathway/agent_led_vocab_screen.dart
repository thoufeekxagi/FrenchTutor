import '../../widgets/adaptive/adaptive.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/api_keys.dart';
import '../../design/tokens.dart';
import '../../data/database/learning_store.dart';
import '../../models/agent_tool.dart';
import '../../models/content_models.dart';
import '../../models/profile.dart';
import '../../models/srs_state.dart';
import '../../providers/database_provider.dart';
import '../../services/audio_streaming_service.dart';
import '../../prompts/live_prompts.dart';
import '../../services/gemini_live_service.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/mic_mode.dart';
import '../../services/session_recorder.dart';
import '../../flow/stage_outcome.dart';
import '../../services/srs_service.dart';
import '../../utils/text_fold.dart';
import '../../utils/transcript_filter.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/error_notice.dart';
import '../../widgets/floating_notetaker.dart';
import '../../widgets/mic_mode_bar.dart';
import '../session/session_screen.dart' show CallStatus;

class VocabStageResult {
  VocabStageResult({
    required this.wordsCovered,
    required this.reviewedCount,
    this.plannedWordIds = const [],
  });
  final List<VocabEntry> wordsCovered;
  final int reviewedCount;

  /// The full word list this session was started with — persisted so an
  /// interrupted session can offer "continue with the remaining words" later.
  final List<String> plannedWordIds;
}

/// One word in the session plan — straight through in the given order, no interleaved
/// repeats. Each word appears exactly once per session.
class _VocabSessionCard {
  _VocabSessionCard(this.entry);
  final VocabEntry entry;
}

enum _UserIntent { advance, again, back, none }

/// Daily Pathway stage 1 — a focused, agent-led vocabulary session, ported from
/// AgentLedVocabView.swift, redesigned around one principle: Marie's tool calls are
/// PROPOSALS, never commands. The app is the sole authority over whether a word actually
/// advances or gets graded — it verifies (via the student's own transcript) that a real
/// attempt happened, or that the student explicitly asked to move on, before honoring
/// next_card/mark_result at all. Example sentences are pre-generated once before the call
/// starts (not invented live), so content is fixed and known upfront.
class AgentLedVocabScreen extends ConsumerStatefulWidget {
  const AgentLedVocabScreen({
    super.key,
    required this.vocabQueue,
    this.focusNote,
    this.examplesByWordId = const {},
  });

  final List<VocabEntry> vocabQueue;
  final String? focusNote;
  final Map<String, BilingualExample> examplesByWordId;

  @override
  ConsumerState<AgentLedVocabScreen> createState() =>
      _AgentLedVocabScreenState();
}

class _AgentLedVocabScreenState extends ConsumerState<AgentLedVocabScreen>
    with WidgetsBindingObserver {
  late GeminiLiveService _gemini;
  late AudioStreamingService _audio;
  late MicController _mic;
  MicMode _micMode = MicMode.auto;
  late LearningStore _store;
  late SessionRecorder _recorder;
  late List<_VocabSessionCard> _sessionPlan;
  late Map<String, bool> _isNewById;

  CallStatus _callStatus = CallStatus.connecting;
  int _callDuration = 0;
  Timer? _timer;
  Timer? _speakingWatchdog;
  String _errorMessage = '';
  bool _finished = false;
  bool _isWrappingUp = false;

  DateTime _lastAudioChunkAt = DateTime.now();

  int _cardIndex = 0;
  int _reviewedCount = 0;

  /// Exactly which words got real practice this sitting — insertion-ordered so
  /// credit follows the ACTUAL session (the planner may reorder the queue, and
  /// back/goto moves make position-based counting lie).
  final Set<String> _practicedIds = <String>{};

  final List<String> _debugLog = [];
  final ScrollController _debugScrollController = ScrollController();

  bool _hasAttempted = false;
  int _attemptCount = 0;
  bool _wasGraded = false;
  _UserIntent _lastDetectedIntent = _UserIntent.none;

  String? _lastAttemptText;
  int _judgeGeneration = 0;

  final Set<String> _handledCallIds = {};

  // Context-aware navigation: every completed utterance is classified by Flash-Lite (with
  // the current card + Marie's last line as context) instead of keyword matching, so "yes,
  // next to the station" reads as an answer while "next word please" reads as a command.

  // Stale-verdict guard: only the newest utterance's classification may act, and only on
  // the card it was launched for. "next… wait, go back" cancels the in-flight "next".
  int _utteranceSeq = 0;

  // Marie's most recent full spoken line — judge context for echo detection and for
  // reading a bare "yes" as the answer to her own "ready to move on?" question.
  String _lastTutorLine = '';

  // Card-change announcements are debounced: a rapid "next next next" cancels the queued
  // announcement for each skipped card so Marie only ever introduces the landing card.
  Timer? _announceTimer;

  // Consent cooldown: after any card move, further navigation verdicts are ignored for a
  // beat — a duplicate/late transcript of the same command must never move twice.
  DateTime _lastCardMoveAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Words failed ('again') during THIS session — they loop back at the end
  /// until passed, instead of silently vanishing until tomorrow.
  final Set<String> _againGradedThisSession = {};
  int _againLoopRounds = 0;

  String _recentTranscriptBuffer = '';
  bool _spokenWordMatched = false;
  bool _wordPulse = false;

  // Drift enforcement: her spoken transcript streams word-by-word in lockstep with her
  // audio, so the app can SEE her start teaching a future word while the screen still shows
  // the current one — the exact "she asks 'ready for the next?' then answers herself and
  // teaches fromage" failure. Prompts alone degrade over a session; when this buffer shows
  // real teaching of a not-yet-current card (its example sentence, or repeated drilling of
  // its word), her audio is cut and a corrective note pulls her back. Offering the next
  // word by name once is allowed and won't trip this.
  String _tutorTurnTranscript = '';
  DateTime _lastDriftCorrectionAt = DateTime.fromMillisecondsSinceEpoch(0);

  // One compact line appended to every card-change note. The full rules live in the
  // system prompt; injections stay LEAN — re-stating everything on every card was bloat
  // that buried the one thing each note actually needs to say.
  static const _noteReminder =
      'Explain in English only, reciting French is practice, never a cue to switch into '
      'French-led talk. NEVER suggest moving on; the student alone decides when.';

  // Offer permission: Marie may not offer moving on until the app has counted enough
  // honest attempts (judge verdict "attempt") on the current card. She used to decide
  // this herself and would offer after ONE repetition — prompt rules alone don't hold.
  // The app now owns the counter and grants permission with a silent note; a bare "yes"
  // to a premature offer is refused (explicit commands and buttons always work).
  bool _offerUnlocked = false;

  /// Practice passes required on a NEW word before Marie may offer moving on —
  /// user-settable in Settings ("practice_passes_per_word"), default 5. Familiar words
  /// need two fewer (min 2).
  int _practicePasses = 5;

  int get _offerThreshold {
    final card = _currentCard;
    if (card == null) return 0;
    final isNew = _isNewById[card.entry.id] == true;
    return isNew
        ? _practicePasses
        : (_practicePasses - 2).clamp(2, _practicePasses);
  }

  _VocabSessionCard? get _currentCard =>
      _cardIndex < _sessionPlan.length ? _sessionPlan[_cardIndex] : null;

  // App-side floor on advancing. Judge verdicts only come from explicit student
  // commands, so the only hard floor is never skipping a word they have not tried.
  int get _minAttemptsRequired => _currentCard == null ? 0 : 1;

  BilingualExample? get _currentExample {
    final card = _currentCard;
    if (card == null) return null;
    return widget.examplesByWordId[card.entry.id];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deferred to after this frame — see pathway_writing_screen.dart for why.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Vocabulary';
    });
    _store = ref.read(learningStoreProvider);
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'vocab',
      topic: 'Vocabulary',
    );
    SharedPreferences.getInstance().then((prefs) {
      final n = prefs.getInt('practice_passes_per_word');
      if (n != null && mounted) {
        setState(() => _practicePasses = n.clamp(2, 10));
      }
    });
    _sessionPlan = widget.vocabQueue.map((e) => _VocabSessionCard(e)).toList();
    _isNewById = {
      for (final entry in widget.vocabQueue)
        entry.id: (_store.srsState(entry.id)?.reps ?? 0) == 0,
    };
    final context = _buildContext(
      _sessionPlan,
      widget.examplesByWordId,
      _isNewById,
      widget.focusNote,
      _store.profile().level,
    );
    _gemini = GeminiLiveService(
      apiKey: ApiKeys.geminiKey,
      sessionType: LiveSessionType.vocabStage,
      lessonContext: context,
      tools: AgentTool.vocabPalette,
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
  /// deliberately. Socket loss in the background is the service's problem
  /// (auto-reconnect); ours is only the microphone.
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
      // Marie opens the call — the Live API won't speak until it receives a turn, so
      // without this she'd sit silent until the student talked first. She greets and
      // introduces the first card; the student never has to prompt her.
      final first = _currentCard;
      if (first != null) {
        final example = widget.examplesByWordId[first.entry.id];
        final exampleNote = example != null
            ? ' Example sentence to teach through: "${example.fr}" (${example.en}).'
            : '';
        _gemini.injectContext(
          'The call has just connected. Greet the student warmly in one short sentence, then '
          'introduce the first word on their screen: ${first.entry.fr} = ${first.entry.en}.$exampleNote '
          'Begin teaching it with step 1.',
          expectReply: true,
        );
      }
    };

    // Service-level auto-reconnect (P0.4): only exhausted retries land here.
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
      // Re-anchor Marie on the CURRENT card: after a fresh (no-handle) reconnect
      // she has no idea where the session was, and even a resumed session deserves
      // a clean "we're back" beat rather than dead air.
      final card = _currentCard;
      if (card != null) {
        _scheduleCardAnnouncement(
          'The call connection dropped briefly and is now restored. The student\'s screen '
          'still shows "${card.entry.fr}" = "${card.entry.en}". Briefly pick that word back '
          'up as if nothing happened, do not re-greet, do not start over.',
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

  // MARK: - The gate: everything below decides whether Marie's proposals get honored

  /// Runs on every completed chunk of the student's own speech. Marks that *something*
  /// happened this card, then asks the Flash-Lite judge what the utterance actually means
  /// given the card and conversation — falling back to the keyword matcher if the judge is
  /// unavailable. Navigation is still decided and executed by the app alone.
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

    // A newer utterance always supersedes an in-flight classification — "next… wait,
    // go back" must never execute the stale "next" after the "go back" arrives.
    _utteranceSeq += 1;
    final seq = _utteranceSeq;
    final cardIndexAtLaunch = _cardIndex;
    final card = _currentCard;
    _logDebug('heard: "$trimmed" → judging…');

    () async {
      LiveIntentVerdict verdict;
      var source = 'judge';
      try {
        String cardDescription;
        if (card != null) {
          final example = widget.examplesByWordId[card.entry.id];
          cardDescription =
              'vocabulary word "${card.entry.fr}" = "${card.entry.en}"'
              '${example != null ? ', example sentence "${example.fr}"' : ''}';
        } else {
          cardDescription = '(session already finished)';
        }
        verdict = await LessonAgentService.shared.classifyLiveIntent(
          utterance: trimmed,
          cardDescription: cardDescription,
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
      // Stale guard: the world may have moved on while we were classifying.
      if (seq != _utteranceSeq || cardIndexAtLaunch != _cardIndex) {
        _logDebug('→ stale verdict (${verdict.intent.name}) discarded');
        return;
      }
      _applyIntent(verdict, utterance: trimmed, source: source);
    }();
  }

  /// The single place a classified utterance becomes action.
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
    // Consent cooldown: a duplicate/late transcript of a command that already moved the
    // card must never move it a second time.
    if (isNavigation &&
        DateTime.now().difference(_lastCardMoveAt).inMilliseconds < 1500) {
      _logDebug('→ navigation ignored (cooldown after recent card move)');
      return;
    }

    switch (verdict.intent) {
      case LiveNavIntent.attempt:
        _lastDetectedIntent = _UserIntent.none;
        _attemptCount += 1;
        _lastAttemptText = utterance;
        _maybeUnlockOffer();
      case LiveNavIntent.chat:
        _lastDetectedIntent = _UserIntent.none;
      case LiveNavIntent.again:
        _lastDetectedIntent = _UserIntent.again;
      case LiveNavIntent.advance:
        _lastDetectedIntent = _UserIntent.advance;
        if (_attemptCount < _minAttemptsRequired) {
          // The one unbreakable app-side rule: never skip a word with zero attempts.
          _logDebug(
            '→ advance blocked: only $_attemptCount/$_minAttemptsRequired attempts so far',
          );
        } else if (!verdict.explicit && !_offerUnlocked) {
          // A bare "yes" consenting to an offer Marie wasn't allowed to make yet. The
          // student's own explicit "next"/button always works — this only refuses
          // premature-offer consent, which is Marie's failure, not the student's choice.
          _refusePrematureConsent();
        } else {
          _advanceFromUserIntent();
        }
      case LiveNavIntent.back:
        _lastDetectedIntent = _UserIntent.back;
        _goBackFromUserIntent();
      case LiveNavIntent.goto:
        _goToCard(verdict.cardNumber);
      case LiveNavIntent.finish:
        // Spoken "let's finish this lesson" = the End button. All words done →
        // clean completion; otherwise the same save-and-continue-later sheet.
        _cutTutorAudio();
        _confirmEnd();
    }
  }

  /// Practice threshold reached. Marie is NOT told — offers are banned outright (she abused
  /// the permission within hours of shipping it). The flag now only (a) flips the on-screen
  /// chip to "ready when you are" so the STUDENT knows, and (b) lets a bare "yes" count as
  /// consent, covering the rare legitimate case where the student asks "should I move on?"
  /// themselves and answers her reply.
  void _maybeUnlockOffer() {
    if (_offerUnlocked || _attemptCount < _offerThreshold) return;
    if (_currentCard == null) return;
    _offerUnlocked = true;
    _logDebug(
      '→ practice threshold reached ($_attemptCount/$_offerThreshold), chip flipped',
    );
  }

  /// Marie suggested moving on (banned) and the student reflexively said "yes" — the card
  /// stays put, and she's silently told to keep practicing instead of waiting on an answer.
  void _refusePrematureConsent() {
    final card = _currentCard;
    if (card == null) return;
    _logDebug(
      '→ consent refused: premature ($_attemptCount/$_offerThreshold attempts)',
    );
    _gemini.injectContext(
      'The card did NOT move, "${card.entry.fr}" needs more practice '
      '($_attemptCount of $_offerThreshold attempts so far). You should never have suggested '
      'moving on. Smoothly continue practicing this word and never suggest advancing again.',
    );
  }

  /// Executes an advance the app itself decided on — from the judge's verdict or a direct
  /// UI tap, the two are identical from here. No model involved in the decision at all.
  void _advanceFromUserIntent() {
    if (_currentCard == null) return;
    _logDebug('→ user-driven advance');
    _cutTutorAudio();
    _performAdvance();
    final next = _currentCard;
    if (next != null) {
      // Continuity matters here: she usually just OFFERED this exact word ("want to try
      // fromage — cheese?") and the student accepted. A cold "the next word is fromage,
      // it means cheese" re-introduction right after that sounds broken — she should pick
      // up from her own offer as one continuous conversation.
      _scheduleCardAnnouncement(
        'The student accepted, the screen now shows: ${next.entry.fr} = ${next.entry.en}.'
        '${_exampleNote(next)} If you just offered this word, continue smoothly from that '
        '(no cold re-introduction): say "${next.entry.fr}" aloud with its meaning and have '
        'them repeat it. $_noteReminder',
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
        'The student asked to go back, the screen now shows: ${card.entry.fr} = '
        '${card.entry.en}.${_exampleNote(card)} Re-anchor it briefly ("We\'re back on '
        '${card.entry.fr}, ${card.entry.en}") and have them try it once. $_noteReminder',
      );
    }
  }

  /// Jump straight to a specific card by 1-based number — "go to the third card".
  /// Grading/judging of the card being left matches the back path (no silent grade).
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
    _fireBatchedJudge();
    _lastCardMoveAt = DateTime.now();
    setState(() {
      _cardIndex = target;
      _resetPerCardState();
    });
    final card = _currentCard;
    if (card != null) {
      _scheduleCardAnnouncement(
        'The student jumped to word $cardNumber, the screen now shows: ${card.entry.fr} = '
        '${card.entry.en}.${_exampleNote(card)} Announce it briefly ("Word $cardNumber: '
        '${card.entry.fr}, ${card.entry.en}") and teach it. $_noteReminder',
      );
    }
  }

  String _exampleNote(_VocabSessionCard card) {
    final example = widget.examplesByWordId[card.entry.id];
    return example != null ? ' Example: "${example.fr}" (${example.en}).' : '';
  }

  /// "Next" means the student is done listening. Her speech arrives as audio chunks WE
  /// play, so flushing the local playback queue silences her instantly — no round trip to
  /// Google — and the mic reopens right away. The follow-up announcement then tells her
  /// not to finish the amputated thought.
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

  /// Card announcements are spoken (expectReply), but debounced: a rapid "next next next"
  /// cancels each skipped card's pending announcement so Marie only introduces where the
  /// student actually landed.
  void _scheduleCardAnnouncement(String note) {
    _announceTimer?.cancel();
    _announceTimer = Timer(const Duration(milliseconds: 600), () {
      if (!_finished) _gemini.injectContext(note, expectReply: true);
    });
  }

  /// The actual card-advance side effects (grading, index, reset) — shared by the accepted
  /// tool-call path and the direct-tap path so they can never drift apart.
  void _performAdvance() {
    final card = _currentCard;
    if (_hasAttempted && !_wasGraded && card != null) {
      // Attempted but never explicitly graded: record honest, conservative
      // progress (hard = short interval), never a silent 'good' (P0.9).
      SRSService(store: _store).grade(
        entryId: card.entry.id,
        grade: SRSGrade.hard,
        responseType: SRSResponseType.auto,
      );
      _wasGraded = true;
      _againGradedThisSession.remove(card.entry.id);
    }
    if (_hasAttempted && card != null) _practicedIds.add(card.entry.id);
    _fireBatchedJudge();
    if (_currentCard != null) _reviewedCount += 1;
    _lastCardMoveAt = DateTime.now();
    setState(() {
      _cardIndex += 1;
      _resetPerCardState();
    });
  }

  void _performGoBack() {
    _fireBatchedJudge();
    _lastCardMoveAt = DateTime.now();
    setState(() {
      _cardIndex -= 1;
      _resetPerCardState();
    });
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
      case 'mark_result':
        if (_lastDetectedIntent == _UserIntent.again) {
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
        final card = _currentCard;
        if (!_hasAttempted || card == null) {
          _logDebug('→ REJECTED (no attempt yet)');
          _gemini.sendToolResponse(
            callId: callId,
            name: name,
            result: {
              'ok': false,
              'reason':
                  "The student hasn't attempted this word yet, listen for their attempt before grading.",
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
        final gradeStr = args['grade'] as String?;
        final grade = _srsGrade(gradeStr);
        if (grade != null) {
          SRSService(store: _store).grade(
            entryId: card.entry.id,
            grade: grade,
            responseType: SRSResponseType.auto,
          );
          if (grade == SRSGrade.again) {
            _againGradedThisSession.add(card.entry.id);
          } else {
            _againGradedThisSession.remove(card.entry.id);
          }
          _wasGraded = true;
          _logDebug('→ ACCEPTED, graded $gradeStr');
          _gemini.sendToolResponse(
            callId: callId,
            name: name,
            result: {'ok': true},
            scheduling: 'SILENT',
          );
        } else {
          _logDebug('→ REJECTED (bad grade arg)');
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
    _lastDetectedIntent = _UserIntent.none;
    _spokenWordMatched = false;
    _recentTranscriptBuffer = '';
    _lastAttemptText = null;
    _handledCallIds.clear();
    _offerUnlocked = false;
    // Must clear on card change: after a "go back", a word she legitimately taught earlier
    // becomes a FUTURE word again — stale mentions of it in the buffer would false-trip
    // the drift enforcer.
    _tutorTurnTranscript = '';
  }

  /// Watches her live speech transcript for the current word — the moment it appears is a
  /// reliable "she's saying it right now" signal, since output transcription streams in
  /// lockstep with the audio itself. Triggers a brief highlight pulse on the French text.
  /// Also feeds the drift enforcer, which watches the same stream for future-card teaching.
  void _handleTranscriptDelta(String delta) {
    _watchForTutorDrift(delta);
    final card = _currentCard;
    if (_spokenWordMatched || card == null) return;
    _recentTranscriptBuffer += delta;
    if (_recentTranscriptBuffer.length > 200) {
      _recentTranscriptBuffer = _recentTranscriptBuffer.substring(
        _recentTranscriptBuffer.length - 200,
      );
    }
    final target = foldFrench(card.entry.fr);
    if (target.isEmpty ||
        !foldFrench(_recentTranscriptBuffer).contains(target)) {
      return;
    }
    _spokenWordMatched = true;
    if (!mounted) return;
    setState(() => _wordPulse = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _wordPulse = false);
    });
  }

  /// The teeth behind the offer-only rule. Offering the next word is legitimate — naming it
  /// once, even with its meaning ("want to try fromage, cheese?"). TEACHING it is not, and
  /// the two are cheaply distinguishable in her live transcript: teaching means saying a
  /// future word's example sentence (examples exist only to teach through) or drilling the
  /// word repeatedly (3+ times in one turn). Either trips the enforcer: her audio is cut on
  /// the spot and a corrective note pulls her back to the on-screen card.
  void _watchForTutorDrift(String delta) {
    if (_currentCard == null) return;
    _tutorTurnTranscript += delta;
    if (_tutorTurnTranscript.length > 1500) {
      _tutorTurnTranscript = _tutorTurnTranscript.substring(
        _tutorTurnTranscript.length - 1500,
      );
    }
    // Post-correction grace: she needs a beat to say the corrective line (which itself
    // names the current word) without immediately re-tripping.
    if (DateTime.now().difference(_lastDriftCorrectionAt).inMilliseconds <
        8000) {
      return;
    }
    final folded = foldFrench(_tutorTurnTranscript);

    // Offers are BANNED — prompt rules alone leaked within hours ("want to try the next
    // word?" at 2/5 practices), so her live speech is checked for move-on suggestions and
    // cut on the spot. Grace after a card move: her legitimate announcement ("the next
    // word is fromage") uses the same phrases.
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
      ];
      if (offerPhrases.any(folded.contains)) {
        _correctIllegalOffer();
        return;
      }
    }
    for (var i = _cardIndex + 1; i < _sessionPlan.length; i++) {
      final future = _sessionPlan[i].entry;
      final fr = foldFrench(future.fr);
      if (fr.isEmpty) continue;
      final example = widget.examplesByWordId[future.id];
      final saidExample =
          example != null && folded.contains(foldFrench(example.fr));
      final wordHits = RegExp(
        '\\b${RegExp.escape(fr)}\\b',
      ).allMatches(folded).length;
      if (saidExample || wordHits >= 3) {
        _correctTutorDrift(future);
        return;
      }
    }
  }

  /// She suggested moving on — GENTLY corrected. No audio cut: chopping her mid-question
  /// was audible and wobbly in headphones, and the offer is harmless anyway (a reflexive
  /// "yes" to it is refused, the card physically can't move). She finishes her sentence
  /// naturally and a silent note pulls her back; the drift enforcer still hard-cuts the
  /// one unrecoverable case — actually teaching a card that isn't on screen.
  void _correctIllegalOffer() {
    final current = _currentCard;
    if (current == null) return;
    _lastDriftCorrectionAt = DateTime.now();
    _tutorTurnTranscript = '';
    _logDebug('→ offer slipped: silent correction, no cut');
    _gemini.injectContext(
      'You suggested moving on, never do that; the student alone decides. Do not wait for '
      'an answer to that question: continue practicing "${current.entry.fr}" = '
      '"${current.entry.en}" as if you had not asked.',
    );
  }

  void _correctTutorDrift(VocabEntry future) {
    final current = _currentCard;
    if (current == null) return;
    _lastDriftCorrectionAt = DateTime.now();
    _tutorTurnTranscript = '';
    _logDebug(
      '→ DRIFT: Marie started teaching "${future.fr}" while "${current.entry.fr}" is on screen, cutting her off',
    );
    _cutTutorAudio();
    _gemini.injectContext(
      'STOP, you started teaching "${future.fr}", but the app has NOT moved on: the student\'s '
      'screen still shows "${current.entry.fr}" = "${current.entry.en}", and only the student\'s '
      'own words move the card. You may OFFER the next word by name and then wait silently for '
      'their answer, never teach it. Pick up "${current.entry.fr}" again now, briefly, as if '
      'nothing happened.',
      expectReply: true,
    );
  }

  /// Fires exactly once per word, right as the app leaves that card (forward or back) —
  /// judges only the student's most recent attempt on it, and quietly logs a mistake tag if
  /// it looks like a genuine recurring error pattern. Never blocks the live conversation,
  /// never shown to the student, and any failure is silently swallowed since this is a pure
  /// enrichment.
  void _fireBatchedJudge() {
    _judgeGeneration += 1;
    final generation = _judgeGeneration;
    final text = _lastAttemptText;
    final card = _currentCard;
    if (text == null || card == null) return;
    final word = card.entry.fr;
    () async {
      try {
        final judgment = await LessonAgentService.shared
            .judgePronunciationAttempt(targetWord: word, studentSaid: text);
        if (generation != _judgeGeneration) return;
        if (judgment.isCorrect) return;
        final tag = judgment.tag;
        final description = judgment.description;
        if (tag == null || description == null) return;
        _store.logMistake(tag: tag, description: description);
      } catch (_) {
        // Best-effort enrichment — never surface failures.
      }
    }();
  }

  SRSGrade? _srsGrade(String? value) {
    switch (value) {
      case 'again':
        return SRSGrade.again;
      case 'good':
        return SRSGrade.good;
      case 'easy':
        return SRSGrade.easy;
      default:
        return null;
    }
  }

  void _wrapUp() {
    if (_isWrappingUp) return;
    // Again-loop (P0.6): words the learner failed this session come back for
    // another pass before the session ends — capped at 2 extra rounds so a
    // hard day still finishes.
    if (_againGradedThisSession.isNotEmpty && _againLoopRounds < 2) {
      _againLoopRounds += 1;
      final retryIds = Set<String>.from(_againGradedThisSession);
      _againGradedThisSession.clear();
      final retryCards = widget.vocabQueue
          .where((e) => retryIds.contains(e.id))
          .map((e) => _VocabSessionCard(e))
          .toList();
      if (retryCards.isNotEmpty) {
        setState(() => _sessionPlan.addAll(retryCards));
        final first = retryCards.first.entry;
        _gemini.injectContext(
          'Before wrapping up: the student struggled with ${retryCards.length} word(s) earlier, '
          'loop back through them one more time, starting with ${first.fr} = ${first.en}. '
          'Keep it light and encouraging: one quick recall attempt each, no full re-teach unless they miss it again.',
          expectReply: true,
        );
        _logDebug(
          '→ again-loop round $_againLoopRounds: ${retryCards.length} word(s) re-queued',
        );
        return;
      }
    }
    _isWrappingUp = true;
    _gemini.injectContext(
      'The student has now reviewed every word on today\'s list. Say a short warm closing line (one sentence) congratulating them, then stop talking.',
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
        stage: 'vocab',
        summary: 'Practiced $_reviewedCount word(s) in a live vocab session.',
      );
    }
    final coveredWords = widget.vocabQueue.take(_reviewedCount).toList();
    _recorder.finish(
      summary: _reviewedCount > 0
          ? 'Practiced $_reviewedCount word(s): ${coveredWords.map((e) => e.fr).join(", ")}'
          : 'Ended early, no words reviewed.',
    );
  }

  /// The only place this screen exits — pops exactly once with a typed
  /// outcome; the PathwayCoordinator decides what it means for the day.
  /// Credits the card the student is standing on when the session ends: a real
  /// attempt on it counts as practice (graded conservatively), merely landing
  /// on it does not — so word 5-of-10 goes back in the pending pile unless it
  /// was actually tried.
  void _settleCurrentCard() {
    final card = _currentCard;
    if (card == null || !_hasAttempted) return;
    if (!_wasGraded) {
      SRSService(store: _store).grade(
        entryId: card.entry.id,
        grade: SRSGrade.hard,
        responseType: SRSResponseType.auto,
      );
      _wasGraded = true;
    }
    if (_practicedIds.add(card.entry.id)) _reviewedCount += 1;
  }

  /// Word ids from today's plan that have not been practiced yet.
  List<String> get _remainingWordIds => widget.vocabQueue
      .map((e) => e.id)
      .where((id) => !_practicedIds.contains(id))
      .toList();

  void _finish({required bool completed, String reason = 'finished'}) {
    final alreadyDone = _finished;
    if (!alreadyDone) _settleCurrentCard();
    _teardown();
    if (!mounted || alreadyDone) return;
    setState(() => _callStatus = CallStatus.ended);
    final coveredWords = widget.vocabQueue
        .where((e) => _practicedIds.contains(e.id))
        .toList();
    final result = VocabStageResult(
      wordsCovered: coveredWords,
      reviewedCount: coveredWords.length,
      plannedWordIds: widget.vocabQueue.map((e) => e.id).toList(),
    );
    // Always carry the result on a pause — even zero-progress: the planned
    // word list is what lets Today offer "continue where you left off".
    final outcome = completed
        ? StageOutcome.completed(result, reason: reason)
        : StageOutcome<VocabStageResult>.paused(result: result, reason: reason);
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

  /// State-aware End: finishing the last word and tapping End IS completion —
  /// no "are you sure you want to quit" for someone who just did the work.
  /// Mid-session, the exit is framed as saving, never abandoning: practiced
  /// words keep their credit and Today offers the remaining ones later.
  Future<void> _confirmEnd() async {
    final remainingAfterThisCard = _remainingWordIds
        .where((id) => id != (_hasAttempted ? _currentCard?.entry.id : null))
        .length;
    if (remainingAfterThisCard == 0) {
      _finish(completed: true, reason: 'finished');
      return;
    }
    final done = widget.vocabQueue.length - remainingAfterThisCard;
    final shouldEnd = await showPSConfirmDialog(
      context,
      title: 'Save & continue later?',
      message:
          '$done of ${widget.vocabQueue.length} words practiced, they\'re '
          'saved. The remaining $remainingAfterThisCard will be waiting on '
          'Today when you come back.',
      confirmLabel: 'Save & exit',
      destructive: false,
    );
    if (shouldEnd && mounted) {
      _finish(completed: false, reason: 'saved_for_later');
    }
  }

  void _showAllWordsSheet() {
    showPSModalSheet(
      context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(
                children: [
                  Text(
                    "Today's words",
                    style: DesignTokens.display(16, weight: FontWeight.w500),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: widget.vocabQueue.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: DesignTokens.hairline),
                itemBuilder: (context, i) {
                  final entry = widget.vocabQueue[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.en,
                                style: DesignTokens.body(
                                  12.5,
                                ).copyWith(color: DesignTokens.slateDim),
                              ),
                              Text(
                                entry.fr,
                                style: DesignTokens.body(
                                  14,
                                  weight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          entry.phonetic,
                          style: DesignTokens.mono(
                            11,
                          ).copyWith(color: DesignTokens.slateDim),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
                tooltip: 'End vocabulary practice',
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
              IconButton(
                tooltip: "Show today's words",
                onPressed: _showAllWordsSheet,
                icon: const Icon(
                  CupertinoIcons.list_bullet,
                  size: 20,
                  color: DesignTokens.ink,
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
                'Vocabulary',
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

  Widget _content() {
    final card = _currentCard;
    if (card == null) {
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
    final example = _currentExample;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _wordPulse
                  ? DesignTokens.info
                  : DesignTokens.surface.withValues(alpha: 0),
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Text(
                card.entry.en,
                style: DesignTokens.display(24, weight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              AnimatedScale(
                scale: _wordPulse ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  card.entry.fr,
                  style: DesignTokens.display(
                    22,
                    weight: FontWeight.w500,
                  ).copyWith(color: DesignTokens.primary),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                card.entry.phonetic,
                style: DesignTokens.mono(
                  13,
                ).copyWith(color: DesignTokens.slateDim),
              ),
              const SizedBox(height: 10),
              // The pacing made visible: attempts counted so far vs. the practice passes
              // this word needs before Marie is allowed to offer moving on.
              Text(
                _offerUnlocked
                    ? 'ready when you are, say "next"'
                    : '${_attemptCount.clamp(0, _offerThreshold)} of $_offerThreshold practices',
                style: DesignTokens.body(11).copyWith(
                  color: _offerUnlocked
                      ? DesignTokens.success
                      : DesignTokens.slateDim,
                ),
              ),
            ],
          ),
        ),
        if (example != null) ...[
          const SizedBox(height: 16),
          PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const KickerText('Example', color: DesignTokens.slateDim),
                const SizedBox(height: 3),
                Text(
                  example.fr,
                  style: DesignTokens.body(13.5, weight: FontWeight.w500),
                ),
                Text(
                  example.en,
                  style: DesignTokens.body(
                    11,
                  ).copyWith(color: DesignTokens.slateDim),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Repeat the word out loud, ${_gemini.persona.displayName} is listening. Say "next" when you\'re ready, or "again" to hear it once more.',
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
                label: 'Next word',
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
    List<_VocabSessionCard> plan,
    Map<String, BilingualExample> examples,
    Map<String, bool> isNewById,
    String? focusNote,
    String learnerLevel,
  ) {
    if (plan.isEmpty) {
      return 'VOCAB STAGE: no new or due vocabulary today. Briefly tell the student there\'s nothing new to review right now and that they can end the call whenever ready.';
    }
    // Marie's English/French ratio follows the learner's self-declared level —
    // a total beginner drowning in French and an intermediate being drip-fed
    // English both churn (PILOT_PLAN.md Phase 3).
    // The student RECITING French (the target word, the example sentence) is practice, not
    // conversation — the base prompt's "if the student speaks French, respond in French"
    // rule must never fire on it, or one successful example recitation flips her into
    // French-led speech at a beginner. Stated in both branches because she escalated
    // exactly this way in testing.
    const noEscalation =
        ' ABSOLUTE RULE: RECITING IS NOT CONVERSING: when the student says the French word '
        'or example sentence, that is them PRACTICING what you asked them to repeat, never a '
        'signal that they can hold French conversation. Do not switch into French-led '
        'explanations after a good recitation, stay at exactly the same English-led level '
        'for the whole session, from first word to last.';
    final languageGuidance = LearnerLevel.isConversational(learnerLevel)
        ? 'LANGUAGE BALANCE: THIS STUDENT CAN HOLD A SIMPLE CONVERSATION: lead in clear, simple French and mirror to English only when the student seems lost or asks. Still pair every TARGET word with its English meaning once when first introduced.$noEscalation'
        : 'CRITICAL: SPEAK PRIMARILY IN ENGLISH, THIS STUDENT DOES NOT SPEAK FRENCH YET: this is a total beginner, not someone who\'s conversational and just polishing vocab. All of your own explaining, encouragement, instructions, and questions should be in English, French should only ever appear as the target word itself and its example sentence, the specific things they\'re here to learn, never as your own explanatory language. Never answer in French only, including when they ask you to repeat something ("again", "encore", "one more time"), every time you say the French word, pair it with the English meaning in the same breath (e.g. "Sure, again, \'to eat\', manger" not just "manger, manger"). If you catch yourself explaining something in French, stop and say it in English instead.$noEscalation';
    final parts = <String>[];
    parts.add(
      '''
VOCAB STAGE, this is a focused vocabulary session, nothing else. The student's screen ALREADY shows the English, French, and pronunciation for the current word the instant it appears, you never need to reveal anything.

$languageGuidance

CRITICAL: YOU DO NOT CONTROL PACING, THE STUDENT DOES: you are NOT in charge of deciding when to move to the next word or go back to a previous one, and you have no tool to do that yourself. The app is watching the student's own words directly, and when they say something like "next", "got it", or "go back", the app moves the card itself, on its own, with zero involvement from you. You'll simply be told the new current word afterward and should react to it naturally, as if you'd just turned the page together. Never say things like "let's move on" as an announcement of an action you're about to take, you aren't taking one.

THE CARD IS A ROOM, this is how the whole session works. The student chose this word; you are both in its room, and you stay there together until THEY walk out. From your point of view there is no schedule, no word list, no "rest of the lesson", the next word does not exist until the app tells you the card changed. The student is here to learn, not to be moved along: some students want two passes, some want ten, and both are exactly right. Their screen tells them how to move on when they choose; it is never your topic.

END EVERY TURN INSIDE THE ROOM: each thing you say ends with an invitation about THIS word, "try it once more", "now say it in the example sentence", "how would you ask for one at the bakery?" You never run out of material for a single word: pronunciation details, the example sentence, a tiny roleplay using it, a related everyday phrase, its gender and article, a memory trick, hearing them use it in their own sentence. If a pass went well, the natural next move is a warmer, slightly harder pass, never a question about what comes next. Never ask "ready for the next word?", "shall we continue?", or anything of the kind: pacing is the student's alone, and any answer to such a question is ignored by the app anyway.

Never explain, drill, repeat, or give the example sentence for ANY word that is not the current card on screen, the student cannot see it, and the app will cut your audio off if you teach ahead. Only once the app tells you the card has changed do you teach the new word.

You have exactly one tool: mark_result, for recording how well the student did with the current word (grade: again/good/easy). It's a proposal, the app only accepts it once it's confirmed the student actually attempted the word. A rejection is not an error; never mention it to the student, just keep teaching naturally and try again once appropriate.

CRITICAL: FOLLOW THIS EXACT ORDER FOR EVERY SINGLE WORD, DO NOT SKIP OR REORDER STEPS: being jumpy/inconsistent about this is the single biggest complaint students have, so stick to it like a script every time:
  1. Say the French word clearly, paired with its English meaning in the same breath.
  2. Ask the student to repeat it, and give them a real beat of silence to actually try.
  3. React briefly to their attempt (encouragement, or a light correction).
  4. THEN walk through the example sentence already shown on their screen, say it in French, then give the English translation, and briefly point out how today's word is being used inside it. Never skip this step and never do it before step 1-3.
Then LOOP, back to another pass, a deeper angle, a tiny roleplay with the word. There is no step 5 and no "moving on" question: the loop continues until the student themselves says next or the app tells you the card changed.
This student is a true beginner, so err toward MORE practice, not less, this is real practice time, not a formality. Follow the student's own lead within this order: if they ask to hear a word again, repeat it (bilingually, in English primarily) as many times as they want; if they say they already know it, still walk through the example sentence at least once.''',
    );

    final lines = plan
        .map((card) {
          final tag = isNewById[card.entry.id] == true ? 'NEW' : 'FAMILIAR';
          var line = '${card.entry.fr} = ${card.entry.en} [$tag]';
          final example = examples[card.entry.id];
          if (example != null) {
            line +=
                ', example already shown on screen: "${example.fr}" (${example.en})';
          }
          return line;
        })
        .join('\n');
    parts.add('TODAY\'S WORD LIST (${plan.length} words):\n$lines');
    if (focusNote != null && focusNote.isNotEmpty) {
      parts.add(
        'TODAY\'S FOCUS (mention this naturally near the start of the session): $focusNote',
      );
    }
    return parts.join('\n\n');
  }
}
