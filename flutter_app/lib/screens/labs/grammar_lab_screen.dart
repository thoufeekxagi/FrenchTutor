import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/grammar_course_catalog.dart';
import '../../design/app_router.dart';
import '../../models/grammar_course.dart';
import '../../models/grammar_course_session_result.dart';
import '../../models/grammar_course_v2.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_speech_service.dart';
import '../grammar/grammar_v2_home_screen.dart';
import '../grammar/grammar_v2_lesson_screen.dart';

/// Grammar owns complete, bounded sessions. A session has one objective and
/// four or five connected steps; the home never exposes those steps as cards.
class GrammarLabScreen extends ConsumerStatefulWidget {
  const GrammarLabScreen({super.key, this.topic, this.autoStart = false});

  final String? topic;
  final bool autoStart;

  @override
  ConsumerState<GrammarLabScreen> createState() => _GrammarLabScreenState();
}

class _GrammarLabScreenState extends ConsumerState<GrammarLabScreen> {
  static const _initialSessionCount = 3;

  List<GrammarCourseSession> _generatedSessions = const [];
  final Set<String> _preparingKeys = <String>{};
  String? _preparationError;

  @override
  void initState() {
    super.initState();
    _reloadSessions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.autoStart) {
        unawaited(_startCourseSession());
      } else {
        unawaited(_preparePresentSessions());
      }
    });
  }

  void _reloadSessions() {
    _generatedSessions = ref.read(grammarLessonStoreProvider).list();
  }

  Future<void> _preparePresentSessions() async {
    for (final mode in GrammarV2Mode.values) {
      await _prepareSessions(
        mode: mode,
        tense: GrammarV2Tenses.present,
        targetCount: _initialSessionCount,
      );
    }
  }

  Future<void> _prepareSessions({
    required GrammarV2Mode mode,
    required String tense,
    int targetCount = _initialSessionCount,
  }) async {
    final profileStore = ref.read(learningStoreProvider);
    final level = GrammarCourseCatalogLevel.normalize(
      profileStore.profile().level,
    );
    final key = '$level:${mode.name}:$tense';
    if (!_preparingKeys.add(key)) return;
    if (mounted) setState(() => _preparationError = null);
    try {
      final profile = profileStore.profile();
      final content = ref.read(contentServiceProvider);
      final store = ref.read(grammarLessonStoreProvider);
      final existing = store.list(mode: mode, level: level, tense: tense);
      final missing = targetCount - existing.length;
      if (missing <= 0) return;
      final starterTitles = GrammarCourseCatalog.forMode(
        mode,
        level: level,
        tense: tense,
      ).map((session) => session.title);
      final generated = await ref
          .read(lessonAgentServiceProvider)
          .generateGrammarCourseSessions(
            mode: mode,
            tense: tense,
            levelBand: level,
            learnerGoal: profile.goal,
            interests: profile.interests,
            knownVocab: content.knownVocabWords(profileStore.allSRSStates()),
            avoidTitles: [
              ...existing.map((session) => session.title),
              ...starterTitles,
            ],
            count: missing,
          );
      for (final session in generated) {
        store.insertGenerated(session);
      }
      _reloadSessions();
      _prewarmSessions();
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      debugPrint(
        'Grammar session preparation failed ($key): $error\n$stackTrace',
      );
      if (mounted) {
        setState(
          () => _preparationError =
              'Your ready-made sessions are available. We could not prepare the personalised reserve yet.',
        );
      }
    } finally {
      _preparingKeys.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<void> _startCourseSession() async {
    final level = GrammarCourseCatalogLevel.normalize(
      ref.read(learningStoreProvider).profile().level,
    );
    final sessions = _sessionsFor(
      GrammarV2Mode.guided,
      GrammarV2Tenses.present,
      level,
    );
    if (sessions.isEmpty || !mounted) {
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    final result = await AppRouter.push<GrammarCourseSessionResult>(
      context,
      (_) => GrammarV2LessonScreen(session: sessions.first),
      fullscreenDialog: true,
    );
    if (mounted) Navigator.of(context).pop(result?.completed == true);
  }

  List<GrammarCourseSession> _sessionsFor(
    GrammarV2Mode mode,
    String tense,
    String level,
  ) {
    final generated = _generatedSessions.where(
      (session) =>
          session.mode == mode &&
          session.level == level &&
          session.tense == tense,
    );
    final sessions = generated.isNotEmpty
        ? generated.toList()
        : GrammarCourseCatalog.forMode(mode, level: level, tense: tense);
    final fingerprints = <String>{};
    return sessions
        .where((session) => fingerprints.add(grammarCourseFingerprint(session)))
        .toList(growable: false);
  }

  void _prewarmSessions() {
    final items = <SpeechItem>[];
    for (final session in _generatedSessions) {
      for (var index = 0; index < session.steps.length; index++) {
        final step = session.steps[index];
        final prefix = 'grammar-session:${session.id}:step:$index';
        items.add(
          SpeechItem(
            text: step.target,
            language: 'fr-FR',
            contentItemId: '$prefix:target',
          ),
        );
        if (step.partnerFrench != null) {
          items.add(
            SpeechItem(
              text: step.partnerFrench!,
              language: 'fr-FR',
              contentItemId: '$prefix:partner',
            ),
          );
        }
        for (
          var choiceIndex = 0;
          choiceIndex < step.choices.length;
          choiceIndex++
        ) {
          items.add(
            SpeechItem(
              text: step.choices[choiceIndex],
              language: 'fr-FR',
              contentItemId: '$prefix:choice:$choiceIndex',
            ),
          );
        }
      }
    }
    if (items.isNotEmpty) {
      unawaited(LessonSpeechService.shared.prewarmNarration(items));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.autoStart) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return GrammarV2HomeScreen(
      generatedSessions: _generatedSessions,
      isPreparingSessions: _preparingKeys.isNotEmpty,
      preparationError: _preparationError,
      onRetryPreparation: () => unawaited(_preparePresentSessions()),
      onPrepareSessions: (mode, tense) =>
          _prepareSessions(mode: mode, tense: tense),
    );
  }
}
