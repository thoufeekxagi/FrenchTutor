import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/speak_curriculum.dart';

/// Lightweight local evidence for a course session while the learner moves
/// through its supporting activities. The published course itself remains
/// shared content; this is only learner progress and is safe to rebuild from
/// the activities the learner actually opens.
class CourseActivityProgress {
  const CourseActivityProgress({required this.skills, required this.seconds});

  final Set<SpeakSkill> skills;
  final int seconds;

  Map<String, dynamic> toJson() => {
    'skills': skills.map((skill) => skill.wireName).toList(),
    'seconds': seconds,
  };

  factory CourseActivityProgress.fromJson(Map<String, dynamic> json) {
    final skills = <SpeakSkill>{};
    for (final value in (json['skills'] as List? ?? const [])) {
      final skill = speakSkillFromWire(value);
      if (skill != null) skills.add(skill);
    }
    return CourseActivityProgress(
      skills: skills,
      seconds: (json['seconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class CourseProgressService {
  CourseProgressService({SharedPreferences? preferences}) {
    _preferences = preferences;
  }

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  String _key(String contentKey) => 'course_progress_$contentKey';

  Future<CourseActivityProgress> read(String contentKey) async {
    final raw = (await _prefs).getString(_key(contentKey));
    if (raw == null || raw.isEmpty) {
      return const CourseActivityProgress(skills: {}, seconds: 0);
    }
    try {
      return CourseActivityProgress.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const CourseActivityProgress(skills: {}, seconds: 0);
    }
  }

  Future<void> recordActivity({
    required String contentKey,
    required SpeakSkill skill,
    required Duration elapsed,
  }) async {
    final current = await read(contentKey);
    final next = CourseActivityProgress(
      skills: {...current.skills, skill},
      seconds: current.seconds + elapsed.inSeconds.clamp(0, 3600).toInt(),
    );
    await (await _prefs).setString(_key(contentKey), jsonEncode(next.toJson()));
  }

  /// A session completes automatically after the learner has touched the
  /// essential learning loop, or after meaningful time across at least two
  /// activities. A quick accidental open/close never marks a lesson done.
  Future<bool> shouldAutoComplete({
    required String contentKey,
    required int estimatedMinutes,
    Set<SpeakSkill>? requiredSkills,
  }) async {
    final progress = await read(contentKey);
    final core =
        requiredSkills ??
        const {SpeakSkill.vocabulary, SpeakSkill.speaking, SpeakSkill.writing};
    final coreCount = progress.skills.intersection(core).length;
    final requiredSeconds = (estimatedMinutes * 45).clamp(90, 900);
    return coreCount == core.length ||
        (coreCount >= 2 && progress.seconds >= requiredSeconds);
  }
}
