import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/api_keys.dart';
import '../../config/theme.dart';
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
    required this.onComplete,
  });

  final ReadingPassage passage;
  final VocabStageResult? vocabSummary;
  final void Function(ListeningStageResult result) onComplete;

  @override
  ConsumerState<AgentLedListeningScreen> createState() => _AgentLedListeningScreenState();
}

class _AgentLedListeningScreenState extends ConsumerState<AgentLedListeningScreen> {
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

  _ReadingSessionCard? get _currentCard => _segmentIndex < _sessionPlan.length ? _sessionPlan[_segmentIndex] : null;

  @override
  void initState() {
    super.initState();
    _store = ref.read(learningStoreProvider);
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'reading_listening',
      topic: 'Reading & Listening',
    );
    _sessionPlan = widget.passage.segments.map((s) => _ReadingSessionCard(s)).toList();
    final context = _buildContext(widget.passage, _sessionPlan, widget.vocabSummary);
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
    _finishAndReturn();
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
        _finishAndReturn();
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
      if (_isWrappingUp) _finishAndReturn();
    };

    _gemini.onInterrupted = () {
      _audio.isOutputActive = false;
      _audio.stopPlayback();
      if (mounted && _callStatus != CallStatus.muted) setState(() => _callStatus = CallStatus.listening);
    };

    _gemini.onToolCall = _handleToolCall;

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
    _hasAttempted = true;
    final intent = _detectIntent(trimmed);
    _lastDetectedIntent = intent;
    if (intent == _ReadingUserIntent.none) _attemptCount += 1;
    _logDebug('heard: "$trimmed" → intent: ${intent.name}, attempts: $_attemptCount');
    switch (intent) {
      case _ReadingUserIntent.advance:
        _advanceFromUserIntent();
      case _ReadingUserIntent.back:
        _goBackFromUserIntent();
      case _ReadingUserIntent.again:
      case _ReadingUserIntent.none:
        break;
    }
  }

  static const _pacingReminder =
      "Reminder: this is a total beginner — explain primarily in English, using French only for "
      "the target word/phrase itself, never full French explanations. Do at least 2 full passes "
      "(read it, have them repeat, react, walk through the grammar note and pronunciation tip) "
      "before you even suggest moving on.";

  void _advanceFromUserIntent() {
    if (_currentCard == null) return;
    _logDebug('→ user-driven advance');
    _performAdvance();
    final next = _currentCard;
    if (next != null) {
      _gemini.injectContext(_contextNote(next.segment, 'The student has moved on to the next part of the passage'));
    } else {
      _wrapUp();
    }
  }

  void _goBackFromUserIntent() {
    if (_segmentIndex <= 0) return;
    _logDebug('→ user-driven go back');
    _performGoBack();
    final card = _currentCard;
    if (card != null) {
      _gemini.injectContext(_contextNote(card.segment, 'The student asked to go back to'));
    }
  }

  static String _contextNote(ReadingSegment segment, String prefix) {
    final meaning = segment.en.isEmpty ? '' : ' = ${segment.en}';
    return '$prefix: "${segment.fr}"$meaning. Grammar note to mention: ${segment.grammarNote} '
        'Pronunciation tip: ${segment.pronunciationTip} $_pacingReminder';
  }

  /// The actual card-advance side effects (grading, index, reset) — shared by the accepted
  /// tool-call path and the direct-tap path so they can never drift apart.
  void _performAdvance() {
    if (_hasAttempted && !_wasGraded) _wasGraded = true;
    if (_currentCard != null) _reviewedCount += 1;
    setState(() {
      _segmentIndex += 1;
      _resetPerCardState();
    });
  }

  void _performGoBack() {
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
      if (words.isNotEmpty && targetFr.isNotEmpty && words.every((w) => w == targetFr || w == targetEn)) {
        _logDebug('→ intent suppressed: utterance is just the current segment ("${card.segment.fr}"), treating as practice not a command');
        return _ReadingUserIntent.none;
      }
    }

    const backKeywords = ['go back', 'back to the', 'back up', 'previous', 'the one before', 'last part', 'redo the last', 'revenons'];
    const againKeywords = ['again', 'repeat', 'one more time', 'say it again', 'encore', 'repete', 'repète', 'une fois de plus'];
    const advanceKeywords = ['next', 'move on', 'got it', 'i know this', 'i know', 'ready', 'continue', 'yes', 'yeah', 'yep', 'sure', 'sounds good', "let's go", "d'accord", 'suivant', 'on continue', 'oui'];

    if (backKeywords.any((k) => t.contains(foldFrench(k)))) return _ReadingUserIntent.back;
    if (againKeywords.any((k) => t.contains(foldFrench(k)))) return _ReadingUserIntent.again;
    if (advanceKeywords.any((k) => t.contains(foldFrench(k)))) return _ReadingUserIntent.advance;
    return _ReadingUserIntent.none;
  }

  void _handleToolCall(String name, Map<String, dynamic> args, String callId) {
    _logDebug('proposed: $name($args) [segment ${_segmentIndex + 1}, attempted=$_hasAttempted, intent=${_lastDetectedIntent.name}]');

    if (_handledCallIds.contains(callId)) {
      _logDebug('→ DUPLICATE call ID, ignoring side effects');
      _gemini.sendToolResponse(callId: callId, name: name, result: {'ok': true}, scheduling: 'SILENT');
      return;
    }
    _handledCallIds.add(callId);

    switch (name) {
      case 'mark_segment_result':
        if (_lastDetectedIntent == _ReadingUserIntent.again) {
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
            'reason': "The student hasn't attempted this segment yet — listen for their attempt before grading.",
          });
          return;
        }
        if (_wasGraded) {
          _logDebug('→ already graded this instance, acknowledging only');
          _gemini.sendToolResponse(callId: callId, name: name, result: {'ok': true}, scheduling: 'SILENT');
          return;
        }
        _wasGraded = true;
        _logDebug('→ ACCEPTED');
        _gemini.sendToolResponse(callId: callId, name: name, result: {'ok': true}, scheduling: 'SILENT');
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
    _lastDetectedIntent = _ReadingUserIntent.none;
    _handledCallIds.clear();
  }

  void _wrapUp() {
    if (_isWrappingUp) return;
    _isWrappingUp = true;
    _gemini.injectContext(
      "The student has now gone through the whole passage. Say a short warm closing line (one "
      "sentence) congratulating them, then stop talking.",
    );
  }

  void _finishAndReturn() {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    _speakingWatchdog?.cancel();
    _audio.stopStreaming();
    _audio.dispose();
    _gemini.disconnect();
    if (mounted) setState(() => _callStatus = CallStatus.ended);
    if (_reviewedCount > 0) {
      _store.saveDiaryEntry(
        stage: 'reading',
        summary: 'Read through $_reviewedCount part(s) of "${widget.passage.title}" in a live reading/listening session.',
      );
    }
    _recorder.finish(
      summary: _reviewedCount > 0
          ? 'Read through $_reviewedCount part(s) of "${widget.passage.title}".'
          : 'Ended early.',
    );
    widget.onComplete(ListeningStageResult(
      grammarDrillResults: const [],
      listeningCorrect: _reviewedCount,
      listeningAttempted: _reviewedCount,
    ));
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
        title: const Text('End this section?'),
        content: const Text('Your progress so far is saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End', style: TextStyle(color: Passeport.maroon)),
          ),
        ],
      ),
    );
    if (shouldEnd == true && mounted) Navigator.of(context).pop();
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
    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      body: SafeArea(
        child: Column(
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
              Text('Reading & Listening', style: Passeport.display(20, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(
                    '${(_segmentIndex + 1).clamp(1, _sessionPlan.isEmpty ? 1 : _sessionPlan.length)} of ${_sessionPlan.length} · $_statusText',
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
    return Column(
      children: [
        PasseportCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KickerText(widget.passage.title, color: Passeport.slateDim),
              const SizedBox(height: 4),
              Text(widget.passage.fullText, style: Passeport.body(13).copyWith(color: Passeport.slateDim)),
            ],
          ),
        ),
        if (card != null) ...[
          const SizedBox(height: 14),
          PasseportCard(
            padding: 24,
            child: Column(
              children: [
                Text(card.segment.fr, style: Passeport.display(22, weight: FontWeight.w500).copyWith(color: Passeport.maroon)),
                if (card.segment.en.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(card.segment.en, style: Passeport.display(16, weight: FontWeight.w500)),
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
                    const KickerText('Grammar note', color: Passeport.slateDim),
                    const SizedBox(height: 3),
                    Text(card.segment.grammarNote, style: Passeport.body(13)),
                  ],
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const KickerText('Pronunciation', color: Passeport.slateDim),
                    const SizedBox(height: 3),
                    Text(card.segment.pronunciationTip, style: Passeport.body(13)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Repeat it out loud — Marie is listening. Say "next" when you\'re ready, or "again" to hear it once more.',
            style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim),
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
        ] else ...[
          const SizedBox(height: 14),
          PasseportCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified, size: 30, color: Passeport.brass),
                const SizedBox(height: 10),
                Text(_isWrappingUp ? 'Wrapping up…' : 'All done!', style: Passeport.body(14, weight: FontWeight.w500)),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: PasseportPrimaryButton(
                    label: 'Continue to Speaking →',
                    onPressed: _finishAndReturn,
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

CRITICAL — YOU DO NOT CONTROL PACING, THE STUDENT DOES: you are NOT in charge of deciding when to move to the next segment or go back, and you have no tool to do that yourself. The app is watching the student's own words directly, and the instant they say something like "next", "got it", "ready", or "go back", the app moves the segment itself — instantly, with zero involvement from you. You'll simply be told the new current segment afterward and should react to it naturally, as if you'd just turned the page together. Never say things like "let's move on" as an announcement of an action you're about to take.

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
      lines.add('${i + 1}. ${segment.fr}$meaning — grammar note: ${segment.grammarNote} pronunciation tip: ${segment.pronunciationTip}');
    }
    parts.add('FULL PASSAGE TEXT: ${passage.fullText}');
    parts.add('SEGMENTS IN ORDER (${plan.length}):\n${lines.join('\n')}');
    if (vocabSummary != null && vocabSummary.wordsCovered.isNotEmpty) {
      final words = vocabSummary.wordsCovered.map((e) => e.fr).join(', ');
      parts.add('VOCABULARY JUST COVERED (in the previous stage, feel free to note the connection naturally if relevant): $words');
    }
    return parts.join('\n\n');
  }
}
