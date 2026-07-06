import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _isRecording = false;
  String? _currentRecordingPath;

  bool get isRecording => _isRecording;

  Future<bool> requestPermissions() async {
    final mic = await Permission.microphone.request();
    return mic.isGranted;
  }

  Future<void> startRecording() async {
    if (_isRecording) return;

    final hasPermission = await requestPermissions();
    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.webm';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.opus,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 64000,
      ),
      path: path,
    );

    _isRecording = true;
    _currentRecordingPath = path;
  }

  Future<Uint8List> stopRecording() async {
    if (!_isRecording) {
      throw Exception('Not recording');
    }

    final path = await _recorder.stop();
    _isRecording = false;
    _currentRecordingPath = path;

    if (path == null) {
      throw Exception('Recording failed — no file path returned');
    }

    final file = File(path);
    final bytes = await file.readAsBytes();
    return bytes;
  }

  Future<void> playAudioBytes(Uint8List audioBytes) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/reply_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final file = File(filePath);
    await file.writeAsBytes(audioBytes);

    await _player.play(DeviceFileSource(filePath));
  }

  Future<void> stopPlayback() async {
    await _player.stop();
  }

  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}
