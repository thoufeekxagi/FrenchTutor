import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A small, renderer-agnostic mouth state. The renderer can use this with a
/// raster puppet, SVG layers, Rive, or a future mesh without changing the
/// audio pipeline.
enum TutorViseme { closed, neutral, wide, round, teeth }

@immutable
class TutorLipSyncFrame {
  const TutorLipSyncFrame({
    this.mouthOpen = 0,
    this.mouthWidth = 0.5,
    this.jaw = 0,
    this.energy = 0,
    this.brightness = 0,
    this.viseme = TutorViseme.closed,
  });

  final double mouthOpen;
  final double mouthWidth;
  final double jaw;
  final double energy;
  final double brightness;
  final TutorViseme viseme;

  static const resting = TutorLipSyncFrame();
}

/// Converts Gemini Live's 24 kHz mono PCM16 output into a stable, low-latency
/// mouth signal.
///
/// This is intentionally an audio-driven controller rather than a timer. A
/// simple amplitude-only jaw looks like a metronome, so it also estimates a
/// coarse spectral brightness from sample deltas and zero crossings. That is
/// enough to choose between open, wide, round, and teeth shapes without a
/// paid cloud viseme API or a native DSP dependency.
class TutorLipSyncController extends ChangeNotifier {
  TutorLipSyncFrame _frame = TutorLipSyncFrame.resting;
  bool _disposed = false;

  TutorLipSyncFrame get frame => _frame;

  /// Accepts raw little-endian mono PCM16 from Gemini Live (24 kHz).
  void pushPcm16(List<int> bytes) {
    if (_disposed || bytes.length < 4) return;

    final alignedLength = bytes.length - (bytes.length.isOdd ? 1 : 0);
    var energySum = 0.0;
    var deltaSum = 0.0;
    var zeroCrossings = 0;
    var previous = 0;
    var sampleCount = 0;

    for (var index = 0; index < alignedLength; index += 2) {
      final lo = bytes[index] & 0xff;
      final hi = bytes[index + 1];
      final sample = (hi << 8) | lo;
      final signed = sample >= 0x8000 ? sample - 0x10000 : sample;
      final normalized = signed / 32768.0;
      energySum += normalized * normalized;
      if (sampleCount > 0) {
        deltaSum += (signed - previous).abs() / 32768.0;
        if ((signed >= 0) != (previous >= 0)) zeroCrossings++;
      }
      previous = signed;
      sampleCount++;
    }

    if (sampleCount == 0) return;

    final rms = math.sqrt(energySum / sampleCount);
    final energy = ((rms - 0.008) / 0.16).clamp(0.0, 1.0).toDouble();
    final delta = (deltaSum / math.max(1, sampleCount - 1))
        .clamp(0.0, 1.0)
        .toDouble();
    final crossingRate = zeroCrossings / math.max(1, sampleCount - 1);
    final brightness = ((delta * 0.72) + (crossingRate * 1.8))
        .clamp(0.0, 1.0)
        .toDouble();

    // Attack quickly enough to follow syllables; release more gently so the
    // mouth does not snap shut between network chunks.
    final targetOpen = energy < 0.035
        ? 0.0
        : (0.10 + energy * 0.78 + brightness * 0.10).clamp(0.0, 1.0).toDouble();
    final open = _approach(
      _frame.mouthOpen,
      targetOpen,
      targetOpen > _frame.mouthOpen ? 0.72 : 0.34,
    );
    final width = _approach(
      _frame.mouthWidth,
      _targetWidth(energy: energy, brightness: brightness),
      0.55,
    );
    final jaw = _approach(_frame.jaw, open * 0.82, 0.62);
    final viseme = _viseme(open: open, energy: energy, brightness: brightness);

    _frame = TutorLipSyncFrame(
      mouthOpen: open,
      mouthWidth: width,
      jaw: jaw,
      energy: energy,
      brightness: brightness,
      viseme: viseme,
    );
    notifyListeners();
  }

  void endSpeech() {
    if (_disposed) return;
    _frame = TutorLipSyncFrame(
      mouthOpen: _approach(_frame.mouthOpen, 0, 0.58),
      mouthWidth: _approach(_frame.mouthWidth, 0.5, 0.4),
      jaw: _approach(_frame.jaw, 0, 0.58),
      energy: 0,
      brightness: 0,
      viseme: TutorViseme.closed,
    );
    notifyListeners();
  }

  static double _approach(double current, double target, double amount) =>
      current + (target - current) * amount;

  static double _targetWidth({
    required double energy,
    required double brightness,
  }) {
    if (energy < 0.035) return 0.5;
    if (brightness > 0.58) return 0.88;
    if (brightness < 0.24) return 0.34;
    return 0.58;
  }

  static TutorViseme _viseme({
    required double open,
    required double energy,
    required double brightness,
  }) {
    if (open < 0.06 || energy < 0.035) return TutorViseme.closed;
    if (brightness > 0.62) return TutorViseme.teeth;
    if (brightness < 0.23 && open > 0.22) return TutorViseme.round;
    if (open > 0.56) return TutorViseme.wide;
    return TutorViseme.neutral;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
