import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/speaking_task_plan.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/review_material_service.dart';
import '../../services/speak_language_profile.dart';
import '../session/session_screen.dart';
import 'speak_review_screen.dart';
import 'speak_roadmap_screen.dart';

/// The single contract used by Home, Practice, Course, and onboarding.
///
/// Keeping the entry configuration separate from the live SessionScreen means
/// every surface can choose a different starting mode without creating another
/// legacy setup screen or another live-session implementation.
enum SpeakingMode {
  guidedConversation,
  roleplay,
  freeTalk,
  tefSectionA,
  tefSectionB,
  examTask,
  pictureDescription,
  pronunciationRepair,
}

class SpeakingPracticeRequest {
  const SpeakingPracticeRequest({
    this.mode = SpeakingMode.guidedConversation,
    this.topic = 'Travel',
    this.level = 'A1',
    this.goal = 'Fluency',
    this.durationMinutes = 10,
    this.lessonContext,
    this.stage,
    this.sessionTopic,
    this.contentKey,
    this.kickoffMessage,
    this.durationLimitSeconds,
    this.wrapUpNote,
    this.wrapUpLeadSeconds = 30,
    this.examMode = false,
    this.popResultImmediately = false,
    this.skipQuota = false,
  });

  final SpeakingMode mode;
  final String topic;
  final String level;
  final String goal;
  final int durationMinutes;
  final String? lessonContext;
  final String? stage;
  final String? sessionTopic;
  final String? contentKey;
  final String? kickoffMessage;
  final int? durationLimitSeconds;
  final String? wrapUpNote;
  final int wrapUpLeadSeconds;
  final bool examMode;
  final bool popResultImmediately;
  final bool skipQuota;

  SpeakingPracticeRequest copyWith({
    SpeakingMode? mode,
    String? topic,
    String? level,
    String? goal,
    int? durationMinutes,
  }) {
    return SpeakingPracticeRequest(
      mode: mode ?? this.mode,
      topic: topic ?? this.topic,
      level: level ?? this.level,
      goal: goal ?? this.goal,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      lessonContext: lessonContext,
      stage: stage,
      sessionTopic: sessionTopic,
      contentKey: contentKey,
      kickoffMessage: kickoffMessage,
      durationLimitSeconds: durationLimitSeconds,
      wrapUpNote: wrapUpNote,
      wrapUpLeadSeconds: wrapUpLeadSeconds,
      examMode: examMode,
      popResultImmediately: popResultImmediately,
      skipQuota: skipQuota,
    );
  }
}

class SpeakingPracticeScreen extends ConsumerStatefulWidget {
  const SpeakingPracticeScreen({
    super.key,
    this.request = const SpeakingPracticeRequest(),
    this.autoStart = false,
  });

  final SpeakingPracticeRequest request;
  final bool autoStart;

  @override
  ConsumerState<SpeakingPracticeScreen> createState() =>
      _SpeakingPracticeScreenState();
}

class _SpeakingPracticeScreenState
    extends ConsumerState<SpeakingPracticeScreen> {
  static const _topics = <String>[
    'Surprise me',
    'Café',
    'Travel',
    'Airport',
    'Directions',
    'Shopping',
    'Daily routine',
  ];
  static const _levels = <String>['A1', 'A2', 'B1', 'B2'];
  static const _modeOptions = <SpeakingMode>[
    SpeakingMode.guidedConversation,
    SpeakingMode.roleplay,
    SpeakingMode.freeTalk,
    SpeakingMode.tefSectionA,
    SpeakingMode.tefSectionB,
    SpeakingMode.pictureDescription,
    SpeakingMode.pronunciationRepair,
  ];
  static const _goals = <String>[
    'Fluency',
    'Pronunciation',
    'Grammar',
    'Vocabulary',
  ];
  static const _durations = <int>[5, 10, 15];

  late SpeakingMode _mode;
  late String _topic;
  late String _level;
  late String _goal;
  late int _durationMinutes;
  bool _launching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final request = widget.request;
    _mode = request.mode;
    _topic = request.topic;
    _level = SpeakingTaskPlan.normalizeLevel(_initialLevel(request));
    _goal = request.goal;
    _durationMinutes = request.durationMinutes;
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_launch());
      });
    }
  }

  /// Home, labs, and other profile-driven entry points construct the request
  /// with its safe A1 default. Course/onboarding/review requests pin a level
  /// with their own context. This keeps a B1/B2 learner from accidentally
  /// opening the universal speaking setup at A1 while preserving deliberate
  /// A1 trial/course sessions.
  String _initialLevel(SpeakingPracticeRequest request) {
    final hasPinnedContext =
        request.level.toUpperCase() != 'A1' ||
        request.lessonContext?.trim().isNotEmpty == true ||
        request.contentKey?.trim().isNotEmpty == true ||
        request.stage?.trim().isNotEmpty == true;
    if (hasPinnedContext) return request.level;
    return ref.read(learningStoreProvider).profile().level;
  }

  Future<void> _launch() async {
    if (_launching) return;
    setState(() {
      _launching = true;
      _error = null;
    });

    try {
      if (!widget.request.skipQuota) {
        final allowed = await ensureAiSessionQuota(
          context,
          ref.read(pilotAccessServiceProvider),
        );
        if (!allowed || !mounted) return;
      }

      LessonSpeechService.shared.deactivate();
      final request = widget.request.copyWith(
        mode: _mode,
        topic: _topic,
        level: _level,
        goal: _goal,
        durationMinutes: _durationMinutes,
      );
      final plan = SpeakingTaskPlan.create(
        mode: _modeKey(_mode),
        level: _level,
        topic: _topic,
        goal: _goal,
      );
      final introduceTutor = _shouldIntroduceTutor();
      final result = await AppRouter.push<SpeakingResult>(
        context,
        (_) => SessionScreen(
          apiKey: ApiKeys.geminiKey,
          sessionTopic: request.sessionTopic ?? plan.title,
          contentKey: request.contentKey,
          stage: _stageFor(request),
          examMode:
              request.examMode ||
              request.mode == SpeakingMode.examTask ||
              request.mode == SpeakingMode.tefSectionA ||
              request.mode == SpeakingMode.tefSectionB,
          lessonContext: _contextFor(request, plan),
          levelOverride: _level,
          kickoffMessage:
              request.kickoffMessage ??
              _kickoffFor(plan, introduceTutor: introduceTutor),
          durationLimitSeconds:
              request.durationLimitSeconds ?? request.durationMinutes * 60,
          wrapUpNote: request.wrapUpNote ?? _wrapUpNoteFor(request),
          wrapUpLeadSeconds: request.wrapUpLeadSeconds,
          popResultImmediately: request.popResultImmediately,
        ),
        fullscreenDialog: true,
      );
      // Auto-start is used by onboarding and course hand-offs. Those callers
      // expect the universal setup route to resolve with the live result
      // instead of leaving an extra setup screen on the navigation stack.
      if (widget.autoStart && mounted) Navigator.of(context).pop(result);
    } catch (error, stackTrace) {
      debugPrint('Speaking setup failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _error =
              'We could not prepare this practice. Your settings are '
              'still here — try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  bool _shouldIntroduceTutor() {
    final speakingSessions = ref
        .read(storageServiceProvider)
        .getAllSessions()
        .where(
          (session) =>
              session.stage == 'speaking' ||
              session.stage == 'speaking_guided' ||
              session.stage == 'speaking_exam' ||
              session.stage == 'speaking_guided' ||
              session.stage == 'picture_description' ||
              session.stage == 'pronunciation_repair' ||
              session.stage == 'free_talk',
        )
        .length;
    return speakingSessions < 3;
  }

  String _kickoffFor(SpeakingTaskPlan plan, {required bool introduceTutor}) {
    final introduction = introduceTutor
        ? 'Introduce yourself as ${ActiveTutor.current.displayName}, say that '
              'you are the learner\'s French tutor for today, and name the '
              'activity. Keep the introduction to two short sentences.'
        : 'Do not introduce yourself or explain the app; start the activity immediately.';
    return '(Note from the app, not the student: the learner just joined this '
        '${plan.modeLabel} session. $introduction Begin the first stage from '
        'the SPEAKING TASK PLAN now. Speak briefly, then wait.)';
  }

  String _stageFor(SpeakingPracticeRequest request) {
    if (request.stage != null && request.stage!.trim().isNotEmpty) {
      return request.stage!;
    }
    return switch (request.mode) {
      SpeakingMode.guidedConversation ||
      SpeakingMode.pronunciationRepair => 'speaking_guided',
      SpeakingMode.roleplay => 'speaking',
      SpeakingMode.tefSectionA ||
      SpeakingMode.tefSectionB ||
      SpeakingMode.examTask => 'speaking_exam',
      SpeakingMode.freeTalk || SpeakingMode.pictureDescription => 'free_talk',
    };
  }

  String _contextFor(SpeakingPracticeRequest request, SpeakingTaskPlan plan) {
    final existing = request.lessonContext?.trim();
    if (existing != null && existing.isNotEmpty) {
      return '$existing\n\n${plan.liveContext}';
    }
    return plan.liveContext;
  }

  String _wrapUpNoteFor(SpeakingPracticeRequest request) {
    return '(App instruction: this practice is ending soon. Give one short '
        'encouraging correction, name one useful phrase from the conversation, '
        'and invite the learner to finish their current thought.)';
  }

  Future<void> _pickMode() async {
    final value = await _showPicker<SpeakingMode>(
      title: 'Speaking mode',
      selected: _mode,
      options: _modeOptions,
      label: _modeLabel,
      detail: _modeDetail,
      icon: _modeIcon,
    );
    if (value != null && mounted) setState(() => _mode = value);
  }

  Future<void> _pickTopic() async {
    final value = await _showPicker<String>(
      title: 'Topic',
      selected: _topic,
      options: _topics,
      label: (value) => value,
    );
    if (value != null && mounted) setState(() => _topic = value);
  }

  Future<void> _pickLevel() async {
    final value = await _showPicker<String>(
      title: 'Level',
      selected: _level,
      options: _levels,
      label: (value) => value,
    );
    if (value != null && mounted) setState(() => _level = value);
  }

  Future<void> _pickGoal() async {
    final value = await _showPicker<String>(
      title: 'Goal',
      selected: _goal,
      options: _goals,
      label: (value) => value,
    );
    if (value != null && mounted) setState(() => _goal = value);
  }

  Future<void> _pickDuration() async {
    final value = await _showPicker<int>(
      title: 'Time',
      selected: _durationMinutes,
      options: _durations,
      label: (value) => '$value minutes',
    );
    if (value != null && mounted) setState(() => _durationMinutes = value);
  }

  Future<T?> _showPicker<T>({
    required String title,
    required T selected,
    required List<T> options,
    required String Function(T) label,
    String Function(T)? detail,
    IconData Function(T)? icon,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: DesignTokens.nightSurface,
      isScrollControlled: true,
      builder: (_) => _SpeakingPickerSheet<T>(
        title: title,
        selected: selected,
        options: options,
        label: label,
        detail: detail,
        icon: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recentSpeaking =
        ReviewMaterialService.recentSessions(ref.watch(storageServiceProvider))
            .where(
              (session) => const {
                'Speaking',
                'Roleplay',
                'Exam speaking',
              }.contains(session.skill),
            )
            .take(3)
            .toList(growable: false);
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _header(),
            const SizedBox(height: 14),
            _workspaceTabs(context),
            const SizedBox(height: 34),
            Text('SPEAKING PRACTICE', style: _eyebrow()),
            const SizedBox(height: 8),
            Text(
              'Build the confidence to speak',
              style: DesignTokens.display(
                30,
              ).copyWith(color: DesignTokens.nightText),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a practice style and your French tutor will teach, coach, '
              'and adapt to your level.',
              style: _body(14, color: DesignTokens.nightMuted, height: 1.4),
            ),
            const SizedBox(height: 22),
            _SelectionTile(
              icon: _modeIcon(_mode),
              label: 'Practice style',
              value: _modeLabel(_mode),
              detail: _modeDetail(_mode),
              onTap: _pickMode,
            ),
            const SizedBox(height: 10),
            _SelectionTile(
              icon: Icons.work_outline_rounded,
              label: 'Topic',
              value: _topic,
              detail: 'A real-world conversation context',
              onTap: _pickTopic,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CompactSelection(
                    label: 'Level',
                    value: _level,
                    onTap: _pickLevel,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactSelection(
                    label: 'Goal',
                    value: _goal,
                    onTap: _pickGoal,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactSelection(
                    label: 'Time',
                    value: '$_durationMinutes min',
                    onTap: _pickDuration,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorPanel(message: _error!),
            ],
            const SizedBox(height: 18),
            _PlanPreviewCard(
              plan: SpeakingTaskPlan.create(
                mode: _modeKey(_mode),
                level: _level,
                topic: _topic,
                goal: _goal,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _launching ? null : _launch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DesignTokens.nightAccent,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: DesignTokens.nightAccent.withValues(
                    alpha: 0.55,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _launching
                    ? const SizedBox(
                        width: 21,
                        height: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: Colors.black,
                        ),
                      )
                    : Text(
                        'Start speaking',
                        style: _body(
                          15,
                          color: Colors.black,
                          weight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            if (recentSpeaking.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text('RECENT SPEAKING', style: _eyebrow()),
              const SizedBox(height: 10),
              for (var index = 0; index < recentSpeaking.length; index++)
                _recentSpeakingRow(
                  context,
                  recentSpeaking[index],
                  showDivider: index > 0,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: DesignTokens.nightText,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'Speaking',
          style: DesignTokens.display(
            21,
          ).copyWith(color: DesignTokens.nightText),
        ),
      ],
    );
  }

  Widget _workspaceTabs(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _workspaceTab(
              label: 'Course',
              selected: false,
              onTap: () =>
                  AppRouter.push(context, (_) => const SpeakRoadmapScreen()),
            ),
          ),
          Expanded(
            child: _workspaceTab(
              label: 'Practice',
              selected: true,
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _workspaceTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? DesignTokens.nightAccentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: DesignTokens.body(13, weight: FontWeight.w700).copyWith(
              color: selected
                  ? DesignTokens.nightAccent
                  : DesignTokens.nightMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _recentSpeakingRow(
    BuildContext context,
    ReviewSessionSummary session, {
    required bool showDivider,
  }) {
    return Column(
      children: [
        if (showDivider)
          const Divider(height: 1, color: DesignTokens.nightHairline),
        Semantics(
          button: true,
          label: 'Open saved transcript for ${session.displayTitle}',
          child: InkWell(
            onTap: () => AppRouter.push(
              context,
              (_) => SavedSpeakingTranscriptScreen(session: session),
            ),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DesignTokens.nightSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: DesignTokens.nightHairline),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: DesignTokens.nightAccentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.forum_outlined,
                      color: DesignTokens.nightAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesignTokens.body(
                            13,
                            weight: FontWeight.w700,
                          ).copyWith(color: DesignTokens.nightText),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${session.skill} · Open saved transcript',
                          style: DesignTokens.body(
                            11,
                          ).copyWith(color: DesignTokens.nightMuted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: DesignTokens.nightAccent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _eyebrow() => DesignTokens.body(
    11,
    weight: FontWeight.w800,
  ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.2);

  TextStyle _body(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) => DesignTokens.body(
    size,
    weight: weight,
  ).copyWith(color: color ?? DesignTokens.nightText, height: height);
}

String _modeKey(SpeakingMode mode) => switch (mode) {
  SpeakingMode.guidedConversation => 'guided_conversation',
  SpeakingMode.roleplay => 'roleplay',
  SpeakingMode.freeTalk => 'free_talk',
  SpeakingMode.tefSectionA => 'tef_section_a',
  SpeakingMode.tefSectionB => 'tef_section_b',
  SpeakingMode.examTask => 'tef_section_a',
  SpeakingMode.pictureDescription => 'picture_description',
  SpeakingMode.pronunciationRepair => 'pronunciation_repair',
};

String _modeLabel(SpeakingMode mode) => switch (mode) {
  SpeakingMode.guidedConversation => 'Guided conversation',
  SpeakingMode.roleplay => 'Roleplay',
  SpeakingMode.freeTalk => 'Free talk',
  SpeakingMode.tefSectionA => 'TEF / TCF · Section A',
  SpeakingMode.tefSectionB => 'TEF / TCF · Section B',
  SpeakingMode.examTask => 'TEF / TCF · Section A',
  SpeakingMode.pictureDescription => 'Picture description',
  SpeakingMode.pronunciationRepair => 'Pronunciation repair',
};

String _modeDetail(SpeakingMode mode) => switch (mode) {
  SpeakingMode.guidedConversation => 'Hear it, repeat it, fix it, use it',
  SpeakingMode.roleplay => 'Practice a real-life scene',
  SpeakingMode.freeTalk => 'Talk naturally about any topic',
  SpeakingMode.tefSectionA => 'Ask questions and obtain information',
  SpeakingMode.tefSectionB => 'Argue, explain, and convince',
  SpeakingMode.examTask => 'Ask questions and obtain information',
  SpeakingMode.pictureDescription => 'Describe what you can see',
  SpeakingMode.pronunciationRepair => 'Repair one sound and say it again',
};

IconData _modeIcon(SpeakingMode mode) => switch (mode) {
  SpeakingMode.guidedConversation => Icons.record_voice_over_outlined,
  SpeakingMode.roleplay => Icons.chat_bubble_outline_rounded,
  SpeakingMode.freeTalk => Icons.people_outline_rounded,
  SpeakingMode.tefSectionA ||
  SpeakingMode.tefSectionB ||
  SpeakingMode.examTask => Icons.fact_check_outlined,
  SpeakingMode.pictureDescription => Icons.image_outlined,
  SpeakingMode.pronunciationRepair => Icons.graphic_eq_rounded,
};

class _PlanPreviewCard extends StatelessWidget {
  const _PlanPreviewCard({required this.plan});

  final SpeakingTaskPlan plan;

  @override
  Widget build(BuildContext context) {
    final language = SpeakLanguageProfile.forLevel(plan.level);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: DesignTokens.nightAccentSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: DesignTokens.nightAccent.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: DesignTokens.nightAccent,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plan.title,
                  style: DesignTokens.body(
                    15,
                    weight: FontWeight.w800,
                  ).copyWith(color: DesignTokens.nightText),
                ),
              ),
              Text(
                plan.level,
                style: DesignTokens.body(
                  12,
                  weight: FontWeight.w800,
                ).copyWith(color: DesignTokens.nightAccent),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            plan.objective.capitalizeSentence(),
            style: DesignTokens.body(
              12,
            ).copyWith(color: DesignTokens.nightMuted, height: 1.35),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: DesignTokens.nightAccent,
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${plan.level} guardrail · ${language.tutorTurnWordLimit} per tutor turn · '
                  '${language.shortLabel}',
                  style: DesignTokens.body(
                    11,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.nightText, height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _PlanTag(label: '${plan.stages.length} guided steps'),
              _PlanTag(label: '${plan.successCriteria.length} success checks'),
              _PlanTag(label: plan.modeLabel),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanTag extends StatelessWidget {
  const _PlanTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: DesignTokens.nightCanvas.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: DesignTokens.body(
          10,
          weight: FontWeight.w700,
        ).copyWith(color: DesignTokens.nightText),
      ),
    );
  }
}

extension on String {
  String capitalizeSentence() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

class _SelectionTile extends StatelessWidget {
  const _SelectionTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $value',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: DesignTokens.nightSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DesignTokens.nightHairline),
          ),
          child: Row(
            children: [
              Icon(icon, color: DesignTokens.nightAccent, size: 24),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: _tileText(11, DesignTokens.nightMuted)),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: _tileText(
                        15,
                        DesignTokens.nightText,
                        FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(detail, style: _tileText(11, DesignTokens.nightMuted)),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: DesignTokens.nightAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _tileText(
    double size,
    Color color, [
    FontWeight weight = FontWeight.w400,
  ]) => DesignTokens.body(size, weight: weight).copyWith(color: color);
}

class _CompactSelection extends StatelessWidget {
  const _CompactSelection({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.fromLTRB(11, 10, 7, 9),
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: DesignTokens.body(
                10,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.nightMuted),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.body(
                      12,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.nightText),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: DesignTokens.nightAccent,
                  size: 17,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1E1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6C3B2B)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: DesignTokens.nightAccent,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: DesignTokens.body(
                12,
              ).copyWith(color: DesignTokens.nightText),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeakingPickerSheet<T> extends StatelessWidget {
  const _SpeakingPickerSheet({
    required this.title,
    required this.selected,
    required this.options,
    required this.label,
    this.detail,
    this.icon,
  });

  final String title;
  final T selected;
  final List<T> options;
  final String Function(T) label;
  final String Function(T)? detail;
  final IconData Function(T)? icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: DesignTokens.nightMuted,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: DesignTokens.display(
                20,
              ).copyWith(color: DesignTokens.nightText),
            ),
            const SizedBox(height: 10),
            ...options.map(
              (option) => _PickerOption<T>(
                value: option,
                selected: option == selected,
                label: label(option),
                detail: detail?.call(option),
                icon: icon?.call(option),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerOption<T> extends StatelessWidget {
  const _PickerOption({
    required this.value,
    required this.selected,
    required this.label,
    this.detail,
    this.icon,
  });

  final T value;
  final bool selected;
  final String label;
  final String? detail;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected
              ? DesignTokens.nightAccentSoft
              : DesignTokens.nightSurfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? DesignTokens.nightAccent
                : DesignTokens.nightHairline,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: selected
                    ? DesignTokens.nightAccent
                    : DesignTokens.nightMuted,
                size: 21,
              ),
              const SizedBox(width: 11),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: DesignTokens.body(
                      14,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.nightText),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail!,
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, color: DesignTokens.nightAccent),
          ],
        ),
      ),
    );
  }
}
