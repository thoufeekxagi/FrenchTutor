/// DEV-ONLY harness for verifying the web live-call audio path by hand.
/// Separate entrypoint, never part of the shipped app:
///
///   flutter run -d chrome -t lib/dev/web_audio_check.dart
///
/// Phase 5 of the web migration replaces flutter_sound with the Web Audio API
/// (`audio_streaming_service_web.dart`). Real-time browser audio is the riskiest
/// part of the whole migration and cannot be covered by widget tests: it needs a
/// real mic, real speakers, and a real browser audio clock. This page exercises
/// each half of the contract independently so a failure points at one thing.
///
/// PLAYBACK check: synthesises a 440Hz PCM16 tone at the same 24kHz mono format
/// Gemini sends and pushes it through `playAudioChunk` in small chunks, imitating
/// network bursts. Success = one continuous clean tone with no gaps or clicks
/// (gapless scheduling working) and no errors.
///
/// CAPTURE check: opens the mic and reports chunk count plus a live RMS level,
/// so you can confirm frames actually arrive at the expected rate and that the
/// level tracks your voice.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/audio_streaming_service.dart';

void main() => runApp(const WebAudioCheckApp());

class WebAudioCheckApp extends StatelessWidget {
  const WebAudioCheckApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Web audio check',
    debugShowCheckedModeBanner: false,
    home: _CheckPage(),
  );
}

class _CheckPage extends StatefulWidget {
  const _CheckPage();

  @override
  State<_CheckPage> createState() => _CheckPageState();
}

class _CheckPageState extends State<_CheckPage> {
  final _audio = AudioStreamingService();
  final _log = <String>[];

  bool _capturing = false;
  int _chunks = 0;
  int _bytes = 0;
  double _rms = 0;
  DateTime? _captureStarted;

  void _say(String m) {
    // ignore: avoid_print
    print('[web-audio-check] $m');
    if (mounted) setState(() => _log.insert(0, m));
  }

  Future<void> _playTone() async {
    try {
      _say('playback: synthesising 1.5s 440Hz tone @24kHz mono PCM16...');
      const rate = 24000;
      const seconds = 1.5;
      const freq = 440.0;
      final total = (rate * seconds).round();
      final bytes = Uint8List(total * 2);
      final view = ByteData.view(bytes.buffer);
      for (var i = 0; i < total; i++) {
        // Fade the last 10% out so the tone ends without a click, which would
        // otherwise be indistinguishable from a scheduling glitch.
        final t = i / rate;
        final envelope = i > total * 0.9 ? (total - i) / (total * 0.1) : 1.0;
        final s = math.sin(2 * math.pi * freq * t) * 0.28 * envelope;
        view.setInt16(i * 2, (s * 32767).round(), Endian.little);
      }

      // Push it in ~40ms slices with gaps between, the way the network delivers
      // it. If scheduling is wrong you hear gaps or overlap here, not a tone.
      const sliceBytes = 1920; // 40ms @ 24kHz mono PCM16
      var sent = 0;
      for (var off = 0; off < bytes.length; off += sliceBytes) {
        final end = math.min(off + sliceBytes, bytes.length);
        await _audio.playAudioChunk(bytes.sublist(off, end));
        sent++;
        await Future<void>.delayed(const Duration(milliseconds: 12));
      }
      _say(
        'playback: queued $sent chunks (${bytes.length} bytes). '
        'Expect ONE clean continuous tone.',
      );
    } catch (e) {
      _say('playback FAILED: $e');
    }
  }

  Future<void> _startCapture() async {
    try {
      _say('capture: requesting mic permission...');
      final granted = await _audio.requestPermission();
      _say('capture: permission granted=$granted');
      if (!granted) {
        _say('capture: cannot continue without mic permission.');
        return;
      }

      _chunks = 0;
      _bytes = 0;
      _captureStarted = DateTime.now();
      await _audio.startStreaming(
        onChunk: (chunk) {
          _chunks++;
          _bytes += chunk.length;
          // RMS over the PCM16 chunk, for a level meter.
          final b = Uint8List.fromList(chunk);
          final v = ByteData.view(b.buffer);
          var sum = 0.0;
          final n = chunk.length ~/ 2;
          for (var i = 0; i < n; i++) {
            final s = v.getInt16(i * 2, Endian.little) / 32768.0;
            sum += s * s;
          }
          final rms = n == 0 ? 0.0 : math.sqrt(sum / n);
          if (mounted && _chunks % 5 == 0) setState(() => _rms = rms);
        },
      );
      setState(() => _capturing = true);
      _say(
        'capture: streaming started. Speak — chunk count and level '
        'should move.',
      );
    } catch (e) {
      _say('capture FAILED: $e');
    }
  }

  Future<void> _stopCapture() async {
    try {
      await _audio.stopStreaming();
      final secs = _captureStarted == null
          ? 0.0
          : DateTime.now().difference(_captureStarted!).inMilliseconds / 1000.0;
      final expected = (16000 * 2 * secs).round();
      _say(
        'capture: stopped. $_chunks chunks, $_bytes bytes in '
        '${secs.toStringAsFixed(1)}s (expected ~$expected bytes @16kHz '
        'mono PCM16 if the mic was ungated the whole time).',
      );
      setState(() => _capturing = false);
    } catch (e) {
      _say('capture stop FAILED: $e');
    }
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Web live-call audio check')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Implementation under test: ${_audio.runtimeType}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: _playTone,
                  child: const Text('1. Play test tone (playback)'),
                ),
                FilledButton(
                  onPressed: _capturing ? null : _startCapture,
                  child: const Text('2. Start mic capture'),
                ),
                OutlinedButton(
                  onPressed: _capturing ? _stopCapture : null,
                  child: const Text('3. Stop capture'),
                ),
                OutlinedButton(
                  onPressed: () => _audio.stopPlayback(),
                  child: const Text('Stop playback'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('chunks: $_chunks   bytes: $_bytes'),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('level '),
                Expanded(
                  child: LinearProgressIndicator(
                    value: (_rms * 4).clamp(0.0, 1.0),
                    minHeight: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Log (newest first):'),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: const Color(0xFFF2F3F5),
                child: ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      _log[i],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
