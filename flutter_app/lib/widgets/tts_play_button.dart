import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../models/tutor_persona.dart';
import '../services/lesson_speech_service.dart';
import 'progress_ring.dart';

/// A single-clip speaker/play button shared across grammar, vocabulary,
/// listening, and writing screens. States:
///  - idle: plain speaker icon, tappable.
///  - generating: an accent-colored spinning ring replaces the icon while a
///    remote clip is resolved or Gemini synthesizes this line. The phase is
///    claimed before the first await so repeated taps cannot queue duplicate
///    requests.
///  - playing: a filled/active icon while the clip sounds, reverting to
///    idle once playback finishes.
/// A line already sitting in cache still uses the same guarded transition so
/// the UI never accepts a burst of taps while its bytes are being resolved.
class TtsPlayButton extends StatefulWidget {
  const TtsPlayButton({
    super.key,
    required this.text,
    this.slow = false,
    this.contentItemId,
    this.bundledAssetPath,
    this.remoteStoragePath,
    this.cacheNamespace,
    this.audioResolver,
    this.onError,
    this.label,
    this.size = 40,
    this.iconSize = 20,
    this.color,
  });

  final String text;
  final bool slow;
  final String? contentItemId;

  /// Optional pre-generated PCM asset. When supplied, the button never calls
  /// Gemini; a missing asset is treated as an unavailable clip instead of
  /// falling back to live synthesis.
  final String? bundledAssetPath;

  /// Optional public Supabase Storage path for a pre-generated clip. If the
  /// remote file is unavailable, [bundledAssetPath] remains the fallback.
  final String? remoteStoragePath;

  /// Optional cache namespace for assets whose source must not share bytes
  /// with another provider. Static alphabet clips use this to avoid reusing
  /// an older, misassigned remote clip from the general TTS cache.
  final String? cacheNamespace;

  /// Optional resolver for generated lesson audio. When supplied, this is the
  /// complete source of PCM bytes for the button.
  final Future<List<int>?> Function()? audioResolver;

  /// Receives a playback or audio-resolution failure so the owning screen can
  /// show the real error instead of leaving the learner guessing.
  final void Function(Object error)? onError;
  final String? label;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  State<TtsPlayButton> createState() => TtsPlayButtonState();
}

enum _Phase { idle, generating, playing }

class TtsPlayButtonState extends State<TtsPlayButton> {
  _Phase _phase = _Phase.idle;
  List<int>? _readyBytes;

  /// Lets another tappable element (e.g. a big letter card the speaker icon
  /// sits inside) trigger the exact same play/cache/debounce behavior as
  /// tapping the icon itself, via a `GlobalKey<TtsPlayButtonState>`.
  Future<void> trigger() => _onTap();

  Future<void> _onTap() async {
    if (_phase != _Phase.idle) return;

    // Claim the button before any cache or network await. Previously the
    // remote/bundled lookup happened while the button still looked idle, so
    // rapid taps could start several identical loads and play them back in a
    // burst when they resolved.
    if (mounted) setState(() => _phase = _Phase.generating);

    try {
      if (_readyBytes != null) {
        await _play(_readyBytes!);
        return;
      }

      final audioResolver = widget.audioResolver;
      if (audioResolver != null) {
        // The resolver owns the PCM cache/live-generation policy. A timeout or
        // empty result is an error, not a silent no-op.
        final bytes = await audioResolver().timeout(
          const Duration(seconds: 40),
          onTimeout: () => throw StateError('Audio resolution timed out.'),
        );
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Audio resolver returned no PCM audio.');
        }
        if (mounted) {
          _readyBytes = bytes;
          await _play(bytes);
        }
        return;
      }

      final remoteStoragePath = widget.remoteStoragePath;
      if (remoteStoragePath != null) {
        final bytes = await LessonSpeechService.shared.loadRemoteAudio(
          remoteStoragePath,
          text: widget.text,
          voiceName: ActiveTutor.current.voiceName,
          slow: widget.slow,
          contentItemId: widget.contentItemId,
          cacheNamespace: widget.cacheNamespace,
        );
        if (bytes != null) {
          _readyBytes = bytes;
          if (mounted) await _play(bytes);
          return;
        }
      }

      final bundledAssetPath = widget.bundledAssetPath;
      if (bundledAssetPath != null) {
        final bytes = await LessonSpeechService.shared.loadBundledAudio(
          bundledAssetPath,
          text: widget.text,
          voiceName: ActiveTutor.current.voiceName,
          slow: widget.slow,
          contentItemId: widget.contentItemId,
          cacheNamespace: widget.cacheNamespace,
        );
        if (bytes == null) {
          throw StateError(
            'Bundled audio asset is unavailable: $bundledAssetPath',
          );
        }
        _readyBytes = bytes;
        if (mounted) await _play(bytes);
        return;
      }

      final voiceName = ActiveTutor.current.voiceName;
      // A cold Gemini request may retry after a transient rate-limit or
      // network failure. Keep the button recoverable while that happens: a
      // bounded wait prevents a grammar/listening speaker from spinning
      // forever when the provider never returns a clip.
      final bytes = await LessonSpeechService.shared
          .synthesizeWithRetry(
            widget.text,
            voiceName: voiceName,
            slow: widget.slow,
            contentItemId: widget.contentItemId,
          )
          .timeout(const Duration(seconds: 25), onTimeout: () => null);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Gemini Live returned no playable audio.');
      }
      _readyBytes = bytes;
      if (mounted) await _play(bytes);
    } catch (error) {
      debugPrint('TtsPlayButton: audio playback failed: $error');
      widget.onError?.call(error);
    } finally {
      // _play owns the transition to playing and back to idle. Only reset
      // here when loading failed or the source was unavailable.
      if (mounted && _phase == _Phase.generating) {
        setState(() => _phase = _Phase.idle);
      }
    }
  }

  @override
  void didUpdateWidget(covariant TtsPlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.bundledAssetPath != widget.bundledAssetPath ||
        oldWidget.remoteStoragePath != widget.remoteStoragePath ||
        oldWidget.cacheNamespace != widget.cacheNamespace ||
        oldWidget.audioResolver != widget.audioResolver) {
      _readyBytes = null;
    }
  }

  Future<void> _play(List<int> bytes) async {
    if (!mounted) return;
    setState(() => _phase = _Phase.playing);
    try {
      await LessonSpeechService.shared.playBytes(bytes);
      final playbackMs = (bytes.length / 2 / 24000 * 1000).round();
      await Future.delayed(Duration(milliseconds: playbackMs));
    } finally {
      // A native audio-session failure must never leave the button stuck in
      // its playing state. The learner can retry once the route is available.
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? DesignTokens.primary;
    final speakerIcon = Icon(
      _phase == _Phase.playing
          ? CupertinoIcons.speaker_3_fill
          : CupertinoIcons.speaker_2_fill,
      color: color,
      size: widget.iconSize,
    );
    final loadingIcon = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: widget.iconSize + 14,
          height: widget.iconSize + 14,
          child: SpinningRing(size: widget.iconSize + 14, color: color),
        ),
        speakerIcon,
      ],
    );
    return SizedBox(
      width: widget.label == null ? widget.size : widget.size + 72,
      height: widget.size,
      child: switch (_phase) {
        _Phase.generating => Center(child: loadingIcon),
        _Phase.idle || _Phase.playing =>
          widget.label == null
              ? IconButton(
                  onPressed: _phase == _Phase.idle ? _onTap : null,
                  icon: speakerIcon,
                )
              : OutlinedButton.icon(
                  onPressed: _phase == _Phase.idle ? _onTap : null,
                  icon: speakerIcon,
                  label: Text(widget.label!),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withValues(alpha: 0.45)),
                  ),
                ),
      },
    );
  }
}
