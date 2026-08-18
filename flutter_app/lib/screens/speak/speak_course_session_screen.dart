import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/speak_curriculum.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../../services/course_progress_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/speak_language_profile.dart';
import '../../services/speak_roadmap_service.dart';
import '../session/session_screen.dart';
import '../labs/alphabet_lab_screen.dart';
import '../labs/connectors_lab_screen.dart';
import '../labs/grammar_lab_screen.dart';
import '../labs/liaison_lab_screen.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/writing_lab_screen.dart';
import 'speak_course_vocabulary_screen.dart';
import '../reading/reading_library_screen.dart';
import 'speak_free_talk_screen.dart';
import 'speak_review_screen.dart';
import 'speak_roleplay_screen.dart';
import 'speak_ui.dart';

/// The bridge between the course path and the existing learning engines.
///
/// Every course session has one declared focus plus a compact transfer loop.
/// Supporting vocabulary, speaking, and writing activities remain available
/// without competing with the focus selected by the catalog.
class SpeakCourseSessionScreen extends ConsumerStatefulWidget {
  const SpeakCourseSessionScreen({super.key, required this.session});

  final SpeakRoadmapSession session;

  @override
  ConsumerState<SpeakCourseSessionScreen> createState() =>
      _SpeakCourseSessionScreenState();
}

class _SpeakCourseSessionScreenState
    extends ConsumerState<SpeakCourseSessionScreen> {
  late final CourseProgressService _courseProgress;
  CourseActivityProgress _activityProgress = const CourseActivityProgress(
    skills: {},
    seconds: 0,
  );
  SpeakSkill? _selectedSkill;
  SpeakRoadmapSession get session => widget.session;

  String get _level => session.level.toUpperCase();

  /// One course session is one guided loop. The catalog owns the order; the
  /// screen should not invent a second menu of competing destinations.
  List<SpeakSkill> get _activities {
    // A1 foundation practice is self-contained in the alphabet lab. The lab
    // already teaches and rehearses the sounds, so never attach the generic
    // live-conversation route (which belongs to later course situations).
    final ordered = <SpeakSkill>[
      ...session.activitySkills.where(
        (skill) => !_isAlphabetFoundation || skill != SpeakSkill.speaking,
      ),
    ];
    final unique = <SpeakSkill>[];
    for (final skill in ordered) {
      if (!unique.contains(skill)) unique.add(skill);
    }
    return unique.toList(growable: false);
  }

  SpeakSkill? get _nextSkill {
    for (final skill in _activities) {
      if (!_activityProgress.skills.contains(skill)) return skill;
    }
    return null;
  }

  bool get _isAlphabetFoundation =>
      _level == 'A1' && session.primarySkill == SpeakSkill.alphabet;

  String get _activityTopic =>
      _isAlphabetFoundation ? session.title : session.unitTitle;

  SpeakSkill? _firstIncomplete(CourseActivityProgress progress) {
    for (final skill in _activities) {
      if (!progress.skills.contains(skill)) return skill;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _courseProgress = CourseProgressService();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final progress = await _courseProgress.read(session.contentKey);
    if (mounted) {
      setState(() {
        _activityProgress = progress;
        _selectedSkill ??=
            _firstIncomplete(progress) ??
            (_activities.isEmpty ? null : _activities.first);
      });
    }
  }

  void _selectSkill(SpeakSkill skill) {
    setState(() => _selectedSkill = skill);
  }

  Future<void> _openActivity(SpeakSkill skill) async {
    final startedAt = DateTime.now();
    if (skill == SpeakSkill.speaking) {
      final allowed = await ensureAiSessionQuota(
        context,
        ref.read(pilotAccessServiceProvider),
      );
      if (!allowed || !mounted) return;
      LessonSpeechService.shared.deactivate();
      await AppRouter.push<SpeakingResult>(
        context,
        (_) => SessionScreen(
          apiKey: ApiKeys.geminiKey,
          sessionTopic: session.title,
          contentKey: session.contentKey,
          stage: skill.wireName,
          lessonContext: session.contextPrompt,
          kickoffMessage: _speakingKickoff,
        ),
        fullscreenDialog: true,
      );
    } else {
      final screen = _screenFor(skill);
      if (screen == null) return;
      await AppRouter.push<bool>(
        context,
        (_) => screen,
        fullscreenDialog: true,
      );
    }
    final elapsed = DateTime.now().difference(startedAt);
    await _courseProgress.recordActivity(
      contentKey: session.contentKey,
      skill: skill,
      elapsed: elapsed,
    );
    final progress = await _courseProgress.read(session.contentKey);
    final storage = ref.read(storageServiceProvider);
    final alreadyRecorded = storage.completedContentKeys().contains(
      session.contentKey,
    );
    final loopComplete = await _courseProgress.shouldAutoComplete(
      contentKey: session.contentKey,
      estimatedMinutes: session.estimatedMinutes,
      requiredSkills: _isAlphabetFoundation
          ? const {SpeakSkill.alphabet, SpeakSkill.vocabulary}
          : null,
    );
    if (!alreadyRecorded && loopComplete) {
      storage.markCourseSessionCompleted(
        contentKey: session.contentKey,
        topic: session.title,
        stage: session.primarySkill.wireName,
      );
    }
    if (mounted) {
      setState(() {
        _activityProgress = progress;
        if (_selectedSkill == skill) {
          _selectedSkill = _firstIncomplete(progress) ?? skill;
        }
      });
    }
  }

  String get _speakingKickoff =>
      '(App instruction, not the student: this is the speaking step inside '
      'the course lesson "${session.title}". Explain the lesson context in '
      'one short English sentence, then model "${session.targetPhrases.isEmpty ? 'Bonjour !' : session.targetPhrases.first}" '
      'in French and ask the learner for one short response. Keep the lesson '
      'at ${_level.toUpperCase()} level and do not open with a generic free-talk question.)';

  Widget? _screenFor(SpeakSkill skill) {
    final contextPrompt = session.contextPrompt;
    return switch (skill) {
      SpeakSkill.alphabet => AlphabetLabScreen(deckId: _alphabetDeckId),
      SpeakSkill.connectors => const ConnectorsLabScreen(),
      SpeakSkill.liaison => const LiaisonLabScreen(),
      SpeakSkill.grammar => GrammarLabScreen(topic: _activityTopic),
      SpeakSkill.listening => ListeningLabScreen(topic: _activityTopic),
      SpeakSkill.reading => ReadingLibraryScreen(topic: _activityTopic),
      SpeakSkill.writing => WritingLabScreen(
        topic: _activityTopic,
        contextPrompt: contextPrompt,
      ),
      SpeakSkill.vocabulary => SpeakCourseVocabularyScreen(
        topic: _activityTopic,
        sessionTitle: session.title,
        contextPrompt: contextPrompt,
        contentKey: session.contentKey,
        levelBand: _level,
        targetPhrases: session.targetPhrases,
      ),
      // Speaking is opened directly by [_openActivity] so the course does
      // not add a preflight screen on top of the live tutor.
      SpeakSkill.speaking => null,
      SpeakSkill.roleplay => SpeakRoleplayScreen(
        topic: session.title,
        scene: session.roleplay,
        contentKey: session.contentKey,
      ),
      // Course-map review uses the same chooser and history source as the
      // Practice tab. It must not open a second summary-only review flow.
      SpeakSkill.review => const SpeakReviewScreen(),
      SpeakSkill.freeTalk => const SpeakFreeTalkScreen(),
    };
  }

  String? get _alphabetDeckId {
    if (!_isAlphabetFoundation) return null;
    return switch (session.index % 10) {
      0 => 'learn_alphabet',
      1 => 'learn_vowels',
      2 => 'learn_consonants',
      _ => null,
    };
  }

  void _complete() {
    ref
        .read(storageServiceProvider)
        .markCourseSessionCompleted(
          contentKey: session.contentKey,
          topic: session.title,
          stage: session.primarySkill.wireName,
        );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final language = SpeakLanguageProfile.forLevel(_level);
    final contextTitle = _isAlphabetFoundation
        ? session.title
        : session.unitTitle;
    final contextHint = _isAlphabetFoundation
        ? 'Learn the sound, connect it to a simple word, then practise it.'
        : language.sessionHint;
    final nextSkill = _nextSkill;
    final canFinish = nextSkill == null;
    final selectedSkill =
        _selectedSkill ??
        (nextSkill ?? (_activities.isEmpty ? null : _activities.first));
    return SpeakScaffold(
      child: Column(
        children: [
          SpeakHeader(
            title: 'Course session',
            subtitle: '$_activityTopic · ${session.estimatedMinutes} min',
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: const Icon(
                Icons.close_rounded,
                color: SpeakColors.inkSoft,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              children: [
                Text(
                  'UNIT ${session.unit}',
                  style: DesignTokens.label(
                    10,
                  ).copyWith(color: SpeakColors.inkSoft, letterSpacing: 1),
                ),
                const SizedBox(height: 7),
                Text(session.title, style: DesignTokens.display(30)),
                const SizedBox(height: 8),
                Text(
                  session.subtitle,
                  style: DesignTokens.body(
                    15,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                ),
                const SizedBox(height: 22),
                SpeakCard(
                  color: SpeakColors.blueSoft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.track_changes_rounded,
                        color: SpeakColors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Today\'s context',
                              style: DesignTokens.body(
                                12,
                                weight: FontWeight.w700,
                              ).copyWith(color: SpeakColors.blue),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              contextTitle,
                              style: DesignTokens.body(
                                17,
                                weight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              contextHint,
                              style: DesignTokens.body(
                                12,
                              ).copyWith(color: SpeakColors.inkSoft),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                SpeakSectionTitle(title: 'Inside this lesson'),
                const SizedBox(height: 5),
                Text(
                  'Move through one short step at a time. The next step is always clear.',
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < _activities.length; i++) ...[
                  _activityRow(
                    _activities[i],
                    index: i,
                    active: _activities[i] == selectedSkill,
                    complete: _activityProgress.skills.contains(_activities[i]),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              children: [
                if (selectedSkill != null)
                  SpeakPrimaryButton(
                    label: 'Start ${selectedSkill.label.toLowerCase()}',
                    icon: Icons.arrow_forward_rounded,
                    onTap: () => _openActivity(selectedSkill),
                  ),
                if (canFinish) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _complete,
                    child: const Text('Finish session'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityRow(
    SpeakSkill skill, {
    required int index,
    required bool active,
    required bool complete,
  }) {
    return GestureDetector(
      onTap: () => _selectSkill(skill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: active ? SpeakColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? SpeakColors.blue : SpeakColors.line,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: active ? Colors.white24 : SpeakColors.blueSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconFor(skill),
                color: active ? Colors.white : SpeakColors.blue,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}. ${skill.label}',
                    style: DesignTokens.body(
                      14,
                      weight: FontWeight.w700,
                    ).copyWith(color: active ? Colors.white : SpeakColors.navy),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    skill.description,
                    style: DesignTokens.body(11).copyWith(
                      color: active ? Colors.white70 : SpeakColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            Radio<SpeakSkill>(
              value: skill,
              groupValue: _selectedSkill,
              onChanged: (_) => _selectSkill(skill),
              activeColor: active ? Colors.white : SpeakColors.blue,
            ),
            if (complete)
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: active ? Colors.white : SpeakColors.blue,
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(SpeakSkill skill) => switch (skill) {
    SpeakSkill.alphabet => Icons.abc_rounded,
    SpeakSkill.vocabulary => Icons.style_outlined,
    SpeakSkill.reading => Icons.menu_book_outlined,
    SpeakSkill.listening => Icons.headphones_outlined,
    SpeakSkill.grammar => Icons.auto_fix_high_outlined,
    SpeakSkill.connectors => Icons.link_rounded,
    SpeakSkill.liaison => Icons.record_voice_over_outlined,
    SpeakSkill.writing => Icons.edit_note_rounded,
    SpeakSkill.speaking => Icons.mic_none_rounded,
    SpeakSkill.roleplay => Icons.forum_outlined,
    SpeakSkill.review => Icons.replay_rounded,
    SpeakSkill.freeTalk => Icons.people_alt_outlined,
  };
}
