class Session {
  Session({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.summary,
    this.topic,
    this.vocabulary = const [],
    this.stage,
  });

  final String id;
  final String startedAt;
  String? endedAt;
  String? summary;
  String? topic;
  List<String> vocabulary;
  String? stage;
}
