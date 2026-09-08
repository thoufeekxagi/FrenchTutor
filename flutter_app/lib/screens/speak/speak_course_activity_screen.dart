import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/speak_curriculum.dart';
import '../../models/speaking_course.dart';
import '../../providers/database_provider.dart';
import '../../services/course_progress_service.dart';
import '../../services/course_artifact_codec.dart';
import '../../services/practice_artwork_service.dart';
import '../../services/premium_access_gate.dart';
import '../../services/speak_roadmap_service.dart';
import '../../services/subscription_gate_service.dart';
import '../labs/alphabet_lab_screen.dart';
import '../labs/connectors_lab_screen.dart';
import '../labs/liaison_lab_screen.dart';
import '../labs/vocabulary_flashcards_screen.dart';
import '../lessons/listening_practice_screen.dart';
import '../lessons/story_reader_screen.dart';
import '../lessons/writing_course_lesson_screen.dart';
import '../grammar/grammar_v2_lesson_screen.dart';
import 'speak_review_screen.dart';
import 'speak_ui.dart';
import 'speaking_flow_screen.dart';
import 'speaking_lesson_flow_screen.dart';

/// Opens one course item directly in the matching Practice engine.
///
/// Course owns the level, compact learner context, and persisted lesson data;
/// the existing Practice engines own the actual interaction UI. This route is
/// only the hand-off between those two responsibilities.
class SpeakCourseActivityScreen extends ConsumerStatefulWidget {
  const SpeakCourseActivityScreen({super.key, required this.session});

  final SpeakRoadmapSession session;

  @override
  ConsumerState<SpeakCourseActivityScreen> createState() =>
      _SpeakCourseActivityScreenState();
}

/// Course has one speaking interaction. Keep legacy roleplay/free-talk rows
/// compatible by opening them in the same guided phrase engine too.
SpeakingCourseMode courseSpeakingModeFor(SpeakSkill skill) {
  if (skill == SpeakSkill.speaking ||
      skill == SpeakSkill.roleplay ||
      skill == SpeakSkill.freeTalk) {
    return SpeakingCourseMode.guided;
  }
  throw ArgumentError.value(skill, 'skill', 'Not a speaking Course skill');
}

class _SpeakCourseActivityScreenState
    extends ConsumerState<SpeakCourseActivityScreen> {
  bool _launching = false;
  String? _error;

  SpeakRoadmapSession get session => widget.session;

  bool get _isSpeakingPath =>
      session.primarySkill == SpeakSkill.speaking ||
      session.primarySkill == SpeakSkill.roleplay ||
      session.primarySkill == SpeakSkill.freeTalk;

  String get _level {
    final keyLevel = session.level.toUpperCase();
    return const {'A1', 'A2', 'B1', 'B2'}.contains(keyLevel)
        ? keyLevel
        : ref.read(learningStoreProvider).profile().level.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    if (!_isSpeakingPath) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _launch();
      });
    }
  }

  Future<void> _launch() async {
    if (_launching) return;
    setState(() {
      _launching = true;
      _error = null;
    });
    try {
      final allowed = await requirePremiumArea(
        context,
        ref,
        PremiumArea.course,
        source: 'course',
      );
      if (!allowed || !mounted) {
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      final startedAt = DateTime.now();
      ref.read(adaptiveCourseStoreProvider).markStarted(session.contentKey);
      final completed = await _openPractice();
      if (!mounted) return;
      if (!completed) {
        Navigator.of(context).pop(false);
        return;
      }

      final progress = CourseProgressService();
      await progress.recordActivity(
        contentKey: session.contentKey,
        skill: session.primarySkill,
        elapsed: DateTime.now().difference(startedAt),
      );
      final shouldComplete = await progress.shouldAutoComplete(
        contentKey: session.contentKey,
        estimatedMinutes: session.estimatedMinutes,
        requiredSkills: {session.primarySkill},
      );
      if (shouldComplete) {
        ref
            .read(storageServiceProvider)
            .markCourseSessionCompleted(
              contentKey: session.contentKey,
              topic: session.title,
              stage: session.primarySkill.wireName,
            );
        ref.read(adaptiveCourseStoreProvider).markCompleted(session.contentKey);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('Direct course activity failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _launching = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<bool> _openPractice() async {
    final skill = session.primarySkill;
    if (skill == SpeakSkill.speaking ||
        skill == SpeakSkill.roleplay ||
        skill == SpeakSkill.freeTalk) {
      final artifact = session.artifact;
      final isAuthoredFoundation =
          session.contentKey == SpeakingCourseCatalog.firstA1GuidedLessonId;
      if (!isAuthoredFoundation &&
          (!session.contentReady || artifact == null)) {
        throw StateError('This course lesson is not ready yet.');
      }
      final speakingLines =
          session.contentKey == SpeakingCourseCatalog.firstA1GuidedLessonId
          ? SpeakingCourseCatalog.firstA1GuidedLesson.lines
          : CourseArtifactCodec.speaking(artifact ?? const <String, dynamic>{});
      // Course speaking always uses the existing guided phrase flow. The
      // Practice app may offer Free Talk and Roleplay, but those are not
      // silently substituted into a Course lesson.
      final lesson = SpeakingCourseLesson(
        id: session.contentKey,
        title: session.title,
        subtitle: session.subtitle,
        level: _level,
        icon: Icons.mic_none_rounded,
        mode: courseSpeakingModeFor(skill),
        lines: speakingLines,
        goal: session.competency,
      );
      final SpeakingResult? result = await AppRouter.push<SpeakingResult>(
        context,
        (_) => SpeakingLessonFlowScreen(
          title: lesson.title,
          topic: lesson.subtitle,
          level: lesson.level,
          contentKey: lesson.id,
          steps: speakingStepsForCourseLines(lesson.lines, level: lesson.level),
        ),
        fullscreenDialog: true,
      );
      // Match the dedicated Speaking Course: completing its native flow owns
      // completion. A dismissed setup returns null/connected=false.
      return result?.connected ?? false;
    }

    // Unit 1's alphabet decks are authored, bundled, and intentionally have
    // no adaptive JSON artifact. Route them before the generated-artifact
    // guard; the old order made Alphabet/Consonants/Vowels/Accents report
    // “This course lesson is not ready yet.”
    if (skill == SpeakSkill.alphabet) {
      final result = await AppRouter.push<bool>(
        context,
        (_) => AlphabetLabScreen(deckId: _alphabetDeckId),
        fullscreenDialog: true,
      );
      return result == true;
    }
    if (skill == SpeakSkill.connectors) {
      final result = await AppRouter.push<bool>(
        context,
        (_) => const ConnectorsLabScreen(),
        fullscreenDialog: true,
      );
      return result == true;
    }
    if (skill == SpeakSkill.liaison) {
      final result = await AppRouter.push<bool>(
        context,
        (_) => const LiaisonLabScreen(),
        fullscreenDialog: true,
      );
      return result == true;
    }
    if (skill == SpeakSkill.review) {
      final result = await AppRouter.push<bool>(
        context,
        (_) => const SpeakReviewScreen(),
        fullscreenDialog: true,
      );
      return result == true;
    }

    final artifact = session.artifact;
    if (!session.contentReady || artifact == null) {
      throw StateError('This course lesson is not ready yet.');
    }
    if (skill == SpeakSkill.vocabulary) {
      final vocabularySet = CourseArtifactCodec.vocabulary(artifact);
      final result = await AppRouter.push<bool>(
        context,
        (_) => VocabularyFlashcardsScreen(
          title: vocabularySet.title,
          entries: vocabularySet.entries,
          source: 'course',
          topic: vocabularySet.topic,
          levelBand: vocabularySet.levelBand,
          studyDepth: VocabularyStudyDepth.wordsAndSentences,
          storyExamples: vocabularySet.storyExamples,
          coverUrl: vocabularySet.coverUrl,
          preparedContentOnly: true,
        ),
        fullscreenDialog: true,
      );
      return result == true;
    }
    if (skill == SpeakSkill.reading) {
      final story = CourseArtifactCodec.story(artifact);
      if (!mounted) return false;
      final result = await AppRouter.push<StoryReaderResult>(
        context,
        (_) => StoryReaderScreen(
          story: story,
          showFinishButton: true,
          generateCoverIfMissing: true,
          coverGenerator: () async {
            final coverUrl = await PracticeArtworkService.generateAndUpload(
              sync: ref.read(syncServiceProvider),
              id: story.id,
              title: story.title,
              summary: story.summary,
              topic: story.topic,
              levelBand: story.levelBand,
              coverPrompt: story.topic,
              visualStyle:
                  'Text-free editorial scene for a French reading lesson; '
                  'no letters, numbers, signs, logos, faces, or characters.',
              maxBytes: 100 * 1024,
              retryMaxBytes: 160 * 1024,
              aspectRatio: '2:3',
            );
            if (coverUrl != null && coverUrl.isNotEmpty) {
              ref
                  .read(adaptiveCourseStoreProvider)
                  .updateArtifactCover(
                    contentKey: session.contentKey,
                    coverUrl: coverUrl,
                  );
            }
            return coverUrl;
          },
        ),
        fullscreenDialog: true,
      );
      return result != null;
    }
    if (skill == SpeakSkill.listening) {
      final story = CourseArtifactCodec.listening(artifact);
      if (!mounted) return false;
      final result = await AppRouter.push<bool>(
        context,
        (_) => ListeningPracticeScreen(story: story, showFinishButton: true),
        fullscreenDialog: true,
      );
      return result == true;
    }
    if (skill == SpeakSkill.writing) {
      final lesson = CourseArtifactCodec.writingCourse(artifact);
      final result = await AppRouter.push<bool>(
        context,
        (_) => WritingCourseLessonScreen(lesson: lesson),
        fullscreenDialog: true,
      );
      return result == true;
    }
    if (skill == SpeakSkill.grammar) {
      final grammarSession = CourseArtifactCodec.grammarCourse(artifact);
      final result = await AppRouter.push<Object?>(
        context,
        (_) => GrammarV2LessonScreen(session: grammarSession),
        fullscreenDialog: true,
      );
      return result != null;
    }

    final screen = switch (skill) {
      SpeakSkill.alphabet => AlphabetLabScreen(deckId: _alphabetDeckId),
      SpeakSkill.connectors => const ConnectorsLabScreen(),
      SpeakSkill.liaison => const LiaisonLabScreen(),
      SpeakSkill.grammar ||
      SpeakSkill.listening ||
      SpeakSkill.reading ||
      SpeakSkill.writing ||
      SpeakSkill.vocabulary => throw StateError('Handled above'),
      SpeakSkill.roleplay ||
      SpeakSkill.freeTalk => throw StateError('Handled above'),
      // A review catalog item hands off to the shared review chooser so the
      // learner selects Reading, Listening, or Speaking from recent history.
      SpeakSkill.review => const SpeakReviewScreen(),
      SpeakSkill.speaking => throw StateError('Speaking is handled above'),
    };

    final result = await AppRouter.push<bool>(
      context,
      (_) => screen,
      fullscreenDialog: true,
    );
    return result == true;
  }

  String? get _alphabetDeckId {
    if (session.unit != 1 || session.index > 3) return null;
    return switch (session.index % 10) {
      0 => 'learn_alphabet',
      1 => 'learn_vowels',
      2 => 'learn_consonants',
      3 => 'learn_core_accents',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_isSpeakingPath) {
      return SpeakingLessonDetailScreen(
        session: session,
        onStart: _launch,
        isStarting: _launching,
        error: _error,
      );
    }
    return _launchShell(context);
  }

  Widget _launchShell(BuildContext context) {
    return SpeakScaffold(
      child: Column(
        children: [
          SpeakHeader(
            title: session.primarySkill.label,
            subtitle: session.title,
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: Icon(Icons.close_rounded, color: SpeakColors.inkSoft),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _error == null && !_launching
                    ? const SizedBox.shrink()
                    : _error == null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: SpeakColors.accent),
                          const SizedBox(height: 18),
                          Text(
                            'Preparing saved lesson audio once…',
                            textAlign: TextAlign.center,
                            style: DesignTokens.body(15),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: DesignTokens.body(15),
                          ),
                          const SizedBox(height: 18),
                          SpeakPrimaryButton(
                            label: 'Back to course',
                            icon: Icons.arrow_back_rounded,
                            onTap: () => Navigator.of(context).pop(false),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
