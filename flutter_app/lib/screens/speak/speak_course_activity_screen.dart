import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/speak_curriculum.dart';
import '../../providers/database_provider.dart';
import '../../services/course_progress_service.dart';
import '../../services/premium_access_gate.dart';
import '../../services/speak_roadmap_service.dart';
import '../../services/subscription_gate_service.dart';
import '../labs/alphabet_lab_screen.dart';
import '../labs/connectors_lab_screen.dart';
import '../labs/grammar_lab_screen.dart';
import '../labs/liaison_lab_screen.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/writing_lab_screen.dart';
import '../reading/reading_library_screen.dart';
import 'speak_course_vocabulary_screen.dart';
import 'speak_review_screen.dart';
import 'speak_ui.dart';
import 'speaking_practice_screen.dart';
import 'speaking_flow_screen.dart';

/// Opens one course item directly in the matching Practice engine.
///
/// The course catalog owns the context and the primary skill; Practice owns
/// generation, learner-scoped storage, and the actual lesson UI. This route
/// is only a short hand-off while a generated item is being prepared, so the
/// old course activity selector can never become a second competing menu.
class SpeakCourseActivityScreen extends ConsumerStatefulWidget {
  const SpeakCourseActivityScreen({super.key, required this.session});

  final SpeakRoadmapSession session;

  @override
  ConsumerState<SpeakCourseActivityScreen> createState() =>
      _SpeakCourseActivityScreenState();
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

  String get _contextPrompt {
    final target =
        session.primarySkill == SpeakSkill.speaking ||
            session.primarySkill == SpeakSkill.roleplay
        ? _requiredTargetPhrases
        : const <String>[];
    final roleplay = session.roleplay;
    final targetLine = target.isEmpty
        ? ''
        : '\nTarget phrases: ${target.join('; ')}.';
    return 'Course unit: ${session.unitTitle}. Lesson: ${session.title}. '
        '${session.contextPrompt}$targetLine'
        '${roleplay == null ? '' : '\nRoleplay location: ${roleplay.location}. '
                  'Learner role: ${roleplay.learnerRole}. '
                  'Tutor role: ${roleplay.tutorRole}. '
                  'Goal: ${roleplay.goal}.'}';
  }

  List<String> get _requiredTargetPhrases {
    if (session.primarySkill == SpeakSkill.freeTalk) {
      return const [];
    }
    return session.targetPhrases;
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
      final result = await AppRouter.push<SpeakingResult>(
        context,
        (_) =>
            SpeakingPracticeScreen(request: _speakingRequest, autoStart: true),
        fullscreenDialog: true,
      );
      // A cancelled, silent, or very short call stays resumable. The course
      // must only advance after the same connected/utterance/time threshold
      // used by the speaking completion policy.
      return result?.meetsThreshold ?? false;
    }

    final screen = switch (skill) {
      SpeakSkill.alphabet => AlphabetLabScreen(deckId: _alphabetDeckId),
      SpeakSkill.connectors => const ConnectorsLabScreen(autoStart: true),
      SpeakSkill.liaison => const LiaisonLabScreen(autoStart: true),
      SpeakSkill.grammar => GrammarLabScreen(
        topic: _contextPrompt,
        autoStart: true,
      ),
      SpeakSkill.listening => ListeningLabScreen(
        topic: _contextPrompt,
        autoStart: true,
      ),
      SpeakSkill.reading => ReadingLibraryScreen(
        topic: _contextPrompt,
        autoStart: true,
      ),
      SpeakSkill.writing => WritingLabScreen(
        topic: session.title,
        contextPrompt: _contextPrompt,
        autoStart: true,
      ),
      SpeakSkill.vocabulary => SpeakCourseVocabularyScreen(
        topic: session.unitTitle,
        sessionTitle: session.title,
        contextPrompt: _contextPrompt,
        contentKey: session.contentKey,
        levelBand: _level,
        targetPhrases: session.targetPhrases,
      ),
      SpeakSkill.roleplay => SpeakingPracticeScreen(
        request: _speakingRequest,
        autoStart: true,
      ),
      // A review catalog item hands off to the shared review chooser so the
      // learner selects Reading, Listening, or Speaking from recent history.
      SpeakSkill.review => const SpeakReviewScreen(),
      SpeakSkill.freeTalk => SpeakingPracticeScreen(
        request: _speakingRequest,
        autoStart: true,
      ),
      SpeakSkill.speaking => throw StateError('Speaking is handled above'),
    };

    final result = await AppRouter.push<bool>(
      context,
      (_) => screen,
      fullscreenDialog: true,
    );
    return result == true;
  }

  String get _speakingKickoff {
    final modelLine = _requiredTargetPhrases.isEmpty
        ? 'model the first useful French phrase for this competency'
        : 'model "${_requiredTargetPhrases.first}" in French';
    return '(App instruction, not the student: this is the speaking step inside '
        'the course lesson "${session.title}". Explain the lesson context in '
        'one short English sentence, then $modelLine and ask the learner for '
        'one short response. Keep the lesson at ${_level.toUpperCase()} level '
        'and do not open with a generic free-talk question.)';
  }

  SpeakingPracticeRequest get _speakingRequest => SpeakingPracticeRequest(
    mode: switch (session.primarySkill) {
      SpeakSkill.speaking => SpeakingMode.guidedConversation,
      SpeakSkill.roleplay => SpeakingMode.roleplay,
      SpeakSkill.freeTalk => SpeakingMode.freeTalk,
      _ => throw StateError(
        'Speaking request cannot be created for ${session.primarySkill.label}.',
      ),
    },
    topic: session.title,
    level: _level,
    goal: 'Fluency',
    durationMinutes: session.estimatedMinutes.clamp(5, 15).toInt(),
    lessonContext: _contextPrompt,
    sessionTopic: session.title,
    contentKey: session.contentKey,
    kickoffMessage: _speakingKickoff,
  );

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
      return SpeakingLessonDetailScreen(session: session, onStart: _launch);
    }
    return _legacyLaunchShell(context);
  }

  Widget _legacyLaunchShell(BuildContext context) {
    return SpeakScaffold(
      child: Column(
        children: [
          SpeakHeader(
            title: session.primarySkill.label,
            subtitle: session.title,
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: const Icon(
                Icons.close_rounded,
                color: SpeakColors.inkSoft,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _error == null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 18),
                          Text(
                            _launching
                                ? 'Opening your ${session.primarySkill.label.toLowerCase()} practice…'
                                : 'Preparing your lesson…',
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
