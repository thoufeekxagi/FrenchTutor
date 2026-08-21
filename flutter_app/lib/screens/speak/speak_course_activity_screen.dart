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
import '../../services/premium_access_gate.dart';
import '../../services/speak_roadmap_service.dart';
import '../../services/starter_cover_resolver.dart';
import '../../services/subscription_gate_service.dart';
import '../labs/alphabet_lab_screen.dart';
import '../labs/connectors_lab_screen.dart';
import '../labs/grammar_lab_screen.dart';
import '../labs/liaison_lab_screen.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/roleplay_lab_screen.dart';
import '../labs/writing_lab_screen.dart';
import '../reading/reading_library_screen.dart';
import '../session/session_screen.dart';
import 'speak_course_vocabulary_screen.dart';
import 'speak_free_talk_screen.dart';
import 'speak_review_screen.dart';
import 'speak_ui.dart';

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

  String get _level {
    final keyLevel = session.level.toUpperCase();
    return const {'A1', 'A2', 'B1', 'B2'}.contains(keyLevel)
        ? keyLevel
        : ref.read(learningStoreProvider).profile().level.toUpperCase();
  }

  String get _contextPrompt {
    final target = session.targetPhrases.isEmpty
        ? ''
        : '\nTarget phrases: ${session.targetPhrases.join('; ')}.';
    return 'Course unit: ${session.unitTitle}. Lesson: ${session.title}. '
        '${session.contextPrompt}$target';
  }

  @override
  void initState() {
    super.initState();
    if (!_isConversation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _launch();
      });
    }
  }

  bool get _isConversation => switch (session.primarySkill) {
    SpeakSkill.speaking || SpeakSkill.roleplay || SpeakSkill.freeTalk => true,
    _ => false,
  };

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
        _error = 'This lesson could not be opened. Please try again.';
      });
    }
  }

  Future<bool> _openPractice() async {
    final skill = session.primarySkill;
    if (skill == SpeakSkill.speaking) {
      final allowed = await ensureAiSessionQuota(
        context,
        ref.read(pilotAccessServiceProvider),
      );
      if (!allowed || !mounted) return false;
      LessonSpeechService.shared.deactivate();
      final result = await AppRouter.push<SpeakingResult>(
        context,
        (_) => SessionScreen(
          apiKey: ApiKeys.geminiKey,
          sessionTopic: session.title,
          contentKey: session.contentKey,
          stage: skill.wireName,
          lessonContext: _contextPrompt,
          kickoffMessage: _speakingKickoff,
        ),
        fullscreenDialog: true,
      );
      return result != null;
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
      SpeakSkill.roleplay => RoleplayLabScreen(
        topic: _contextPrompt,
        autoStart: true,
      ),
      // A review catalog item hands off to the shared review chooser so the
      // learner selects Reading, Listening, or Speaking from recent history.
      SpeakSkill.review => const SpeakReviewScreen(),
      SpeakSkill.freeTalk => const SpeakFreeTalkScreen(),
      SpeakSkill.speaking => throw StateError('Speaking is handled above'),
    };

    final result = await AppRouter.push<bool>(
      context,
      (_) => screen,
      fullscreenDialog: true,
    );
    return result == true;
  }

  String get _speakingKickoff =>
      '(App instruction, not the student: this is the speaking step inside '
      'the course lesson "${session.title}". Explain the lesson context in '
      'one short English sentence, then model "${session.targetPhrases.isEmpty ? 'Bonjour !' : session.targetPhrases.first}" '
      'in French and ask the learner for one short response. Keep the lesson '
      'at ${_level.toUpperCase()} level and do not open with a generic free-talk question.)';

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
    if (_isConversation) return _sceneBrief(context);
    return _legacyLaunchShell(context);
  }

  Widget _sceneBrief(BuildContext context) {
    final roleplay = session.roleplay;
    final goal =
        roleplay?.goal ??
        (session.subtitle.trim().isEmpty
            ? session.primarySkill.description
            : session.subtitle);
    final learnerRole = roleplay?.learnerRole ?? 'You';
    final tutorRole = roleplay?.tutorRole ?? 'French conversation partner';
    final openingLine =
        roleplay?.openingLine ??
        (session.targetPhrases.isEmpty
            ? 'Bonjour !'
            : session.targetPhrases.first);

    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Close scene brief',
                  child: IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: DesignTokens.nightText,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Speaking Studio',
                    style: DesignTokens.display(
                      20,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.nightText),
                  ),
                ),
                Text(
                  '${session.level}  ·  ${session.estimatedMinutes} min',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              'BEFORE YOU SPEAK',
              style: DesignTokens.body(
                11,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.2),
            ),
            const SizedBox(height: 6),
            Text(
              session.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.display(
                30,
              ).copyWith(color: DesignTokens.nightText),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: SizedBox(
                height: 192,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(_sceneCoverAsset(session), fit: BoxFit.cover),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.08),
                            Colors.black.withValues(alpha: 0.78),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          'SCENE ${session.index}',
                          style: DesignTokens.body(11, weight: FontWeight.w700)
                              .copyWith(
                                color: DesignTokens.nightAccent,
                                letterSpacing: 1.1,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              goal,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.body(
                16,
                weight: FontWeight.w600,
              ).copyWith(color: DesignTokens.nightText, height: 1.35),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _sceneDetail(
                    icon: Icons.person_outline_rounded,
                    label: 'Your role',
                    value: learnerRole,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _sceneDetail(
                    icon: Icons.record_voice_over_rounded,
                    label: 'Marcus',
                    value: tutorRole,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              'MARCUS SAYS',
              style: DesignTokens.body(
                11,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.2),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
              decoration: BoxDecoration(
                color: DesignTokens.nightSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: DesignTokens.nightHairline),
              ),
              child: Text(
                openingLine,
                style: DesignTokens.body(
                  18,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.nightText, height: 1.35),
              ),
            ),
            const SizedBox(height: 26),
            if (_error != null) ...[
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.nightMuted),
              ),
              const SizedBox(height: 12),
            ],
            Semantics(
              button: true,
              label: 'Enter the speaking scene',
              child: GestureDetector(
                onTap: _launching ? null : _launch,
                child: Container(
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _launching
                        ? DesignTokens.nightHairline
                        : DesignTokens.nightAccent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: _launching
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: DesignTokens.nightAccent,
                          ),
                        )
                      : Text(
                          'I’m ready — enter the scene',
                          style: DesignTokens.body(
                            15,
                            weight: FontWeight.w700,
                          ).copyWith(color: Colors.black),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sceneDetail({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DesignTokens.nightAccent, size: 19),
          const SizedBox(height: 9),
          Text(
            label.toUpperCase(),
            style: DesignTokens.body(
              10,
              weight: FontWeight.w700,
            ).copyWith(color: DesignTokens.nightMuted, letterSpacing: 0.6),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DesignTokens.body(
              13,
              weight: FontWeight.w600,
            ).copyWith(color: DesignTokens.nightText),
          ),
        ],
      ),
    );
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

String _sceneCoverAsset(SpeakRoadmapSession session) {
  final resolved = StarterCoverResolver.resolve(title: session.title);
  if (resolved != null && resolved.startsWith('asset:')) {
    return resolved.substring('asset:'.length);
  }
  return switch (session.index % 4) {
    0 => 'assets/starter_covers/market.png',
    1 => 'assets/starter_covers/station.png',
    2 => 'assets/starter_covers/lantern.png',
    _ => 'assets/starter_covers/boat.png',
  };
}
