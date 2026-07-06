import 'dart:convert';

class Session {
  final String id;
  final String startedAt;
  final String? endedAt;
  final String? summary;
  final String? topic;
  final List<String> vocabulary;

  Session({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.summary,
    this.topic,
    this.vocabulary = const [],
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      startedAt: json['started_at'] as String,
      endedAt: json['ended_at'] as String?,
      summary: json['summary'] as String?,
      topic: json['topic'] as String?,
      vocabulary: json['vocabulary'] != null
          ? List<String>.from(jsonDecode(json['vocabulary'] as String))
          : [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'started_at': startedAt,
      'ended_at': endedAt,
      'summary': summary,
      'topic': topic,
      'vocabulary': jsonEncode(vocabulary),
    };
  }

  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      id: map['id'] as String,
      startedAt: map['started_at'] as String,
      endedAt: map['ended_at'] as String?,
      summary: map['summary'] as String?,
      topic: map['topic'] as String?,
      vocabulary: map['vocabulary'] != null
          ? List<String>.from(jsonDecode(map['vocabulary'] as String))
          : [],
    );
  }
}
