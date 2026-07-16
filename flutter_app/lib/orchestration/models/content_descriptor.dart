import 'competency.dart';

enum ContentMappingRole {
  teaches,
  practises,
  assesses;

  static ContentMappingRole fromWireName(String value) =>
      values.where((item) => item.name == value).firstOrNull ??
      (throw FormatException('Unknown content mapping role: $value'));
}

class ContentCompetencyMapping {
  const ContentCompetencyMapping({
    required this.id,
    required this.contentItemId,
    required this.competencyId,
    required this.role,
    required this.modality,
    required this.weight,
    required this.curriculumVersion,
  });

  final String id;
  final String contentItemId;
  final String competencyId;
  final ContentMappingRole role;
  final PerformanceModality modality;
  final double weight;
  final String curriculumVersion;

  factory ContentCompetencyMapping.fromJson(Map<String, dynamic> json) =>
      ContentCompetencyMapping(
        id: json['id'] as String,
        contentItemId: json['contentItemId'] as String,
        competencyId: json['competencyId'] as String,
        role: ContentMappingRole.fromWireName(json['role'] as String),
        modality: PerformanceModality.fromWireName(json['modality'] as String),
        weight: (json['weight'] as num).toDouble(),
        curriculumVersion: json['curriculumVersion'] as String,
      );
}

class CompetencyFramework {
  const CompetencyFramework({
    required this.frameworkVersion,
    required this.curriculumVersion,
    required this.competencies,
    required this.mappings,
  });

  final String frameworkVersion;
  final String curriculumVersion;
  final List<Competency> competencies;
  final List<ContentCompetencyMapping> mappings;

  factory CompetencyFramework.fromJson(Map<String, dynamic> json) =>
      CompetencyFramework(
        frameworkVersion: json['frameworkVersion'] as String,
        curriculumVersion: json['curriculumVersion'] as String,
        competencies: (json['competencies'] as List)
            .map(
              (item) =>
                  Competency.fromJson((item as Map).cast<String, dynamic>()),
            )
            .toList(growable: false),
        mappings: (json['mappings'] as List)
            .map(
              (item) => ContentCompetencyMapping.fromJson(
                (item as Map).cast<String, dynamic>(),
              ),
            )
            .toList(growable: false),
      );
}
