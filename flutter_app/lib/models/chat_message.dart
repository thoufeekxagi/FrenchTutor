import 'package:uuid/uuid.dart';

class ChatMessage {
  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : id = id ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now();

  final String id;
  final String role;
  final String content;
  final DateTime timestamp;

  bool get isUser => role == 'user';
  bool get isTutor => role == 'assistant' || role == 'tutor';
}
