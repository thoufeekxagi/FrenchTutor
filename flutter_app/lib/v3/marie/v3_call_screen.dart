import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/session.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../ui/v3_ui.dart';
import 'v3_marie_session.dart';

/// Screen: a whole-screen call with the tutor. Key prefix: [keyPrefix]
/// (talk or onboarding.trial).
///
/// User arrived to: practise speaking with the tutor.
/// They must understand: the tutor is listening, what she said, and how to
/// stop.
/// Primary action: talk. Secondary actions: mute, end.
/// Success state: the call ends and the caller gets a [SpeakingResult].
/// Must not contain: a mascot, fake transcripts, or controls that start
/// anything else.
///
/// This is the same call engine as the lesson Marie (speech filter, echo
/// protection, language lock, reply limits); only the prompt differs.
class V3CallScreen extends ConsumerStatefulWidget {
  const V3CallScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.stage,
    required this.topic,
    required this.createSession,
    this.keyPrefix = 'talk',
    this.limitSeconds,
    this.wrapUpNote,
    this.wrapUpLeadSeconds = 30,
  });

  final String title;
  final String subtitle;

  /// Saved on the session row ('free_talk' or 'trial').
  final String stage;
  final String topic;
  final V3MarieSession Function() createSession;
  final String keyPrefix;

  /// A hard stop, in seconds, for the three-minute onboarding call.
  final int? limitSeconds;
  final String? wrapUpNote;
  final int wrapUpLeadSeconds;

  @override
  ConsumerState<V3CallScreen> createState() => _V3CallScreenState();
}

class _V3CallScreenState extends ConsumerState<V3CallScreen>
    with WidgetsBindingObserver {
  late final V3MarieSession _session;
  final _scroll = ScrollController();
  Timer? _ticker;
  DateTime? _liveAt;
  var _seconds = 0;
  var _wrapSent = false;
  var _finishing = false;
  var _sawLive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.createSession()..addListener(_onSession);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_session.toggle(context));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _session.handleLifecycle(state);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _session.removeListener(_onSession);
    _session.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!mounted || _finishing) return;
    if (_session.phase == V3MariePhase.live) {
      _sawLive = true;
      _liveAt ??= DateTime.now();
    }
    if (_sawLive && _session.phase == V3MariePhase.idle) {
      unawaited(_finish('ended'));
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _tick() {
    if (!mounted || _finishing || _liveAt == null) return;
    setState(() => _seconds++);
    final limit = widget.limitSeconds;
    if (limit == null) return;
    final note = widget.wrapUpNote;
    if (note != null &&
        !_wrapSent &&
        _seconds >= limit - widget.wrapUpLeadSeconds &&
        _seconds < limit) {
      _wrapSent = true;
      final s = _session;
      if (s is V3LiveMarieSession) s.call.gemini?.sendText(note);
    }
    if (_seconds >= limit) unawaited(_finish('completed'));
  }

  Future<void> _finish(String reason) async {
    if (_finishing) return;
    _finishing = true;
    _ticker?.cancel();
    final connected = _liveAt != null;
    final turns = _session.learnerTurns;
    final history = _session.history;
    await _session.end();
    if (connected) _save(history, turns);
    if (!mounted) return;
    Navigator.of(context).pop(
      SpeakingResult(
        connected: connected,
        durationSeconds: _seconds,
        learnerUtteranceCount: turns,
        endedReason: reason,
      ),
    );
  }

  void _save(List<V3MarieLine> history, int turns) {
    try {
      final storage = ref.read(storageServiceProvider);
      final now = DateTime.now();
      final id = const Uuid().v4();
      storage.saveSession(
        Session(
          id: id,
          startedAt: _liveAt!.toIso8601String(),
          endedAt: now.toIso8601String(),
          summary:
              'Spoke $turns time${turns == 1 ? '' : 's'} in '
              '${(_seconds / 60).clamp(1, 999).round()} min.',
          topic: widget.topic,
          stage: widget.stage,
        ),
      );
      for (final line in history) {
        storage.saveMessage(
          sessionId: id,
          role: line.fromMarie ? 'assistant' : 'user',
          content: line.text,
        );
      }
      if (_seconds >= 45) {
        ref
            .read(learningStoreProvider)
            .markHabit(
              'speaking',
              minutes: (_seconds / 60).clamp(1, 999).round(),
            );
      }
    } catch (_) {
      // Saving the recap must never block hanging up.
    }
  }

  String get _clock {
    final left = (widget.limitSeconds ?? 0) - _seconds;
    final m = (left.clamp(0, 9999) ~/ 60).toString();
    final s = (left.clamp(0, 9999) % 60).toString().padLeft(2, '0');
    return '$m:$s left';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.keyPrefix;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_finish('user_ended'));
      },
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.35,
        child: Scaffold(
          backgroundColor: DesignTokens.canvas,
          body: V3Width(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: ListenableBuilder(
                  listenable: _session,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          V3Pressable(
                            key: ValueKey('$p.close'),
                            label: 'End call and close',
                            onTap: () => unawaited(_finish('user_ended')),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(
                                CupertinoIcons.xmark,
                                size: 20,
                                color: DesignTokens.ink,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (widget.limitSeconds != null && _liveAt != null)
                            Text(
                              _clock,
                              key: ValueKey('$p.clock'),
                              style: V3Type.strong(14, DesignTokens.inkSoft),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(widget.title, style: V3Type.hero(30)),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: V3Type.body(15, DesignTokens.inkSoft),
                      ),
                      const SizedBox(height: 14),
                      _status(),
                      const SizedBox(height: 14),
                      Expanded(child: _transcript()),
                      const SizedBox(height: 12),
                      _controls(p),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _status() {
    final name = ActiveTutor.current.displayName;
    final (String text, Color color) = switch (_session.phase) {
      V3MariePhase.connecting => ('Connecting to $name…', DesignTokens.primary),
      V3MariePhase.error => ('Could not connect', DesignTokens.danger),
      V3MariePhase.idle => ('Ending…', DesignTokens.inkSoft),
      V3MariePhase.live =>
        _session.muted
            ? ('Muted. $name cannot hear you', DesignTokens.inkSoft)
            : _session.marieSpeaking
            ? ('$name is speaking', DesignTokens.primary)
            : ('Listening', DesignTokens.success),
    };
    return Semantics(
      liveRegion: true,
      label: text,
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: V3Type.strong(14, DesignTokens.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _transcript() {
    final name = ActiveTutor.current.displayName;
    if (_session.phase == V3MariePhase.error) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          _session.error ?? 'Check your connection and try again.',
          style: V3Type.body(16, DesignTokens.ink),
        ),
      );
    }
    final lines = [..._session.history];
    final live = _session.marieSpeaking ? _session.caption : '';
    if (live.isNotEmpty &&
        !(lines.isNotEmpty &&
            lines.last.fromMarie &&
            lines.last.text == live)) {
      lines.add(V3MarieLine(fromMarie: true, text: live));
    }
    if (lines.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          _session.phase == V3MariePhase.live ? '$name is about to start.' : '',
          style: V3Type.body(16, DesignTokens.inkSoft),
        ),
      );
    }
    return ListView.separated(
      key: ValueKey('${widget.keyPrefix}.transcript'),
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: lines.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, i) {
        final line = lines[i];
        if (line.fromMarie) {
          return Text(line.text, style: V3Type.reading(20));
        }
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: DesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(line.text, style: V3Type.body(16, DesignTokens.ink)),
          ),
        );
      },
    );
  }

  Widget _controls(String p) {
    if (_session.phase == V3MariePhase.error) {
      return V3Button(
        key: ValueKey('$p.retry'),
        label: 'Try again',
        onTap: () => unawaited(_session.toggle(context)),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_session.phase == V3MariePhase.live && _session.marieSpeaking) ...[
          V3Pressable(
            key: ValueKey('$p.skip'),
            label: 'Stop ${ActiveTutor.current.displayName} talking',
            onTap: _session.skip,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Skip',
                style: V3Type.strong(15, DesignTokens.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        if (_session.phase == V3MariePhase.live) ...[
          _round(
            key: ValueKey('$p.mute'),
            label: _session.muted ? 'Unmute microphone' : 'Mute microphone',
            icon: _session.muted
                ? CupertinoIcons.mic_slash_fill
                : CupertinoIcons.mic_fill,
            fill: _session.muted ? DesignTokens.ink : DesignTokens.surface,
            foreground: _session.muted ? DesignTokens.canvas : DesignTokens.ink,
            onTap: _session.toggleMute,
          ),
          const SizedBox(width: 18),
        ],
        _round(
          key: ValueKey('$p.end'),
          label: 'End call',
          icon: CupertinoIcons.phone_down_fill,
          fill: DesignTokens.danger,
          foreground: Colors.white,
          onTap: () => unawaited(_finish('user_ended')),
        ),
      ],
    );
  }

  Widget _round({
    required Key key,
    required String label,
    required IconData icon,
    required Color fill,
    required Color foreground,
    required VoidCallback onTap,
  }) {
    return V3Pressable(
      key: key,
      label: label,
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: DesignTokens.hairline),
          boxShadow: DesignTokens.surfaceShadow,
        ),
        child: Icon(icon, size: 26, color: foreground),
      ),
    );
  }
}
