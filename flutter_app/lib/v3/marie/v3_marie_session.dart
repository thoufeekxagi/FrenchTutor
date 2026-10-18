import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../data/database/learning_store.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../services/gemini_live_audio_service.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_speech_service.dart';

enum V3MariePhase { idle, connecting, live, error }

class V3MarieLine {
  const V3MarieLine({required this.fromMarie, required this.text});

  final bool fromMarie;
  final String text;
}

/// Marie, in the lesson, on the same screen. One object per lesson screen.
///
/// The screen only talks to this class: start or end the call, mute, tell her
/// the screen changed. The real implementation wraps the Gemini Live inline
/// controller. The fake one (debug builds with E2E_FAKE_AUDIO) never touches
/// the network or billing, so device tests can drive every state.
abstract class V3MarieSession extends ChangeNotifier {
  V3MarieSession({Duration? idleLimit})
    : idleLimit = idleLimit ?? const Duration(seconds: _idleSeconds);

  /// Seconds of silence before the call hangs up by itself. Tests shorten it
  /// with --dart-define=E2E_MARIE_IDLE_SECONDS=4 (ignored in release builds).
  static const _idleSeconds = int.fromEnvironment(
    'E2E_MARIE_IDLE_SECONDS',
    defaultValue: 90,
  );

  static bool get useFake =>
      kDebugMode && const bool.fromEnvironment('E2E_FAKE_AUDIO');

  /// What the fake was asked to do, for assertions in device tests.
  static final debugLog = <String>[];

  factory V3MarieSession.create({
    required LearningStore Function() store,
    required String Function() context,
  }) => useFake
      ? V3FakeMarieSession()
      : V3LiveMarieSession(store: store, context: context);

  final Duration idleLimit;
  static const maxHistory = 12;

  final _history = <V3MarieLine>[];
  String _streaming = '';
  String _caption = '';
  bool _marieSpeaking = false;
  String? _speakingText;
  bool _hideTranscript = false;
  String? _endedNote;
  Timer? _idleTimer;

  V3MariePhase get phase;
  bool get muted;
  String? get error;

  bool get isLive => phase == V3MariePhase.live;
  bool get isBusy => phase != V3MariePhase.idle;
  bool get marieSpeaking => _marieSpeaking;

  /// The line she was last asked to say, until she finishes it.
  String? get speakingText => _speakingText;

  /// Her words as she says them, then her last complete line.
  String get caption => _caption;
  List<V3MarieLine> get history => List.unmodifiable(_history);

  /// Set when the call ended by itself (silence). The screen shows it once and
  /// calls [clearEndedNote].
  String? get endedNote => _endedNote;
  void clearEndedNote() => _endedNote = null;

  Future<void> toggle(BuildContext context);
  Future<void> end();
  Future<void> toggleMute();

  /// Says [text] out loud in the selected tutor's voice, exactly as written.
  /// This is the speaker button: the old vocabulary lessons asked live Marie
  /// the same way, on one warm connection, so it is fast and always the voice
  /// the learner chose. A tap connects her (muted, no hello) if she is not
  /// already on. Returns false if she could not be reached.
  ///
  /// With [reveal] false (an unanswered listening question) her words are not
  /// shown in the pill or the conversation, so the text cannot give the answer
  /// away. She is still heard.
  Future<bool> speak(BuildContext context, String text, {bool reveal = true});

  /// Quietly makes the clips for [lines] ahead of the learner's tap so the
  /// speaker buttons answer at once. Short lines only; already saved clips are
  /// skipped. Never plays anything and never opens a call.
  void prefetch(List<String> lines) {}

  /// Cuts off what she is saying right now. The call stays open.
  Future<void> skip();

  /// A new step is on screen: cut any old reply, silently tell her the new
  /// step. She does not speak unless the learner does.
  void screenChanged();

  /// The same step changed (an answer was checked): silently refresh.
  void screenUpdated();

  /// Close the learner mic during short app-played feedback sounds so the
  /// model cannot mistake the sound for learner speech.
  void blockMicUntil(DateTime time) {}

  /// Hang up only when the app is really in the background. Split View on an
  /// iPad (notes beside the app) only makes the app inactive, and that must not
  /// end a call.
  void handleLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (isBusy) unawaited(end());
    }
  }

  // ---- shared bookkeeping for both implementations -----------------------

  @protected
  void startedCall() {
    _history.clear();
    _streaming = '';
    _caption = '';
    _marieSpeaking = false;
    _endedNote = null;
  }

  @protected
  void resetCall() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _streaming = '';
    _marieSpeaking = false;
    _speakingText = null;
    _hideTranscript = false;
  }

  @protected
  void setSpeakingText(String? text, {bool reveal = true}) {
    _speakingText = text;
    _hideTranscript = !reveal;
    notifyListeners();
  }

  @protected
  void touch() {
    _idleTimer?.cancel();
    if (!isLive) return;
    // With the microphone closed nothing is being billed, so she may stay
    // connected three times as long between speaker taps.
    _idleTimer = Timer(muted ? idleLimit * 3 : idleLimit, () {
      if (!isLive) return;
      _endedNote =
          'The call ended after a minute and a half of quiet. Tap the phone to talk again.';
      unawaited(end());
    });
  }

  @protected
  void marieDelta(String delta) {
    if (_hideTranscript) {
      _marieSpeaking = true;
      touch();
      notifyListeners();
      return;
    }
    _streaming += delta;
    _caption = _streaming.trim();
    _marieSpeaking = true;
    touch();
    notifyListeners();
  }

  @protected
  void marieTurn(String text) {
    final line = text.trim();
    _streaming = '';
    _marieSpeaking = false;
    _speakingText = null;
    if (_hideTranscript) {
      _hideTranscript = false;
      touch();
      notifyListeners();
      return;
    }
    if (line.isNotEmpty) {
      _caption = line;
      _addLine(V3MarieLine(fromMarie: true, text: line));
    }
    touch();
    notifyListeners();
  }

  @protected
  void learnerSaid(String text) {
    final line = text.trim();
    if (line.isEmpty) return;
    _addLine(V3MarieLine(fromMarie: false, text: line));
    touch();
    notifyListeners();
  }

  @protected
  void clearCaption() {
    _streaming = '';
    _caption = '';
    _marieSpeaking = false;
    _speakingText = null;
    _hideTranscript = false;
  }

  void _addLine(V3MarieLine line) {
    _history.add(line);
    if (_history.length > maxHistory) _history.removeAt(0);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}

/// Real Marie: Gemini Live through the shared inline controller.
class V3LiveMarieSession extends V3MarieSession {
  V3LiveMarieSession({
    required this.store,
    required this.context,
    super.idleLimit,
  });

  final LearningStore Function() store;
  final String Function() context;

  /// Built on the first tap, so a lesson that never calls Marie costs nothing.
  InlineCallController? _callInstance;
  InlineCallController get _call => _callInstance ??= InlineCallController(
    sessionType: LiveSessionType.lessonCoach,
    lessonContext: () =>
        'CURRENT APP STEP (the screen changed; this replaces every earlier step): ${context()}',
    setupContext: _contextWithMemory,
    learningStoreForProfile: store(),
    onChanged: _changed,
    openingPrompt: _greeting(),
    onUserTranscript: learnerSaid,
    onTutorTranscript: marieTurn,
    onTutorTranscriptDelta: marieDelta,
    onTurnComplete: touch,
  );
  var _wasLive = false;

  /// The screen plus the last few lines of this call, for every connect and
  /// reconnect. A reconnect that forgot the conversation made her introduce
  /// herself again and talk about the wrong word.
  String _contextWithMemory() => withMemory(context(), history);

  /// [base] plus the last six lines of the call. Pure, so it can be tested.
  @visibleForTesting
  static String withMemory(String base, List<V3MarieLine> history) {
    final lines = history.length <= 6
        ? history
        : history.sublist(history.length - 6);
    if (lines.isEmpty) return base;
    String cut(String v) => v.length <= 160 ? v : '${v.substring(0, 160)}...';
    final b = StringBuffer(base)
      ..write(
        '\nCALL MEMORY (earlier in this same call, so the learner already '
        'knows you):',
      );
    for (final l in lines) {
      b.write('\n- ${l.fromMarie ? 'You' : 'Learner'}: ${cut(l.text)}');
    }
    return b.toString();
  }

  static String _greeting() {
    final name = ActiveTutor.current.displayName;
    return '(App instruction, not learner speech.) The call has just connected. '
        'Say ONE short, friendly line in English so the learner knows you are '
        'connected, in your own words: that you are $name, you are connected, '
        'and if they need any help with this lesson they can just talk. Then '
        'stay quiet until they speak.';
  }

  void _changed() {
    final live = _call.active;
    if (live && !_wasLive) touch();
    if (!live && _wasLive) resetCall();
    _wasLive = live;
    notifyListeners();
  }

  @override
  V3MariePhase get phase {
    if (_callInstance == null) return V3MariePhase.idle;
    if (_call.connecting || _call.reconnecting) return V3MariePhase.connecting;
    if (_call.active) return V3MariePhase.live;
    if (_call.error != null) return V3MariePhase.error;
    return V3MariePhase.idle;
  }

  @override
  bool get muted => _callInstance?.muted ?? false;

  @override
  String? get error => _callInstance?.error;

  @override
  Future<void> toggle(BuildContext context) async {
    if (!_call.isLive) startedCall();
    await _call.toggle(context);
  }

  @override
  Future<void> end() async {
    resetCall();
    await _callInstance?.end();
    notifyListeners();
  }

  @override
  Future<void> toggleMute() async => _callInstance?.toggleMute();

  Timer? _clipTimer;
  final _prefetchQueue = <String>[];
  final _prefetchSeen = <String>{};
  var _prefetching = false;

  @override
  void prefetch(List<String> lines) {
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.length > 90 || !_prefetchSeen.add(line))
        continue;
      _prefetchQueue.add(line);
    }
    if (!_prefetching && _prefetchQueue.isNotEmpty) unawaited(_runPrefetch());
  }

  Future<void> _runPrefetch() async {
    _prefetching = true;
    final voice = ActiveTutor.current.voiceName;
    try {
      while (_prefetchQueue.isNotEmpty) {
        final line = _prefetchQueue.removeAt(0);
        try {
          final saved = await LessonSpeechService.shared.loadCachedAudio(
            line,
            voiceName: voice,
          );
          if (saved != null && saved.isNotEmpty) continue;
          await GeminiLiveAudioService.shared.generateAndCache(
            text: line,
            contentItemId: 'v3_speaker',
            voiceName: voice,
          );
        } catch (_) {
          _prefetchSeen.remove(line);
        }
      }
    } finally {
      _prefetching = false;
    }
  }

  /// A speaker tap plays a saved audio clip in the selected tutor's voice. It
  /// never opens a call and never touches the microphone: the first tap of a
  /// line makes the clip once (a few seconds), every later tap is instant and
  /// works offline. If a call is open, Marie stops talking and the microphone
  /// stays closed while the clip plays.
  @override
  Future<bool> speak(
    BuildContext context,
    String text, {
    bool reveal = true,
  }) async {
    final line = text.trim();
    if (line.isEmpty) return false;
    final voice = ActiveTutor.current.voiceName;
    try {
      final bytes =
          await LessonSpeechService.shared.loadCachedAudio(
            line,
            voiceName: voice,
          ) ??
          await GeminiLiveAudioService.shared.generateAndCache(
            text: line,
            contentItemId: 'v3_speaker',
            voiceName: voice,
          );
      if (bytes == null || bytes.isEmpty || bytes.length.isOdd) return false;
      final call = _callInstance;
      if (call != null && call.active && call.tutorTurnActive) {
        await call.interruptTutorReply();
      }
      clearCaption();
      setSpeakingText(line, reveal: false);
      await LessonSpeechService.shared.playBytes(bytes);
      _clipTimer?.cancel();
      _clipTimer = Timer(
        Duration(microseconds: (bytes.length / 2 / 24000 * 1000000).round()),
        () {
          if (_speakingText == line) setSpeakingText(null);
        },
      );
      if (call != null && call.active) touch();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> skip() async {
    final call = _callInstance;
    if (call == null || !call.active) return;
    await call.interruptTutorReply();
    clearCaption();
    notifyListeners();
  }

  @override
  void screenChanged() {
    final call = _callInstance;
    if (call == null || !call.active) return;
    // The step wins over the tail of an old reply, but the socket stays open.
    if (call.tutorTurnActive) unawaited(call.interruptTutorReply());
    clearCaption();
    call.updateLessonContext();
    notifyListeners();
  }

  @override
  void screenUpdated() {
    final call = _callInstance;
    if (call != null && call.active) call.updateLessonContext();
  }

  @override
  void blockMicUntil(DateTime time) {
    _callInstance?.audio?.blockMicUntil(time);
  }

  @override
  void dispose() {
    _clipTimer?.cancel();
    _callInstance?.dispose();
    super.dispose();
  }
}

/// A scripted Marie for device tests. Never connects anywhere.
class V3FakeMarieSession extends V3MarieSession {
  V3FakeMarieSession({super.idleLimit}) {
    current = this;
  }

  /// The most recent fake, so a test can make her "say" something.
  static V3FakeMarieSession? current;

  var _phase = V3MariePhase.idle;
  var _muted = false;
  int _generation = 0;
  Timer? _sayTimer;

  @override
  V3MariePhase get phase => _phase;

  @override
  bool get muted => _muted;

  @override
  String? get error => null;

  @override
  Future<void> toggle(BuildContext context) async {
    if (_phase != V3MariePhase.idle) {
      await end();
      return;
    }
    V3MarieSession.debugLog.add('start');
    startedCall();
    final gen = ++_generation;
    _phase = V3MariePhase.connecting;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (gen != _generation) return;
    _phase = V3MariePhase.live;
    touch();
    notifyListeners();
    debugSay(
      '${ActiveTutor.current.displayName} is connected. If you need any assistance, feel free to talk.',
    );
  }

  /// Test hook: Marie says [text], word by word, as a live caption.
  void debugSay(String text) {
    final gen = _generation;
    final words = text.split(' ');
    var i = 0;
    _sayTimer?.cancel();
    _sayTimer = Timer.periodic(const Duration(milliseconds: 40), (t) {
      if (gen != _generation || !isLive) {
        t.cancel();
        return;
      }
      if (i < words.length) {
        marieDelta('${i == 0 ? '' : ' '}${words[i]}');
        i++;
      } else {
        t.cancel();
        marieTurn(text);
      }
    });
  }

  /// Test hook: the learner "said" something.
  void debugLearnerSays(String text) => learnerSaid(text);

  @override
  Future<void> end() async {
    if (_phase == V3MariePhase.idle) return;
    V3MarieSession.debugLog.add('end');
    _generation++;
    _sayTimer?.cancel();
    _phase = V3MariePhase.idle;
    _muted = false;
    resetCall();
    notifyListeners();
  }

  @override
  Future<void> toggleMute() async {
    if (!isLive) return;
    _muted = !_muted;
    V3MarieSession.debugLog.add(_muted ? 'mute' : 'unmute');
    notifyListeners();
  }

  @override
  Future<bool> speak(
    BuildContext context,
    String text, {
    bool reveal = true,
  }) async {
    final line = text.trim();
    if (line.isEmpty || _phase == V3MariePhase.connecting) return false;
    if (_phase == V3MariePhase.idle) {
      V3MarieSession.debugLog.add('start-audio');
      startedCall();
      final gen = ++_generation;
      _phase = V3MariePhase.connecting;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (gen != _generation) return false;
      _phase = V3MariePhase.live;
      _muted = true;
      touch();
      notifyListeners();
    }
    V3MarieSession.debugLog.add('speak:$line');
    setSpeakingText(line, reveal: reveal);
    debugSay(line);
    return true;
  }

  @override
  Future<void> skip() async {
    if (!isLive) return;
    V3MarieSession.debugLog.add('skip');
    _generation++;
    _sayTimer?.cancel();
    clearCaption();
    notifyListeners();
  }

  @override
  void screenChanged() {
    if (!isLive) return;
    V3MarieSession.debugLog.add('context:step');
    _generation++;
    _sayTimer?.cancel();
    clearCaption();
    notifyListeners();
  }

  @override
  void screenUpdated() {
    if (isLive) V3MarieSession.debugLog.add('context:update');
  }

  @override
  void blockMicUntil(DateTime time) {
    V3MarieSession.debugLog.add('feedback-mic-blocked');
  }

  @override
  void dispose() {
    _sayTimer?.cancel();
    // Leaving the lesson hangs up, like the real one.
    if (_phase != V3MariePhase.idle) V3MarieSession.debugLog.add('end');
    super.dispose();
  }
}
