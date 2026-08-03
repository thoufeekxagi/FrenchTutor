import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

import 'audio_streaming_service.dart';

/// Selected by the conditional import in `audio_streaming_service.dart` on web.
AudioStreamingService createAudioStreamingService() =>
    WebAudioStreamingService();

/// The AudioWorklet processor, as source. It is injected via a Blob URL rather
/// than shipped as a separate `web/*.js` asset so this whole implementation
/// stays in one Dart file with nothing to keep in sync at deploy time.
///
/// An AudioWorklet (not the deprecated ScriptProcessorNode) is used because it
/// runs on the dedicated audio render thread: mic capture keeps producing
/// evenly-spaced frames even while the Flutter UI is busy laying out a lesson
/// screen. ScriptProcessorNode runs on the main thread and drops frames under
/// exactly that load, which is audible as clipped words.
///
/// It forwards raw Float32 frames untouched; all PCM16 conversion happens in
/// Dart so the format logic lives next to the rest of the audio code.
const _captureWorkletSource = r'''
class PcmCaptureProcessor extends AudioWorkletProcessor {
  process(inputs) {
    const input = inputs[0];
    if (input && input.length > 0 && input[0] && input[0].length > 0) {
      // Copy: the underlying buffer is reused by the audio thread between
      // render quanta, so posting it directly would deliver mutated samples.
      this.port.postMessage(new Float32Array(input[0]));
    }
    return true;
  }
}
registerProcessor('pcm-capture', PcmCaptureProcessor);
''';

class WebAudioStreamingService implements AudioStreamingService {
  // The browser resamples for us: constructing each AudioContext at the exact
  // rate Gemini expects means no hand-written interpolation anywhere. Input and
  // output need different rates, hence two contexts.
  static const _inputSampleRate = 16000;
  static const _outputSampleRate = 24000;

  web.AudioContext? _inputContext;
  web.AudioContext? _outputContext;
  web.MediaStream? _micStream;
  web.MediaStreamAudioSourceNode? _micSource;
  web.AudioWorkletNode? _captureNode;

  void Function(List<int> chunk)? _onChunk;
  bool _isStreaming = false;
  bool _starting = false;

  /// Scheduled-playback cursor, in the output context's clock. Web Audio gives
  /// us sample-accurate scheduling, so gapless playback of network-bursty
  /// chunks is just "start each one where the last one ended" — no drain loop
  /// or hand-managed queue like the native implementation needs.
  double _nextStartTime = 0;
  final List<web.AudioBufferSourceNode> _scheduled = [];

  /// A PCM16 sample is 2 bytes and Gemini's chunk boundaries do not respect
  /// that, so a chunk can carry an odd byte count that splits a sample. Feeding
  /// a misaligned buffer shifts every sample after it (audible as gargled
  /// robotic playback), so the stray byte rides along to the next chunk. Same
  /// hazard, and same fix, as the native implementation.
  int? _pendingOddByte;

  @override
  bool isOutputActive = false;

  /// Mirrors the native implementation: `isOutputActive` goes false the moment
  /// the server signals turnComplete, but audio already scheduled keeps
  /// physically playing for a while after. Reopening the mic at turnComplete
  /// would capture the tail of the tutor's own voice as fresh user speech.
  static const _playbackTailGraceSeconds = 0.35;

  /// Barge-in is disabled for the same reason it is on native: Gemini Live's
  /// server-side VAD treats any sound during generation as an interruption and
  /// makes the tutor stutter and restart. See the native implementation for the
  /// full rationale.
  static const _allowBargeIn = false;

  @override
  Future<bool> requestPermission() async {
    // In a browser there is no reliable "ask without opening the mic" query:
    // calling getUserMedia IS the permission prompt. The stream is kept for
    // startStreaming rather than opened twice, which would prompt twice in
    // some browsers.
    try {
      final constraints = web.MediaStreamConstraints(
        audio: web.MediaTrackConstraints(
          // Echo cancellation stays OFF to match native, where it measurably
          // degrades output quality; the mic is gated during the tutor's turn
          // instead. Noise suppression and AGC are left to the browser default.
          echoCancellation: false.toJS,
          channelCount: 1.toJS,
        ).jsify()!,
      );
      _micStream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      return true;
    } catch (e) {
      debugPrint(
        'WebAudioStreamingService: mic permission denied or '
        'unavailable: $e',
      );
      return false;
    }
  }

  @override
  Future<void> startStreaming({
    required void Function(List<int> chunk) onChunk,
  }) async {
    if (_isStreaming || _starting) return;
    _starting = true;
    try {
      _onChunk = onChunk;

      // requestPermission() normally already opened this; tolerate being
      // called without it.
      _micStream ??= await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(
              audio: web.MediaTrackConstraints(
                echoCancellation: false.toJS,
                channelCount: 1.toJS,
              ).jsify()!,
            ),
          )
          .toDart;

      final ctx = web.AudioContext(
        web.AudioContextOptions(sampleRate: _inputSampleRate),
      );
      _inputContext = ctx;

      final blob = web.Blob(
        [_captureWorkletSource.toJS].toJS,
        web.BlobPropertyBag(type: 'application/javascript'),
      );
      final url = web.URL.createObjectURL(blob);
      try {
        await ctx.audioWorklet.addModule(url).toDart;
      } finally {
        web.URL.revokeObjectURL(url);
      }

      final node = web.AudioWorkletNode(ctx, 'pcm-capture');
      _captureNode = node;
      node.port.onmessage = (web.MessageEvent event) {
        _handleMicFrame(event.data as JSFloat32Array);
      }.toJS;

      _micSource = ctx.createMediaStreamSource(_micStream!);
      _micSource!.connect(node);
      // Deliberately NOT connected to ctx.destination: routing the mic to the
      // speakers would play the learner's own voice back at them.

      // Autoplay policy can start a context suspended even after a user
      // gesture in some browsers.
      if (ctx.state == 'suspended') await ctx.resume().toDart;

      _ensureOutputContext();
      _isStreaming = true;
    } catch (e) {
      debugPrint('WebAudioStreamingService: startStreaming failed: $e');
      await stopStreaming();
      rethrow;
    } finally {
      _starting = false;
    }
  }

  void _handleMicFrame(JSFloat32Array jsFrame) {
    final onChunk = _onChunk;
    if (!_isStreaming || onChunk == null) return;

    if (!_allowBargeIn) {
      if (isOutputActive) return;
      // Hold the mic closed until scheduled playback has actually drained,
      // plus a short grace, so the tutor's tail is never captured.
      final ctx = _outputContext;
      if (ctx != null &&
          _nextStartTime + _playbackTailGraceSeconds > ctx.currentTime) {
        return;
      }
    }

    final frame = jsFrame.toDart;
    if (frame.isEmpty) return;

    // Float32 [-1, 1] -> little-endian PCM16, clamped so an over-unity sample
    // wraps to full scale instead of overflowing into the opposite sign.
    final bytes = Uint8List(frame.length * 2);
    final view = ByteData.view(bytes.buffer);
    for (var i = 0; i < frame.length; i++) {
      var s = frame[i];
      if (s > 1.0) s = 1.0;
      if (s < -1.0) s = -1.0;
      view.setInt16(i * 2, (s * 32767).round(), Endian.little);
    }
    onChunk(bytes);
  }

  @override
  Future<void> stopStreaming() async {
    _isStreaming = false;
    _onChunk = null;

    try {
      _captureNode?.port.onmessage = null;
      _captureNode?.disconnect();
    } catch (_) {}
    _captureNode = null;

    try {
      _micSource?.disconnect();
    } catch (_) {}
    _micSource = null;

    // Release the mic so the browser's recording indicator actually clears.
    final tracks = _micStream?.getTracks().toDart;
    if (tracks != null) {
      for (final t in tracks) {
        try {
          t.stop();
        } catch (_) {}
      }
    }
    _micStream = null;

    final ctx = _inputContext;
    _inputContext = null;
    if (ctx != null) {
      try {
        await ctx.close().toDart;
      } catch (_) {}
    }
  }

  void _ensureOutputContext() {
    if (_outputContext != null) return;
    final ctx = web.AudioContext(
      web.AudioContextOptions(sampleRate: _outputSampleRate),
    );
    _outputContext = ctx;
    _nextStartTime = ctx.currentTime;
  }

  @override
  Future<void> playAudioChunk(List<int> pcmBytes) async {
    if (pcmBytes.isEmpty) return;
    _ensureOutputContext();
    final ctx = _outputContext;
    if (ctx == null) return;
    if (ctx.state == 'suspended') {
      try {
        await ctx.resume().toDart;
      } catch (_) {}
    }

    // Re-align across chunk boundaries (see _pendingOddByte).
    var data = pcmBytes;
    final carry = _pendingOddByte;
    if (carry != null) {
      data = [carry, ...data];
      _pendingOddByte = null;
    }
    if (data.length.isOdd) {
      _pendingOddByte = data.last;
      data = data.sublist(0, data.length - 1);
    }
    if (data.isEmpty) return;

    final sampleCount = data.length ~/ 2;
    final source = ByteData.view(Uint8List.fromList(data).buffer);
    final buffer = ctx.createBuffer(1, sampleCount, _outputSampleRate);
    final channel = buffer.getChannelData(0).toDart;
    for (var i = 0; i < sampleCount; i++) {
      channel[i] = source.getInt16(i * 2, Endian.little) / 32768.0;
    }
    // getChannelData may hand back a copy rather than a live view depending on
    // the engine, so write it back explicitly.
    buffer.copyToChannel(channel.toJS, 0);

    final node = ctx.createBufferSource();
    node.buffer = buffer;
    node.connect(ctx.destination);

    // Sample-accurate gapless scheduling. If the network fell behind and the
    // cursor is already in the past, restart from now rather than scheduling
    // audio that the context would play all at once.
    final now = ctx.currentTime;
    if (_nextStartTime < now) _nextStartTime = now;
    node.start(_nextStartTime);
    _nextStartTime += buffer.duration;

    _scheduled.add(node);
    node.onended = ((web.Event _) => _scheduled.remove(node)).toJS;
  }

  @override
  Future<void> stopPlayback() async {
    for (final node in List.of(_scheduled)) {
      try {
        node.onended = null;
        node.stop();
        node.disconnect();
      } catch (_) {}
    }
    _scheduled.clear();
    _pendingOddByte = null;
    final ctx = _outputContext;
    if (ctx != null) _nextStartTime = ctx.currentTime;
  }

  /// No-op on web: output routing is the browser's and the OS's to decide,
  /// with no earpiece-vs-loudspeaker distinction to override.
  @override
  void setSpeakerEnabled(bool enabled) {}

  @override
  Future<void> dispose() async {
    await stopPlayback();
    await stopStreaming();
    final ctx = _outputContext;
    _outputContext = null;
    if (ctx != null) {
      try {
        await ctx.close().toDart;
      } catch (_) {}
    }
  }
}
