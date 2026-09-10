import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/grammar_course_catalog.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/grammar_course.dart';
import '../../models/grammar_course_session_result.dart';
import '../../models/grammar_course_v2.dart';
import '../../providers/database_provider.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../speak/v3_settings_screen.dart';
import 'grammar_v2_lesson_screen.dart';

/// Grammar home: the grid contains sessions, never individual exercise
/// sentences. Each session opens one bounded 4–5-step learning flow.
class GrammarV2HomeScreen extends ConsumerStatefulWidget {
  const GrammarV2HomeScreen({
    super.key,
    required this.generatedSessions,
    this.isPreparingSessions = false,
    this.preparationError,
    this.onRetryPreparation,
    this.onPrepareSessions,
  });

  final List<GrammarCourseSession> generatedSessions;
  final bool isPreparingSessions;
  final String? preparationError;
  final VoidCallback? onRetryPreparation;
  final Future<void> Function(GrammarV2Mode mode, String tense)?
  onPrepareSessions;

  @override
  ConsumerState<GrammarV2HomeScreen> createState() =>
      _GrammarV2HomeScreenState();
}

class _GrammarV2HomeScreenState extends ConsumerState<GrammarV2HomeScreen> {
  GrammarV2Mode _mode = GrammarV2Mode.guided;
  String _tense = GrammarV2Tenses.present;
  String? _selectedSessionId;

  String get _level => GrammarCourseCatalogLevel.normalize(
    ref.watch(learningStoreProvider).profile().level,
  );

  List<GrammarCourseSession> get _sessions {
    final generated = widget.generatedSessions.where(
      (session) =>
          session.mode == _mode &&
          session.level == _level &&
          (_tense == GrammarV2Tenses.mixed || session.tense == _tense),
    );
    // Authored sessions are an instant fallback. Once the personalized
    // reserve exists, it becomes the complete visible set so the home stays
    // a bounded set of coherent sessions rather than growing forever.
    final starter = grammarCourseStarterSessions.where(
      (session) =>
          session.mode == _mode &&
          session.level == _level &&
          (_tense == GrammarV2Tenses.mixed || session.tense == _tense),
    );
    final source = generated.isNotEmpty ? generated : starter;
    final seen = <String>{};
    return source
        .where((session) => seen.add(grammarCourseFingerprint(session)))
        .toList(growable: false);
  }

  GrammarCourseSession? get _selectedSession {
    final sessions = _sessions;
    if (sessions.isEmpty) return null;
    for (final session in sessions) {
      if (session.id == _selectedSessionId) return session;
    }
    for (final session in sessions) {
      if (!_isCompleted(session)) return session;
    }
    return sessions.first;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    final selected = _selectedSession;
    final completed = sessions.where(_isCompleted).length;
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: WebConstrainedView(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 34),
            children: [
              _header(context),
              const SizedBox(height: 22),
              Text(
                'Build confidence with grammar',
                style: DesignTokens.display(30),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose one focus, practise a connected session, and use it in context.',
                style: DesignTokens.body(
                  14,
                ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _levelBadge(level: _level),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${sessions.length} sessions ready · $completed complete',
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.muted),
                    ),
                  ),
                  if (widget.isPreparingSessions)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _focusPicker(),
              const SizedBox(height: 20),
              _modePicker(),
              const SizedBox(height: 24),
              _sectionLabel('NEXT ${_mode.label.toUpperCase()} SESSION'),
              const SizedBox(height: 10),
              if (selected != null)
                _featuredSession(selected)
              else
                _emptySessionCard(),
              const SizedBox(height: 28),
              _sectionLabel('${_mode.label.toUpperCase()} SESSIONS'),
              const SizedBox(height: 10),
              if (sessions.isEmpty)
                _emptySessionCard(compact: true)
              else
                _sessionGrid(sessions),
              if (widget.preparationError != null) ...[
                const SizedBox(height: 14),
                _statusCard(
                  widget.preparationError!,
                  action: widget.onRetryPreparation,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => SizedBox(
    height: 52,
    child: Row(
      children: [
        Semantics(
          button: true,
          label: 'Back',
          child: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: DesignTokens.ink,
          ),
        ),
        Expanded(
          child: Text(
            'Grammar',
            textAlign: TextAlign.center,
            style: DesignTokens.display(21),
          ),
        ),
        Semantics(
          button: true,
          label: 'Grammar settings',
          child: IconButton(
            onPressed: () =>
                AppRouter.push(context, (_) => const V3SettingsScreen()),
            icon: const Icon(Icons.tune_rounded),
            color: DesignTokens.primary,
          ),
        ),
      ],
    ),
  );

  Widget _focusPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionLabel('GRAMMAR FOCUS'),
      const SizedBox(height: 9),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tense in GrammarV2Tenses.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(tense),
                  selected: _tense == tense,
                  onSelected: (_) => _setTense(tense),
                  selectedColor: DesignTokens.primary,
                  backgroundColor: DesignTokens.surface,
                  side: BorderSide(color: DesignTokens.hairline),
                  labelStyle: DesignTokens.label(11).copyWith(
                    color: _tense == tense
                        ? DesignTokens.onPrimary
                        : DesignTokens.inkSoft,
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _modePicker() {
    const modes = [
      (GrammarV2Mode.guided, 'Guided', Icons.edit_note_rounded),
      (GrammarV2Mode.complete, 'Complete', Icons.checklist_rounded),
      (GrammarV2Mode.roleplay, 'Roleplay', Icons.forum_outlined),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Row(
        children: [
          for (final entry in modes)
            Expanded(
              child: Semantics(
                button: true,
                selected: _mode == entry.$1,
                label: '${entry.$2} grammar mode',
                child: InkWell(
                  onTap: () => _setMode(entry.$1),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: DesignTokens.durationFast,
                    constraints: const BoxConstraints(minHeight: 58),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _mode == entry.$1
                          ? DesignTokens.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          entry.$3,
                          size: 19,
                          color: _mode == entry.$1
                              ? DesignTokens.onPrimary
                              : DesignTokens.muted,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.$2,
                          style: DesignTokens.label(10).copyWith(
                            color: _mode == entry.$1
                                ? DesignTokens.onPrimary
                                : DesignTokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _featuredSession(GrammarCourseSession session) {
    final complete = _isCompleted(session);
    final phases = switch (session.mode) {
      GrammarV2Mode.guided => const [
        (Icons.touch_app_outlined, 'Choose'),
        (Icons.check_circle_outline_rounded, 'Check'),
        (Icons.phone_in_talk_outlined, 'Tutor'),
      ],
      GrammarV2Mode.complete => const [
        (Icons.menu_book_outlined, 'Read'),
        (Icons.checklist_rounded, 'Build'),
        (Icons.refresh_rounded, 'Recall'),
      ],
      GrammarV2Mode.roleplay => const [
        (Icons.chat_bubble_outline_rounded, 'Read'),
        (Icons.reply_outlined, 'Reply'),
        (Icons.phone_in_talk_outlined, 'Tutor'),
      ],
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
        border: Border.all(color: DesignTokens.primary),
        boxShadow: DesignTokens.surfaceShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sessionIcon(session, large: true),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.title, style: DesignTokens.display(18)),
                    const SizedBox(height: 4),
                    Text(
                      '${session.level} · ${session.steps.length} grammar steps',
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.muted),
                    ),
                  ],
                ),
              ),
              if (complete)
                Icon(Icons.check_circle_rounded, color: DesignTokens.success),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            session.subtitle,
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            '${session.tense} · ${session.grammarFocus}',
            style: DesignTokens.body(12).copyWith(color: DesignTokens.muted),
          ),
          const SizedBox(height: 16),
          Divider(color: DesignTokens.hairline),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final phase in phases)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(phase.$1, color: DesignTokens.primary, size: 17),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          phase.$2,
                          style: DesignTokens.label(10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          PrimaryActionButton(
            label: complete ? 'Practise again' : 'Start session',
            onPressed: () => _openSession(session),
          ),
        ],
      ),
    );
  }

  Widget _sessionGrid(List<GrammarCourseSession> sessions) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: sessions.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1,
    ),
    itemBuilder: (context, index) {
      final session = sessions[index];
      return _GrammarSessionCard(
        key: ValueKey(session.id),
        session: session,
        selected: session.id == _selectedSessionId,
        complete: _isCompleted(session),
        onTap: () => setState(() => _selectedSessionId = session.id),
      );
    },
  );

  Widget _emptySessionCard({bool compact = false}) => Container(
    padding: EdgeInsets.all(compact ? 15 : 18),
    decoration: BoxDecoration(
      color: DesignTokens.surface,
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      border: Border.all(color: DesignTokens.hairline),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.auto_awesome_rounded, color: DesignTokens.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            widget.isPreparingSessions
                ? 'Preparing three connected ${_mode.label.toLowerCase()} sessions for $_tense…'
                : 'This focus is ready to be prepared. Your first session will contain four or five connected steps.',
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
          ),
        ),
      ],
    ),
  );

  Widget _statusCard(String message, {VoidCallback? action}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: DesignTokens.primarySoft,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: DesignTokens.body(13).copyWith(height: 1.35),
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 10),
          TextButton(onPressed: action, child: const Text('Retry')),
        ],
      ],
    ),
  );

  Widget _sessionIcon(GrammarCourseSession session, {bool large = false}) =>
      Container(
        width: large ? 54 : 42,
        height: large ? 54 : 42,
        decoration: BoxDecoration(
          color: DesignTokens.primarySoft,
          borderRadius: BorderRadius.circular(
            large ? DesignTokens.radiusCard : 13,
          ),
        ),
        child: Icon(
          session.icon,
          color: DesignTokens.primary,
          size: large ? 27 : 21,
        ),
      );

  Widget _sectionLabel(String value) => Text(
    value,
    style: DesignTokens.label(
      12,
      weight: FontWeight.w800,
    ).copyWith(color: DesignTokens.primary, letterSpacing: 1.15),
  );

  Widget _levelBadge({required String level}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: DesignTokens.primarySoft,
      borderRadius: BorderRadius.circular(100),
      border: Border.all(color: DesignTokens.primary),
    ),
    child: Text(level, style: DesignTokens.label(11, weight: FontWeight.w800)),
  );

  bool _isCompleted(GrammarCourseSession session) {
    final store = ref.read(learningStoreProvider);
    if (store.lessonStatus(session.progressId).status == 'completed') {
      return true;
    }
    return session.steps.asMap().keys.every(
      (index) =>
          store.lessonStatus('${session.progressId}_step_$index').status ==
          'completed',
    );
  }

  void _setMode(GrammarV2Mode mode) {
    setState(() {
      _mode = mode;
      _selectedSessionId = null;
    });
    final prepare = widget.onPrepareSessions;
    if (prepare != null) unawaited(prepare(mode, _tense));
  }

  void _setTense(String tense) {
    setState(() {
      _tense = tense;
      _selectedSessionId = null;
    });
    final prepare = widget.onPrepareSessions;
    if (prepare != null) unawaited(prepare(_mode, tense));
  }

  Future<void> _openSession(GrammarCourseSession session) async {
    final result = await AppRouter.push<GrammarCourseSessionResult>(
      context,
      (_) => GrammarV2LessonScreen(session: session),
      fullscreenDialog: true,
    );
    if (!mounted || result == null) return;
    setState(() {});
  }
}

class _GrammarSessionCard extends StatelessWidget {
  const _GrammarSessionCard({
    super.key,
    required this.session,
    required this.selected,
    required this.complete,
    required this.onTap,
  });

  final GrammarCourseSession session;
  final bool selected;
  final bool complete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${session.title}, ${session.steps.length} step Grammar session',
    child: Material(
      color: selected ? DesignTokens.primarySoft : DesignTokens.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 11, 9, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? DesignTokens.primary : DesignTokens.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 31,
                    height: 31,
                    decoration: BoxDecoration(
                      color: selected
                          ? DesignTokens.primary
                          : DesignTokens.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      session.icon,
                      size: 17,
                      color: selected
                          ? DesignTokens.onPrimary
                          : DesignTokens.primary,
                    ),
                  ),
                  const Spacer(),
                  if (complete)
                    Icon(
                      Icons.check_circle_rounded,
                      color: DesignTokens.success,
                      size: 18,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                session.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.body(13, weight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${session.steps.length} connected steps',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.body(
                  10,
                ).copyWith(color: DesignTokens.muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
