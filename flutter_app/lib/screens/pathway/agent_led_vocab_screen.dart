import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/api_keys.dart';
import '../../config/theme.dart';
import '../../data/database/learning_store.dart';
import '../../models/agent_tool.dart';
import '../../models/content_models.dart';
import '../../models/srs_state.dart';
import '../../providers/database_provider.dart';
import '../../services/audio_streaming_service.dart';
import '../../services/gemini_live_service.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/session_recorder.dart';
import '../../flow/stage_outcome.dart';
import '../../services/srs_service.dart';
import '../../utils/text_fold.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/floating_notetaker.dart';
import '../session/session_screen.dart' show CallStatus;

class VocabStageResult {
  VocabStageResult({required this.wordsCovered, required this.reviewedCount});
  final List<VocabEntry> wordsCovered;
  final int reviewedCount;
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
  ConsumerState<AgentLedVocabScreen> createState() => _AgentLedVocabScreenState();
}

class _AgentLedVocabScreenState extends ConsumerState<AgentLedVocabScreen> {
  late GeminiLiveService _gemini;
  late AudioStreamingService _audio;
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

  final List<String> _debugLog = [];
  final ScrollController _debugScrollController = ScrollController();

  bool _hasAttempted = false;
  int _attemptCount = 0;
  bool _wasGraded = false;
  _UserIntent _lastDetectedIntent = _UserIntent.none;

  String? _lastAttemptText;
  int _judgeGeneration = 0;

  final Set<String> _handledCallIds = {};

  /// Words failed ('again') during THIS session — they loop back at the end
  /// until passed, instead of silently vanishing until tomorrow.
  final Set<String> _againGradedThisSession = {};
  int _againLoopRounds = 0;

  String _recentTranscriptBuffer = '';
  bool _spokenWordMatched = false;
  bool _wordPulse = false;

  static const _pacingReminder =
      "Reminder: this is a total beginner — explain primarily in English, using French only for "
      "the target word and its example sentence, not full French explanations. Do at least 4-5 "
      "full passes (say the word, have them repeat, react, walk through the example sentence) "
      "before you even suggest moving on — never propose it after just one or two repeats.";

  _VocabSessionCard? get _currentCard => _cardIndex < _sessionPlan.length ? _sessionPlan[_cardIndex] : null;

  // Adaptive app-side floor (P0.6): a brand-new word earns real practice
  // (4 passes), a familiar one a quick confirmation (2), a mature one a single
  // recall — not four ritual repetitions of a word the learner already owns.
  int get _minAttemptsRequired {
    final card = _currentCard;
    if (card == null) return 0;
    final state = _store.srsState(card.entry.id);
    if (state == null || state.reps == 0) return 4;
    if (state.isKnown) return 1;
    return 2;
  }

  BilingualExample? get _currentExample {
    final card = _currentCard;
    if (card == null) return null;
    return widget.examplesByWordId[card.entry.id];
  }

  @override
  void initState() {
    super.initState();
    // Deferred to after this frame — see pathway_writing_screen.dart for why.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Vocabulary';
    });
    _store = ref.read(learningStoreProvider);
    _recorder = SessionRecorder(storage: ref.read(storageServiceProvider), stage: 'vocab', topic: 'Vocabulary');
    _sessionPlan = widget.vocabQueue.map((e) => _VocabSessionCard(e)).toList();
    _isNewById = {
      for (final entry in widget.vocabQueue) entry.id: (_store.srsState(entry.id)?.reps ?? 0) == 0,
    };
    final context = _buildContext(_sessionPlan, widget.examplesByWordId, _isNewById, widget.focusNote, _store.profile().level);
    _gemini = GeminiLiveService(
      apiKey: ApiKeys.geminiKey,
      lessonContext: context,
      tools: AgentTool.vocabPalette,
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

    _gemini.onTutorTranscript = (text) => _recorder.logTutor(text);

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
      if (mounted && _callStatus != CallStatus.muted) setState(() => _callStatus = CallStatus.listening);
      if (_isWrappingUp) _finish(completed: true);
    };

    _gemini.onInterrupted = () {
      _audio.isOutputActive = false;
      _audio.stopPlayback();
      if (mounted && _callStatus != CallStatus.muted) setState(() => _callStatus = CallStatus.listening);
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
  /// happened this card, detects an explicit navigational intent if present, and fires the
  /// invisible background judge.
  void _handleUserTranscript(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _hasAttempted = true;
    final intent = _detectIntent(trimmed);
    // Always reflect the MOST RECENT utterance, never let a stale "again"/"back" from an
    // earlier turn linger and silently block future advances.
    _lastDetectedIntent = intent;
    if (intent == _UserIntent.none) {
      _attemptCount += 1;
      _lastAttemptText = trimmed;
    }
    _logDebug('heard: "$trimmed" → intent: ${intent.name}, attempts: $_attemptCount');

    switch (intent) {
      case _UserIntent.advance:
        if (_attemptCount < _minAttemptsRequired) {
          _logDebug('→ advance blocked: only $_attemptCount/$_minAttemptsRequired attempts so far');
        } else {
          _advanceFromUserIntent();
        }
      case _UserIntent.back:
        _goBackFromUserIntent();
      case _UserIntent.again:
      case _UserIntent.none:
        break;
    }
  }

  /// Executes an advance the app itself decided on — from detected speech intent or a direct
  /// UI tap, the two are identical from here. No model involved in the decision at all.
  void _advanceFromUserIntent() {
    if (_currentCard == null) return;
    _logDebug('→ user-driven advance');
    _performAdvance();
    final next = _currentCard;
    if (next != null) {
      final example = widget.examplesByWordId[next.entry.id];
      final exampleNote = example != null ? ' Example sentence to teach through: "${example.fr}" (${example.en}).' : '';
      _gemini.injectContext(
        'The student has moved on to the next word: ${next.entry.fr} = ${next.entry.en}.$exampleNote $_pacingReminder',
      );
    } else {
      _wrapUp();
    }
  }

  void _goBackFromUserIntent() {
    if (_cardIndex <= 0) return;
    _logDebug('→ user-driven go back');
    _performGoBack();
    final card = _currentCard;
    if (card != null) {
      final example = widget.examplesByWordId[card.entry.id];
      final exampleNote = example != null ? ' Example sentence to teach through: "${example.fr}" (${example.en}).' : '';
      _gemini.injectContext(
        'The student asked to go back to: ${card.entry.fr} = ${card.entry.en}.$exampleNote $_pacingReminder',
      );
    }
  }

  /// The actual card-advance side effects (grading, index, reset) — shared by the accepted
  /// tool-call path and the direct-tap path so they can never drift apart.
  void _performAdvance() {
    final card = _currentCard;
    if (_hasAttempted && !_wasGraded && card != null) {
      // Attempted but never explicitly graded: record honest, conservative
      // progress (hard = short interval), never a silent 'good' (P0.9).
      SRSService(store: _store)
          .grade(entryId: card.entry.id, grade: SRSGrade.hard, responseType: SRSResponseType.auto);
      _wasGraded = true;
      _againGradedThisSession.remove(card.entry.id);
    }
    _fireBatchedJudge();
    if (_currentCard != null) _reviewedCount += 1;
    setState(() {
      _cardIndex += 1;
      _resetPerCardState();
    });
  }

  void _performGoBack() {
    _fireBatchedJudge();
    setState(() {
      _cardIndex -= 1;
      _resetPerCardState();
    });
  }

  _UserIntent _detectIntent(String text) {
    final t = foldFrench(text);

    // Ambiguity guard: some vocab words we actually teach ("oui", "encore", "continuer") are
    // themselves navigation keywords below. If the utterance is nothing but the target word
    // itself, that's the student practicing THIS word, not issuing a command.
    final card = _currentCard;
    if (card != null) {
      final cleaned = t.replaceAll(RegExp(r'[.!?,]'), '').trim();
      final targetFr = foldFrench(card.entry.fr);
      final targetEn = foldFrench(card.entry.en);
      final words = cleaned.split(' ').where((w) => w.isNotEmpty).toList();
      if (words.isNotEmpty && targetFr.isNotEmpty && words.every((w) => w == targetFr || w == targetEn)) {
        _logDebug('→ intent suppressed: utterance is just today\'s word ("${card.entry.fr}"), treating as practice not a command');
        return _UserIntent.none;
      }
    }

    const backKeywords = ['go back', 'back to the', 'back up', 'previous word', 'previous one', 'the one before', 'word before', 'last word', 'redo the last', 'go to the last', 'revenons', 'mot précédent', 'mot precedent'];
    const againKeywords = ['again', 'repeat', 'one more time', 'say it again', 'encore', 'repete', 'repète', 'une fois de plus'];
    const advanceKeywords = ['next', 'move on', 'got it', 'i know this', 'i know', 'ready', 'continue', 'yes', 'yeah', 'yep', 'sure', 'sounds good', "let's go", "d'accord", 'suivant', 'je sais', 'on continue', 'oui'];

    if (backKeywords.any((k) => t.contains(foldFrench(k)))) return _UserIntent.back;
    if (againKeywords.any((k) => t.contains(foldFrench(k)))) return _UserIntent.again;
    if (advanceKeywords.any((k) => t.contains(foldFrench(k)))) return _UserIntent.advance;
    return _UserIntent.none;
  }

  void _handleToolCall(String name, Map<String, dynamic> args, String callId) {
    _logDebug('proposed: $name($args) [card ${_cardIndex + 1}, attempted=$_hasAttempted, intent=${_lastDetectedIntent.name}]');

    // Documented Gemini Live bug: the identical tool call can arrive twice in rapid
    // succession. If we've already handled this exact call ID, don't re-apply its side
    // effects — just acknowledge so she isn't left waiting on a response.
    if (_handledCallIds.contains(callId)) {
      _logDebug('→ DUPLICATE call ID, ignoring side effects');
      _gemini.sendToolResponse(callId: callId, name: name, result: {'ok': true}, scheduling: 'SILENT');
      return;
    }
    _handledCallIds.add(callId);

    switch (name) {
      case 'mark_result':
        if (_lastDetectedIntent == _UserIntent.again) {
          _logDebug('→ REJECTED (intent=again)');
          _gemini.sendToolResponse(callId: callId, name: name, result: {
            'ok': false,
            'reason': "The student asked to try again — don't grade yet.",
          });
          return;
        }
        final card = _currentCard;
        if (!_hasAttempted || card == null) {
          _logDebug('→ REJECTED (no attempt yet)');
          _gemini.sendToolResponse(callId: callId, name: name, result: {
            'ok': false,
            'reason': "The student hasn't attempted this word yet — listen for their attempt before grading.",
          });
          return;
        }
        if (_wasGraded) {
          _logDebug('→ already graded this instance, acknowledging only');
          _gemini.sendToolResponse(callId: callId, name: name, result: {'ok': true}, scheduling: 'SILENT');
          return;
        }
        final gradeStr = args['grade'] as String?;
        final grade = _srsGrade(gradeStr);
        if (grade != null) {
          SRSService(store: _store)
              .grade(entryId: card.entry.id, grade: grade, responseType: SRSResponseType.auto);
          if (grade == SRSGrade.again) {
            _againGradedThisSession.add(card.entry.id);
          } else {
            _againGradedThisSession.remove(card.entry.id);
          }
          _wasGraded = true;
          _logDebug('→ ACCEPTED, graded $gradeStr');
          _gemini.sendToolResponse(callId: callId, name: name, result: {'ok': true}, scheduling: 'SILENT');
        } else {
          _logDebug('→ REJECTED (bad grade arg)');
          _gemini.sendToolResponse(callId: callId, name: name, result: {'ok': false}, scheduling: 'SILENT');
        }
      default:
        _logDebug('→ unknown tool $name');
        _gemini.sendToolResponse(callId: callId, name: name, result: {'ok': false, 'error': 'unknown tool'});
    }
  }

  void _logDebug(String message) {
    final time = DateFormat.Hms().format(DateTime.now());
    setState(() {
      _debugLog.add('[$time] $message');
      if (_debugLog.length > 40) _debugLog.removeRange(0, _debugLog.length - 40);
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
  }

  /// Watches her live speech transcript for the current word — the moment it appears is a
  /// reliable "she's saying it right now" signal, since output transcription streams in
  /// lockstep with the audio itself. Triggers a brief highlight pulse on the French text.
  void _handleTranscriptDelta(String delta) {
    final card = _currentCard;
    if (_spokenWordMatched || card == null) return;
    _recentTranscriptBuffer += delta;
    if (_recentTranscriptBuffer.length > 200) {
      _recentTranscriptBuffer = _recentTranscriptBuffer.substring(_recentTranscriptBuffer.length - 200);
    }
    final target = foldFrench(card.entry.fr);
    if (target.isEmpty || !foldFrench(_recentTranscriptBuffer).contains(target)) return;
    _spokenWordMatched = true;
    if (!mounted) return;
    setState(() => _wordPulse = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _wordPulse = false);
    });
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
        final judgment = await LessonAgentService.shared.judgePronunciationAttempt(targetWord: word, studentSaid: text);
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
      case 'again': return SRSGrade.again;
      case 'good': return SRSGrade.good;
      case 'easy': return SRSGrade.easy;
      default: return null;
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
          'Before wrapping up: the student struggled with ${retryCards.length} word(s) earlier — '
          'loop back through them one more time, starting with ${first.fr} = ${first.en}. '
          'Keep it light and encouraging: one quick recall attempt each, no full re-teach unless they miss it again.',
        );
        _logDebug('→ again-loop round $_againLoopRounds: ${retryCards.length} word(s) re-queued');
        return;
      }
    }
    _isWrappingUp = true;
    _gemini.injectContext(
      'The student has now reviewed every word on today\'s list. Say a short warm closing line (one sentence) congratulating them, then stop talking.',
    );
  }

  void _teardown() {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    _speakingWatchdog?.cancel();
    _audio.stopStreaming();
    _audio.dispose();
    _gemini.disconnect();
    if (_reviewedCount > 0) {
      _store.saveDiaryEntry(stage: 'vocab', summary: 'Practiced $_reviewedCount word(s) in a live vocab session.');
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
  void _finish({required bool completed, String reason = 'finished'}) {
    final alreadyDone = _finished;
    _teardown();
    if (!mounted || alreadyDone) return;
    setState(() => _callStatus = CallStatus.ended);
    final coveredWords = widget.vocabQueue.take(_reviewedCount).toList();
    final result = VocabStageResult(wordsCovered: coveredWords, reviewedCount: _reviewedCount);
    final outcome = completed
        ? StageOutcome.completed(result, reason: reason)
        : StageOutcome<VocabStageResult>.paused(
            result: _reviewedCount > 0 ? result : null, reason: reason);
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
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End vocabulary practice?'),
        content: const Text("Words you've already reviewed are saved."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End', style: TextStyle(color: Passeport.maroon)),
          ),
        ],
      ),
    );
    if (shouldEnd == true && mounted) _finish(completed: false, reason: 'cancelled');
  }

  void _showAllWordsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Passeport.card,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(
                children: [
                  Text("Today's words", style: Passeport.display(16, weight: FontWeight.w500)),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: widget.vocabQueue.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: Passeport.hairline),
                itemBuilder: (context, i) {
                  final entry = widget.vocabQueue[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.en, style: Passeport.body(12.5).copyWith(color: Passeport.slateDim)),
                              Text(entry.fr, style: Passeport.body(14, weight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        Text(entry.phonetic, style: Passeport.mono(11).copyWith(color: Passeport.slateDim)),
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

  String _formatDuration(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  Color get _statusColor {
    switch (_callStatus) {
      case CallStatus.connecting: return Colors.orange;
      case CallStatus.listening: return Colors.green;
      case CallStatus.tutorSpeaking: return Passeport.maroon;
      case CallStatus.muted: return Passeport.slate;
      case CallStatus.ended: return Passeport.slate.withValues(alpha: 0.5);
    }
  }

  String get _statusText {
    switch (_callStatus) {
      case CallStatus.connecting: return 'connecting…';
      case CallStatus.listening: return 'listening';
      case CallStatus.tutorSpeaking: return 'Marie is speaking';
      case CallStatus.muted: return 'muted';
      case CallStatus.ended: return 'ended';
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
      backgroundColor: Passeport.parchmentDim,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _header(),
                Expanded(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16), child: _content())),
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(_errorMessage, style: Passeport.mono(12).copyWith(color: Passeport.maroon)),
                  ),
                _debugPanel(),
                _controls(),
              ],
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
              GestureDetector(onTap: _confirmEnd, child: const Icon(Icons.close, size: 20, color: Passeport.ink)),
              const Spacer(),
              Text(_formatDuration(_callDuration), style: Passeport.mono(13, weight: FontWeight.w500).copyWith(color: Passeport.slateDim)),
              const Spacer(),
              GestureDetector(
                onTap: _showAllWordsSheet,
                child: const Icon(Icons.list, size: 18, color: Passeport.ink),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          child: Column(
            children: [
              Text('Vocabulary', style: Passeport.display(20, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(
                    '${(_cardIndex + 1).clamp(1, _sessionPlan.isEmpty ? 1 : _sessionPlan.length)} of ${_sessionPlan.length} · $_statusText',
                    style: Passeport.mono(11.5).copyWith(color: Passeport.slateDim),
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
            const Icon(Icons.verified, size: 30, color: Passeport.brass),
            const SizedBox(height: 10),
            Text(_isWrappingUp ? 'Wrapping up…' : 'All done!', style: Passeport.body(14, weight: FontWeight.w500)),
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
            color: Passeport.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _wordPulse ? Passeport.brass : Colors.transparent, width: 2),
          ),
          child: Column(
            children: [
              Text(card.entry.en, style: Passeport.display(24, weight: FontWeight.w500)),
              const SizedBox(height: 10),
              AnimatedScale(
                scale: _wordPulse ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Text(card.entry.fr, style: Passeport.display(22, weight: FontWeight.w500).copyWith(color: Passeport.maroon)),
              ),
              const SizedBox(height: 4),
              Text(card.entry.phonetic, style: Passeport.mono(13).copyWith(color: Passeport.slateDim)),
            ],
          ),
        ),
        if (example != null) ...[
          const SizedBox(height: 16),
          PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const KickerText('Example', color: Passeport.slateDim),
                const SizedBox(height: 3),
                Text(example.fr, style: Passeport.body(13.5, weight: FontWeight.w500)),
                Text(example.en, style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Repeat the word out loud — Marie is listening. Say "next" when you\'re ready, or "again" to hear it once more.',
          style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _cardIndex == 0 ? null : _goBackFromUserIntent,
                icon: const Icon(Icons.chevron_left, size: 16),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Passeport.hairline),
                  foregroundColor: Passeport.text,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PasseportPrimaryButton(
                label: 'Next word',
                onPressed: _advanceFromUserIntent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _debugPanel() {
    return Container(
      height: 110,
      color: Colors.black.withValues(alpha: 0.85),
      child: ListView.builder(
        controller: _debugScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        itemCount: _debugLog.length,
        itemBuilder: (context, i) => Text(
          _debugLog[i],
          style: Passeport.mono(9.5).copyWith(color: Passeport.slateDim),
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
            icon: _callStatus == CallStatus.muted ? Icons.mic_off : Icons.mic,
            label: _callStatus == CallStatus.muted ? 'Muted' : 'Mic on',
            color: _callStatus == CallStatus.muted ? Passeport.slate : Passeport.maroon,
            onTap: (_callStatus == CallStatus.connecting || _callStatus == CallStatus.ended) ? null : _toggleMute,
          ),
          _controlButton(icon: Icons.call_end, label: 'End', color: const Color(0xFFD93333), onTap: _confirmEnd),
        ],
      ),
    );
  }

  Widget _controlButton({required IconData icon, required String label, required Color color, required VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: Passeport.mono(10).copyWith(color: Passeport.slateDim)),
        ],
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
    final languageGuidance = switch (learnerLevel) {
      'conversational' =>
        'LANGUAGE BALANCE — THIS STUDENT CAN HOLD A SIMPLE CONVERSATION: lead in clear, simple French and mirror to English only when the student seems lost or asks. Still pair every TARGET word with its English meaning once when first introduced.',
      _ =>
        'CRITICAL — SPEAK PRIMARILY IN ENGLISH, THIS STUDENT DOES NOT SPEAK FRENCH YET: this is a total beginner, not someone who\'s conversational and just polishing vocab. All of your own explaining, encouragement, instructions, and questions should be in English — French should only ever appear as the target word itself and its example sentence, the specific things they\'re here to learn, never as your own explanatory language. Never answer in French only, including when they ask you to repeat something ("again", "encore", "one more time") — every time you say the French word, pair it with the English meaning in the same breath (e.g. "Sure, again — \'to eat\', manger" not just "manger, manger"). If you catch yourself explaining something in French, stop and say it in English instead.',
    };
    final parts = <String>[];
    parts.add('''
VOCAB STAGE — this is a focused vocabulary session, nothing else. The student's screen ALREADY shows the English, French, and pronunciation for the current word the instant it appears — you never need to reveal anything.

$languageGuidance

CRITICAL — YOU DO NOT CONTROL PACING, THE STUDENT DOES: you are NOT in charge of deciding when to move to the next word or go back to a previous one, and you have no tool to do that yourself. The app is watching the student's own words directly, and the instant they say something like "next", "got it", "ready", or "go back", the app moves the card itself — instantly, on its own, with zero involvement from you. You'll simply be told the new current word afterward and should react to it naturally, as if you'd just turned the page together. Never say things like "let's move on" as an announcement of an action you're about to take — you aren't taking one. Instead, teach the current word for as long as it takes, and when it feels like a natural moment, ask a genuine question like "does that feel good? Ready for the next one?" — this is real conversation, not a mechanism, since it's the student's own answer (heard by the app, not you) that actually moves things forward.

You have exactly one tool: mark_result, for recording how well the student did with the current word (grade: again/good/easy). It's a proposal — the app only accepts it once it's confirmed the student actually attempted the word. A rejection is not an error; never mention it to the student, just keep teaching naturally and try again once appropriate.

CRITICAL — FOLLOW THIS EXACT ORDER FOR EVERY SINGLE WORD, DO NOT SKIP OR REORDER STEPS: being jumpy/inconsistent about this is the single biggest complaint students have, so stick to it like a script every time:
  1. Say the French word clearly, paired with its English meaning in the same breath.
  2. Ask the student to repeat it, and give them a real beat of silence to actually try.
  3. React briefly to their attempt (encouragement, or a light correction).
  4. THEN walk through the example sentence already shown on their screen — say it in French, then give the English translation, and briefly point out how today's word is being used inside it. Never skip this step and never do it before step 1-3.
  5. ONLY NOW ask a genuine question about moving on — e.g. "Does that feel good? Ready for the next word, or want to try it once more?" — and wait for their actual answer next turn. Never ask this before you've done steps 1 through 4.
This student is a true beginner, so err toward MORE practice, not less. Some words below are marked NEW (never studied before) — do at least 4 to 5 full passes of steps 1-4 before step 5, not one or two; this is real practice time, not a formality. Others are marked FAMILIAR (already studied) — 2 passes is enough. Above all, follow the student's own lead within this order: if they ask to hear a word again, repeat it (bilingually, in English primarily) as many times as they want before moving to step 5; if they say they already know it, don't force the full 4-5 passes, but still walk through the example sentence at least once — never skip straight from step 1 to step 5.''');

    final lines = plan.map((card) {
      final tag = isNewById[card.entry.id] == true ? 'NEW' : 'FAMILIAR';
      var line = '${card.entry.fr} = ${card.entry.en} [$tag]';
      final example = examples[card.entry.id];
      if (example != null) {
        line += ' — example already shown on screen: "${example.fr}" (${example.en})';
      }
      return line;
    }).join('\n');
    parts.add('TODAY\'S WORD LIST (${plan.length} words):\n$lines');
    if (focusNote != null && focusNote.isNotEmpty) {
      parts.add('TODAY\'S FOCUS (mention this naturally near the start of the session): $focusNote');
    }
    return parts.join('\n\n');
  }
}
