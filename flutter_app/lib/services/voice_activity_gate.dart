import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

/// A small client-side VAD in front of the paid Live audio stream.
///
/// It holds a short pre-roll, requires sustained speech before opening a turn,
/// then sends the final silence and explicitly closes the turn. This keeps
/// room silence off the billable socket while preserving learner pauses and
/// the first syllable. Acoustic echo cancellation and noise suppression must
/// run before this gate; it is not an echo canceller or a speech recognizer.
class VoiceActivityGate {
  VoiceActivityGate({
    this.sampleRate = 16000,
    this.startConfirmation = const Duration(milliseconds: 360),
    this.endSilence = const Duration(milliseconds: 700),
    this.preRoll = const Duration(milliseconds: 600),
  });

  final int sampleRate;
  final Duration startConfirmation;
  final Duration endSilence;
  final Duration preRoll;

  final Queue<Uint8List> _preRoll = Queue<Uint8List>();
  int _preRollBytes = 0;
  double _noiseFloor = 0.02;
  double _candidateMs = 0;
  double _silenceMs = 0;
  bool _active = false;
  double _peak = 0;
  final List<double> _candidateRms = [];

  bool get isSpeechActive => _active;
  double get noiseFloor => _noiseFloor;
  double lastLevel = 0;
  double lastThreshold = 0;

  VoiceActivityUpdate add(Uint8List frame) {
    final durationMs = frame.length / 2 / sampleRate * 1000;
    if (durationMs <= 0) return const VoiceActivityUpdate();
    final level = _speechLevel(frame);
    final threshold = math.max(0.04, _noiseFloor * 2.2 + 0.015).toDouble();
    final speechLike = level >= threshold;
    lastLevel = level;
    lastThreshold = threshold;

    if (!_active) {
      if (!speechLike) {
        _noiseFloor = (_noiseFloor * 0.96 + level * 0.04)
            .clamp(0.008, 0.18)
            .toDouble();
      }
      final buffered = Uint8List.fromList(frame);
      _preRoll.addLast(buffered);
      _preRollBytes += buffered.length;
      final maxBytes = (preRoll.inMicroseconds / 1000000 * sampleRate * 2)
          .round();
      while (_preRollBytes > maxBytes && _preRoll.isNotEmpty) {
        _preRollBytes -= _preRoll.removeFirst().length;
      }

      if (speechLike) {
        _candidateMs += durationMs;
        _candidateRms.add(_rms(frame));
      } else {
        _candidateMs = 0;
        _candidateRms.clear();
      }
      if (_candidateMs < startConfirmation.inMicroseconds / 1000) {
        return const VoiceActivityUpdate();
      }
      // Fans, air conditioning and tones hold a near-constant level while
      // speech swings several times within a third of a second. A steady
      // signal is noise however loud, so it raises the noise floor instead.
      if (_isSteady(_candidateRms)) {
        _noiseFloor = (_noiseFloor * 0.5 + level * 0.5)
            .clamp(0.008, 0.18)
            .toDouble();
        _candidateMs = 0;
        _candidateRms.clear();
        return const VoiceActivityUpdate();
      }
      _candidateRms.clear();

      _active = true;
      _peak = level;
      _candidateMs = 0;
      _silenceMs = 0;
      final frames = List<Uint8List>.unmodifiable(_preRoll);
      _preRoll.clear();
      _preRollBytes = 0;
      return VoiceActivityUpdate(speechStarted: true, frames: frames);
    }

    // Steady chatter or music behind the learner stays above the absolute
    // threshold forever and would keep the turn open. The turn ends when the
    // level falls well below this utterance's own peak (the learner's voice).
    _peak = math.max(_peak * 0.9995, level);
    final stillSpeaking = level >= math.max(threshold, _peak * 0.4);
    _silenceMs = stillSpeaking ? 0 : _silenceMs + durationMs;
    if (_silenceMs < endSilence.inMicroseconds / 1000) {
      return VoiceActivityUpdate(frames: [Uint8List.fromList(frame)]);
    }

    // Include this final frame before the end marker so Gemini receives the
    // natural tail of the utterance and its own VAD has a clean boundary.
    _active = false;
    _silenceMs = 0;
    _candidateMs = 0;
    return VoiceActivityUpdate(
      speechEnded: true,
      frames: [Uint8List.fromList(frame)],
    );
  }

  void reset() {
    _preRoll.clear();
    _preRollBytes = 0;
    _noiseFloor = 0.02;
    _candidateMs = 0;
    _silenceMs = 0;
    _active = false;
    _peak = 0;
    _candidateRms.clear();
  }

  static bool _isSteady(List<double> rms) {
    if (rms.length < 8) return false;
    var lo = double.infinity;
    var hi = 0.0;
    var total = 0.0;
    for (final r in rms) {
      lo = math.min(lo, r);
      hi = math.max(hi, r);
      total += r;
    }
    final mean = total / rms.length;
    return mean > 0.01 && (hi - lo) < mean * 0.3;
  }

  static double _rms(Uint8List bytes) {
    var sum = 0.0;
    var n = 0;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      var v = bytes[i] | (bytes[i + 1] << 8);
      if (v >= 0x8000) v -= 0x10000;
      sum += v * v.toDouble();
      n++;
    }
    return n == 0 ? 0 : math.sqrt(sum / n) / 32768.0;
  }

  double _speechLevel(Uint8List bytes) {
    var sumSquares = 0.0;
    var peak = 0.0;
    var samples = 0;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      var sample = bytes[i] | (bytes[i + 1] << 8);
      if (sample >= 0x8000) sample -= 0x10000;
      final value = sample.abs() / 32768.0;
      sumSquares += value * value;
      if (value > peak) peak = value;
      samples++;
    }
    if (samples == 0) return 0;
    return (math.sqrt(sumSquares / samples) * 4.5 + peak * 0.15)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}

class VoiceActivityUpdate {
  const VoiceActivityUpdate({
    this.speechStarted = false,
    this.speechEnded = false,
    this.frames = const [],
  });

  final bool speechStarted;
  final bool speechEnded;
  final List<Uint8List> frames;
}
