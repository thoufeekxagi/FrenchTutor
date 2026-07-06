import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

enum SessionStatus { idle, listening, thinking, speaking, ended }

class WebSocketService {
  WebSocketChannel? _channel;
  final String serverUrl;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<SessionStatus> _statusController =
      StreamController<SessionStatus>.broadcast();
  final StreamController<String> _transcriptController =
      StreamController<String>.broadcast();
  final StreamController<Uint8List> _audioController =
      StreamController<Uint8List>.broadcast();
  final StreamController<String> _summaryController =
      StreamController<String>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<SessionStatus> get status => _statusController.stream;
  Stream<String> get transcript => _transcriptController.stream;
  Stream<Uint8List> get audio => _audioController.stream;
  Stream<String> get summary => _summaryController.stream;
  Stream<String> get errors => _errorController.stream;

  WebSocketService({required this.serverUrl});

  void connect(String sessionId) {
    final uri = Uri.parse('$serverUrl/ws/$sessionId');
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (data) {
        final msg = jsonDecode(data) as Map<String, dynamic>;
        _handleMessage(msg);
      },
      onError: (e) {
        _errorController.add('Connection error: $e');
      },
      onDone: () {
        _statusController.add(SessionStatus.ended);
      },
    );
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String;

    switch (type) {
      case 'status':
        final status = msg['status'] as String;
        final s = _parseStatus(status);
        _statusController.add(s);
        break;
      case 'transcript':
        final role = msg['role'] as String;
        final text = msg['text'] as String;
        _transcriptController.add('$role|$text');
        break;
      case 'audio':
        final audioB64 = msg['data'] as String;
        final audioBytes = base64Decode(audioB64);
        _audioController.add(audioBytes);
        break;
      case 'session_ended':
        final summary = msg['summary'] as String? ?? '';
        _summaryController.add(summary);
        _statusController.add(SessionStatus.ended);
        break;
      case 'error':
        _errorController.add(msg['message'] as String? ?? 'Unknown error');
        break;
    }
    _messageController.add(msg);
  }

  SessionStatus _parseStatus(String status) {
    switch (status) {
      case 'listening':
        return SessionStatus.listening;
      case 'thinking':
        return SessionStatus.thinking;
      case 'speaking':
        return SessionStatus.speaking;
      default:
        return SessionStatus.idle;
    }
  }

  void sendStart() {
    _channel?.sink.add(jsonEncode({'type': 'start'}));
  }

  void sendAudio(Uint8List audioBytes) {
    final b64 = base64Encode(audioBytes);
    _channel?.sink.add(jsonEncode({'type': 'audio', 'data': b64}));
  }

  void sendEnd() {
    _channel?.sink.add(jsonEncode({'type': 'end'}));
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _statusController.close();
    _transcriptController.close();
    _audioController.close();
    _summaryController.close();
    _errorController.close();
  }
}
