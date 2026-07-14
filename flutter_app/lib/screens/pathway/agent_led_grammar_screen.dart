import '../../widgets/adaptive/adaptive.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/api_keys.dart';
import '../../config/theme.dart';
import '../../flow/stage_outcome.dart';
import '../../data/database/learning_store.dart';
import '../../models/agent_tool.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/audio_streaming_service.dart';
import '../../services/gemini_live_service.dart';
import '../../services/session_recorder.dart';
import '../../utils/text_fold.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/floating_notetaker.dart';
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
  ConsumerState<AgentLedGrammarScreen> createState() => _AgentLedGrammarScreenState();
}

class _AgentLedGrammarScreenState extends ConsumerState<AgentLedGrammarScreen> {
  late GeminiLiveService _gemini;
  late AudioStreamingService _audio;
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

  String _recentTranscriptBuffer = '';
  bool _spokenSentenceMatched = false;
  bool _sentencePulse = false;

  static const _pacingReminder =
      "Reminder: this is a total beginner — explain primarily in English, using French only for "
      "the target sentence itself, not full French explanations. Keep grammar SIMPLE — no "
      "advanced tense talk beyond the note shown, this is intentionally basic for now. Do at "
      "least one full pass (say the sentence, have them repeat it, react, explain the grammar "
      "note) before you even suggest moving on.";

  _GrammarSessionCard? get _currentCard => _cardIndex < _sessionPlan.length ? _sessionPlan[_cardIndex] : null;

  @override
  void initState() {
    super.initState();
    // Deferred to after this frame — see pathway_writing_screen.dart for why.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Grammar';
    });
    _store = ref.read(learningStoreProvider);
    _topicId = 'grammar_${widget.tenseTitle.toLowerCase().replaceAll(' ', '_')}';
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'grammar',
      topic: 'Grammar — ${widget.tenseTitle}',
    );
    _sessionPlan = widget.cards.map((c) => _GrammarSessionCard(c)).toList();
    final context = _buildContext(widget.tenseTitle, _sessionPlan, widget.focusNote, widget.vocabSummary);
    _gemini = GeminiLiveService(
      apiKey: ApiKeys.geminiKey,
      lessonContext: context,
      tools: AgentTool.grammarPalette,
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

  // MARK: - The gate: same shape as vocab, walking one generated sentence card at a time

  void _handleUserTranscript(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _hasAttempted = true;
    final intent = _detectIntent(trimmed);
    _lastDetectedIntent = intent;
    _logDebug('heard: "$trimmed" → intent: ${intent.name}');
    switch (intent) {
      case _GrammarUserIntent.advance:
        _advanceFromUserIntent();
      case _GrammarUserIntent.back:
        _goBackFromUserIntent();
      case _GrammarUserIntent.again:
      case _GrammarUserIntent.none:
        break;
    }
  }

  void _advanceFromUserIntent() {
    if (_currentCard == null) return;
    _logDebug('→ user-driven advance');
    _performAdvance();
    final next = _currentCard;
    if (next != null) {
      _gemini.injectContext(
        'The student has moved on to the next sentence: "${next.card.fr}" (${next.card.en}). '
        'Grammar note: ${next.card.note} $_pacingReminder',
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
      _gemini.injectContext(
        'The student asked to go back to: "${card.card.fr}" (${card.card.en}). '
        'Grammar note: ${card.card.note} $_pacingReminder',
      );
    }
  }

  /// The actual card-advance side effects (grading, index, reset) — shared by the accepted
  /// tool-call path and the direct-tap path so they can never drift apart.
  void _performAdvance() {
    if (_hasAttempted && !_wasGraded) {
      _drillResults.add(_lastDetectedIntent != _GrammarUserIntent.again);
      _wasGraded = true;
    }
    setState(() {
      _cardIndex += 1;
      _resetPerCardState();
    });
  }

  void _performGoBack() {
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
        _logDebug('→ intent suppressed: utterance is just today\'s sentence, treating as practice not a command');
        return _GrammarUserIntent.none;
      }
    }

    const backKeywords = ['go back', 'back to the', 'back up', 'previous', 'the one before', 'last sentence', 'redo the last', 'revenons'];
    const againKeywords = ['again', 'repeat', 'one more time', 'say it again', 'encore', 'repete', 'repète', 'une fois de plus'];
    const advanceKeywords = ['next', 'move on', 'got it', 'i know this', 'i know', 'ready', 'continue', 'yes', 'yeah', 'yep', 'sure', 'sounds good', "let's go", "d'accord", 'suivant', 'on continue', 'oui'];

    if (backKeywords.any((k) => t.contains(foldFrench(k)))) return _GrammarUserIntent.back;
    if (againKeywords.any((k) => t.contains(foldFrench(k)))) return _GrammarUserIntent.again;
    if (advanceKeywords.any((k) => t.contains(foldFrench(k)))) return _GrammarUserIntent.advance;
    return _GrammarUserIntent.none;
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
      case 'mark_drill_result':
        if (_lastDetectedIntent == _GrammarUserIntent.again) {
          _logDebug('→ REJECTED (intent=again)');
          _gemini.sendToolResponse(callId: callId, name: name, result: {
            'ok': false,
            'reason': "The student asked to try again — don't grade yet.",
          });
          return;
        }
        if (!_hasAttempted || _currentCard == null) {
          _logDebug('→ REJECTED (no attempt yet)');
          _gemini.sendToolResponse(callId: callId, name: name, result: {
            'ok': false,
            'reason': "The student hasn't attempted this sentence yet.",
          });
          return;
        }
        if (_wasGraded) {
          _logDebug('→ already graded this instance, acknowledging only');
          _gemini.sendToolResponse(callId: callId, name: name, result: {'ok': true}, scheduling: 'SILENT');
          return;
        }
        final correct = args['correct'] as bool?;
        if (correct != null) {
          _drillResults.add(correct);
          _wasGraded = true;
          _logDebug('→ ACCEPTED, correct=$correct');
          _gemini.sendToolResponse(callId: callId, name: name, result: {'ok': true}, scheduling: 'SILENT');
        } else {
          _logDebug('→ REJECTED (bad correct arg)');
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
    _wasGraded = false;
    _lastDetectedIntent = _GrammarUserIntent.none;
    _spokenSentenceMatched = false;
    _recentTranscriptBuffer = '';
    _handledCallIds.clear();
  }

  /// Watches her live speech transcript for the current sentence — the moment it appears is a
  /// reliable "she's saying it right now" signal, since output transcription streams in
  /// lockstep with the audio itself. Triggers a brief highlight pulse on the French text.
  void _handleTranscriptDelta(String delta) {
    final card = _currentCard;
    if (_spokenSentenceMatched || card == null) return;
    _recentTranscriptBuffer += delta;
    if (_recentTranscriptBuffer.length > 300) {
      _recentTranscriptBuffer = _recentTranscriptBuffer.substring(_recentTranscriptBuffer.length - 300);
    }
    final target = foldFrench(card.card.fr);
    if (target.isEmpty || !foldFrench(_recentTranscriptBuffer).contains(target)) return;
    _spokenSentenceMatched = true;
    if (!mounted) return;
    setState(() => _sentencePulse = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _sentencePulse = false);
    });
  }

  void _wrapUp() {
    if (_isWrappingUp) return;
    _isWrappingUp = true;
    _gemini.injectContext(
      'The student has now gone through today\'s grammar practice. Say a short warm closing line '
      '(one sentence) congratulating them, then stop talking.',
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
    if (_cardIndex > 0) {
      final score = _drillResults.isEmpty ? null : _drillResults.where((r) => r).length / _drillResults.length;
      _store.setLessonStatus(_topicId, (score ?? 1.0) >= 0.8 ? 'completed' : 'in_progress', score: score);
      _store.saveDiaryEntry(stage: 'grammar', summary: 'Practiced ${widget.tenseTitle} in a live grammar session.');
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
    final result = GrammarStageResult(topicTitle: widget.tenseTitle, drillResults: _drillResults);
    final outcome = completed
        ? StageOutcome.completed(result, reason: reason)
        : StageOutcome<GrammarStageResult>.paused(
            result: _drillResults.isNotEmpty ? result : null, reason: reason);
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
      title: 'End grammar practice?',
      message: "Your progress so far is saved.",
      confirmLabel: 'End',
      destructive: true,
    );
    if (shouldEnd && mounted) _finish(completed: false, reason: 'cancelled');
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
              Container(width: 10, height: 10, decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          child: Column(
            children: [
              Text('Grammar — ${widget.tenseTitle}', style: Passeport.display(19, weight: FontWeight.w600)),
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
            const Icon(Icons.verified, size: 30, color: Passeport.brass),
            const SizedBox(height: 10),
            Text(_isWrappingUp ? 'Wrapping up…' : 'All done!', style: Passeport.body(14, weight: FontWeight.w500)),
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
            color: Passeport.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _sentencePulse ? Passeport.brass : Colors.transparent, width: 2),
          ),
          child: Column(
            children: [
              Text(card.en, style: Passeport.display(20, weight: FontWeight.w500)),
              const SizedBox(height: 10),
              AnimatedScale(
                scale: _sentencePulse ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  card.fr,
                  style: Passeport.display(20, weight: FontWeight.w500).copyWith(color: Passeport.maroon),
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
                const KickerText('Grammar note', color: Passeport.slateDim),
                const SizedBox(height: 3),
                Text(card.note, style: Passeport.body(13, weight: FontWeight.w500)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Say the sentence out loud — Marie is listening. Say "next" when you\'re ready, or "again" to hear it once more.',
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
                label: 'Next',
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

CRITICAL — YOU DO NOT CONTROL PACING, THE STUDENT DOES: you have no tool to advance or go back. The app watches the student's own words directly and moves the card itself the instant they say something like "next" or "go back" — zero involvement from you. You'll simply be told the new current sentence afterward and should react to it naturally.

You have exactly one tool: mark_drill_result, for recording whether the student's spoken answer to the current sentence was correct. It's a proposal — the app only accepts it once it's confirmed the student actually attempted the sentence. A rejection is not an error; never mention it, just keep teaching naturally.

CRITICAL — FOLLOW THIS EXACT ORDER FOR EVERY SENTENCE:
  1. Say the French sentence clearly, paired with its English meaning.
  2. Ask the student to repeat it, and give them a real beat of silence to actually try.
  3. React briefly to their attempt.
  4. THEN explain the grammar note already shown on screen, in plain simple English.
  5. ONLY NOW ask if they're ready to move on, and wait for their actual answer.
Keep grammar explanations SIMPLE — no advanced tense talk beyond the note shown, this is intentionally basic for now; a harder/dynamic-difficulty version comes later.
''');
    final lines = <String>[];
    for (var i = 0; i < plan.length; i++) {
      final session = plan[i];
      lines.add('${i + 1}. ${session.card.fr} = ${session.card.en} — ${session.card.note}');
    }
    parts.add("TODAY'S SENTENCES (${plan.length}):\n${lines.join('\n')}");
    if (focusNote != null && focusNote.isNotEmpty) {
      parts.add('TODAY\'S FOCUS (mention this naturally near the start): $focusNote');
    }
    if (vocabSummary != null && vocabSummary.wordsCovered.isNotEmpty) {
      final words = vocabSummary.wordsCovered.map((e) => e.fr).join(', ');
      parts.add('VOCABULARY JUST COVERED (previous stage, these sentences reuse some of these words): $words');
    }
    return parts.join('\n\n');
  }
}
