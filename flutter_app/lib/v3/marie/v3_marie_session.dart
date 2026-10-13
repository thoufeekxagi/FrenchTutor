import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../data/database/learning_store.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../services/inline_call_controller.dart';

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
  String? _endedNote;
  Timer? _idleTimer;

  V3MariePhase get phase;
  bool get muted;
  String? get error;

  bool get isLive => phase == V3MariePhase.live;
  bool get isBusy => phase != V3MariePhase.idle;
  bool get marieSpeaking => _marieSpeaking;

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

  /// A new step is on screen: cut any old reply, silently tell her the new
  /// step. She does not speak unless the learner does.
  void screenChanged();

  /// The same step changed (an answer was checked): silently refresh.
  void screenUpdated();

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
  }

  @protected
  void touch() {
    _idleTimer?.cancel();
    if (!isLive) return;
    _idleTimer = Timer(idleLimit, () {
      if (!isLive) return;
      _endedNote =
          'The call ended after a minute and a half of quiet. Tap the phone to talk again.';
      unawaited(end());
    });
  }

  @protected
  void marieDelta(String delta) {
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
    lessonContext: context,
    learningStoreForProfile: store(),
    onChanged: _changed,
    openingPrompt: _greeting(),
    onUserTranscript: learnerSaid,
    onTutorTranscript: marieTurn,
    onTutorTranscriptDelta: marieDelta,
    onTurnComplete: touch,
  );
  var _wasLive = false;

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
  void dispose() {
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
      'Marie is connected. If you need any assistance, feel free to talk.',
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
  void dispose() {
    _sayTimer?.cancel();
    // Leaving the lesson hangs up, like the real one.
    if (_phase != V3MariePhase.idle) V3MarieSession.debugLog.add('end');
    super.dispose();
  }
}
