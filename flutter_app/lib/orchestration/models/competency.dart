enum CompetencyKind {
  lexical,
  grammar,
  phonology,
  function,
  discourse,
  strategy;

  static CompetencyKind fromWireName(String value) =>
      values.where((item) => item.name == value).firstOrNull ??
      (throw FormatException('Unknown competency kind: $value'));
}

enum PerformanceModality {
  listeningRecognition('listening_recognition'),
  readingRecognition('reading_recognition'),
  controlledWriting('controlled_writing'),
  spontaneousWriting('spontaneous_writing'),
  controlledSpeaking('controlled_speaking'),
  spontaneousSpeaking('spontaneous_speaking'),
  pronunciationProduction('pronunciation_production');

  const PerformanceModality(this.wireName);

  final String wireName;

  static PerformanceModality fromWireName(String value) =>
      values.where((item) => item.wireName == value).firstOrNull ??
      (throw FormatException('Unknown performance modality: $value'));
}

enum EvidenceSupportLevel {
  recognition,
  cuedRecall('cued_recall'),
  hintedProduction('hinted_production'),
  unaidedProduction('unaided_production'),
  spontaneousTransfer('spontaneous_transfer');

  const EvidenceSupportLevel([String? wireName])
    : wireName = wireName ?? 'recognition';

  final String wireName;

  static EvidenceSupportLevel fromWireName(String value) =>
      values.where((item) => item.wireName == value).firstOrNull ??
      (throw FormatException('Unknown evidence support level: $value'));
}

class Competency {
  const Competency({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.difficultyBand,
    required this.prerequisiteIds,
    required this.curriculumVersion,
    this.targetLevelLabel,
    this.examRelevance = const {},
  });

  final String id;
  final CompetencyKind kind;
  final String title;
  final String description;
  final String difficultyBand;
  final List<String> prerequisiteIds;
  final String? targetLevelLabel;
  final Map<String, Object?> examRelevance;
  final String curriculumVersion;

  factory Competency.fromJson(Map<String, dynamic> json) => Competency(
    id: json['id'] as String,
    kind: CompetencyKind.fromWireName(json['kind'] as String),
    title: json['title'] as String,
    description: json['description'] as String,
    difficultyBand: json['difficultyBand'] as String,
    prerequisiteIds: List<String>.from(
      json['prerequisiteIds'] as List? ?? const [],
    ),
    targetLevelLabel: json['targetLevelLabel'] as String?,
    examRelevance:
        (json['examRelevance'] as Map?)?.cast<String, Object?>() ?? const {},
    curriculumVersion: json['curriculumVersion'] as String,
  );
}
