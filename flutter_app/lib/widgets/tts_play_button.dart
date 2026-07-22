import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../models/tutor_persona.dart';
import '../services/lesson_speech_service.dart';
import 'progress_ring.dart';

/// A single-clip speaker/play button shared across grammar, vocabulary,
/// listening, and writing screens. States:
///  - idle: plain speaker icon, tappable.
///  - generating: a green spinning ring replaces the icon while Gemini
///    synthesizes this line for the first time — this only ever happens
///    once per line, ever, since every synthesis is cached (see
///    `LessonSpeechService`). Once generation finishes the button reverts to
///    idle — the tap that started it does not auto-play; the learner taps
///    again to actually hear it (a completed download revealing a "ready"
///    state, not a surprise autoplay).
///  - playing: a filled/active icon while the clip sounds, reverting to
///    idle once playback finishes.
/// A line already sitting in cache (from an earlier tap, an earlier
/// session, or another learner who hit this exact content first) never
/// shows the ring at all — it plays immediately, indistinguishable from any
/// other idle→playing tap.
class TtsPlayButton extends StatefulWidget {
  const TtsPlayButton({
    super.key,
    required this.text,
    this.slow = false,
    this.contentItemId,
    this.size = 40,
    this.iconSize = 20,
    this.color,
  });

  final String text;
  final bool slow;
  final String? contentItemId;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  State<TtsPlayButton> createState() => _TtsPlayButtonState();
}

enum _Phase { idle, generating, playing }

class _TtsPlayButtonState extends State<TtsPlayButton> {
  _Phase _phase = _Phase.idle;
  List<int>? _readyBytes;

  Future<void> _onTap() async {
    if (_phase != _Phase.idle) return;
    final voiceName = ActiveTutor.current.voiceName;

    if (_readyBytes != null) {
      await _play(_readyBytes!);
      return;
    }

    final alreadyCached = LessonSpeechService.shared.isCached(
      widget.text,
      voiceName: voiceName,
      slow: widget.slow,
    );
    if (alreadyCached) {
      final bytes = await LessonSpeechService.shared.synthesizeWithRetry(
        widget.text,
        voiceName: voiceName,
        slow: widget.slow,
        contentItemId: widget.contentItemId,
      );
      if (bytes != null) await _play(bytes);
      return;
    }

    if (!mounted) return;
    setState(() => _phase = _Phase.generating);
    final bytes = await LessonSpeechService.shared.synthesizeWithRetry(
      widget.text,
      voiceName: voiceName,
      slow: widget.slow,
      contentItemId: widget.contentItemId,
    );
    _readyBytes = bytes;
    if (!mounted) return;
    setState(() => _phase = _Phase.idle);
  }

  Future<void> _play(List<int> bytes) async {
    if (!mounted) return;
    setState(() => _phase = _Phase.playing);
    await LessonSpeechService.shared.playBytes(bytes);
    final playbackMs = (bytes.length / 2 / 24000 * 1000).round();
    await Future.delayed(Duration(milliseconds: playbackMs));
    if (!mounted) return;
    setState(() => _phase = _Phase.idle);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? DesignTokens.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: switch (_phase) {
        _Phase.generating => Center(
          child: SpinningRing(size: widget.size * 0.75, color: DesignTokens.success),
        ),
        _Phase.idle || _Phase.playing => IconButton(
          onPressed: _phase == _Phase.idle ? _onTap : null,
          icon: Icon(
            _phase == _Phase.playing
                ? CupertinoIcons.speaker_3_fill
                : CupertinoIcons.speaker_2_fill,
            color: color,
            size: widget.iconSize,
          ),
        ),
      },
    );
  }
}
