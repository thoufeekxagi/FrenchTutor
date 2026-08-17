import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../design/tokens.dart';
import '../../design/app_router.dart';
import '../../providers/database_provider.dart';
import '../../models/tutor_persona.dart';
import '../../services/ai_session_gate.dart';
import '../../services/daily_goal_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/passeport_primary_button.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/grammar_lab_screen.dart';
import '../labs/roleplay_lab_screen.dart';
import '../labs/writing_lab_screen.dart';
import '../pathway/vocab_picker_screen.dart';
import '../session/session_screen.dart';
import '../subscription/speak_paywall_screen.dart';

/// "Today's mission" — not a generated multi-step lesson plan anymore, just
/// a plain daily accountability check: touch each of [DailyGoalService.categories]
/// once today. Backed entirely by the `sessions` table every practice
/// screen writes to via `SessionRecorder`, so it advances the same whether
/// a category was done through this card's own button or by going straight
/// into Practice/Labs — there's no separate plan/task state to fall out of
/// sync with what was actually practiced.
class TodayMissionWidget extends ConsumerStatefulWidget {
  const TodayMissionWidget({super.key, this.onProgress, this.isActive = true});

  final VoidCallback? onProgress;

  /// True while the Home tab is the visible one — see `DashboardScreen.isActive`
  /// for why this exists: without it, completing a category from a different
  /// tab (e.g. Practice) never refreshed this card's `_doneToday`/`_streak`
  /// until the app fully restarted, since `IndexedStack` keeps this widget
  /// alive and its `initState` only ever runs once.
  final bool isActive;

  @override
  ConsumerState<TodayMissionWidget> createState() => _TodayMissionWidgetState();
}

class _TodayMissionWidgetState extends ConsumerState<TodayMissionWidget> {
  bool _loading = true;
  bool _running = false;
  // Fatal — reading today's sessions itself failed, nothing to show but a
  // retry. Distinct from [_actionError], which is a non-fatal inline notice
  // (e.g. opening a category failed) shown alongside an otherwise-working card.
  String? _loadError;
  String? _actionError;
  Set<String> _doneToday = {};
  List<String> _missionOrder = DailyGoalService.categories;
  bool _hasHistory = false;
  int _streak = 0;
  // "Skip for today" just previews a different not-yet-done category for
  // this visit — it never marks anything done, so it can't be used to fake
  // the accountability check. Resets whenever _doneToday changes.
  int _previewOffset = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TodayMissionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _load();
  }

  void _load() {
    if (mounted) setState(() => _loading = true);
    try {
      final sessions = ref.read(storageServiceProvider).getAllSessions();
      final done = DailyGoalService.categoriesToday(sessions);
      final profile = ref.read(learningStoreProvider).profile();
      if (!mounted) return;
      setState(() {
        _doneToday = done;
        _hasHistory = sessions.isNotEmpty;
        _missionOrder = DailyGoalService.missionOrderFor(
          profile,
          hasHistory: sessions.isNotEmpty,
        );
        _streak = DailyGoalService.streak(sessions);
        _previewOffset = 0;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('TodayMissionWidget: failed to load today\'s progress: $e');
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load today\'s progress. Please try again.';
        _loading = false;
      });
    }
  }

  List<String> get _remainingCategories =>
      _missionOrder.where((c) => !_doneToday.contains(c)).toList();

  String? get _featuredCategory {
    final remaining = _remainingCategories;
    if (remaining.isEmpty) return null;
    return remaining[_previewOffset % remaining.length];
  }

  void _skipForNow() {
    final remaining = _remainingCategories;
    if (remaining.length <= 1) return;
    setState(() => _previewOffset = (_previewOffset + 1) % remaining.length);
  }

  String? _labLockKeyFor(String category) => switch (category) {
    'Vocabulary' => 'vocabulary',
    'Grammar' => 'grammar',
    'Listening' => 'listening',
    'Roleplay' => 'roleplay',
    'Writing' => 'writing',
    _ => null, // Speaking (Talk with Marie) is ungated, matching the dashboard.
  };

  /// Whether tapping into today's featured category will show the paywall
  /// first — surfaced as a lock badge so that's never a surprise, matching
  /// the Practice tab and Keep Practising. Called from build(), so this must
  /// watch (not read) the gate — otherwise this badge keeps showing
  /// whatever was true when the widget first built, even after a purchase.
  bool _isLocked(String category) {
    final lockKey = _labLockKeyFor(category);
    return lockKey != null &&
        ref.watch(subscriptionGateServiceProvider).isLabLocked(lockKey);
  }

  Future<void> _openCategory(String category) async {
    final lockKey = _labLockKeyFor(category);
    if (lockKey != null &&
        ref.read(subscriptionGateServiceProvider).isLabLocked(lockKey)) {
      final subscribed = await AppRouter.push<bool>(
        context,
        (_) => const SpeakPaywallScreen(),
        fullscreenDialog: true,
      );
      if (subscribed != true || !mounted) return;
    }
    setState(() {
      _running = true;
      _actionError = null;
    });
    try {
      switch (category) {
        case 'Vocabulary':
          await AppRouter.push(context, (_) => const VocabPickerScreen());
        case 'Grammar':
          await AppRouter.push(context, (_) => const GrammarLabScreen());
        case 'Listening':
          await AppRouter.push(context, (_) => const ListeningLabScreen());
        case 'Roleplay':
          await AppRouter.push(context, (_) => const RoleplayLabScreen());
        case 'Writing':
          await AppRouter.push(context, (_) => const WritingLabScreen());
        case 'Speaking':
          if (!await ensureAiSessionQuota(
                context,
                ref.read(pilotAccessServiceProvider),
              ) ||
              !mounted) {
            break;
          }
          LessonSpeechService.shared.deactivate();
          await AppRouter.push(
            context,
            // Missing `stage: 'speaking'` was the actual "mission completion
            // doesn't complete the mission" bug: SessionScreen persists
            // whatever `stage` it's given verbatim (defaulting to null when
            // omitted, same as the dashboard's stage-less free-talk call),
            // and DailyGoalService only counts a session toward a category
            // when its stage maps to one — a null stage silently never
            // counted, so Speaking could never reach 6/6 from this button.
            (_) => SessionScreen(apiKey: ApiKeys.geminiKey, stage: 'speaking'),
            fullscreenDialog: true,
          );
      }
      _load();
      widget.onProgress?.call();
    } catch (e) {
      debugPrint('TodayMissionWidget: could not open $category: $e');
      if (mounted) {
        setState(() => _actionError = 'Could not open that. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: PSProgressIndicator());
    }
    if (_loadError != null) {
      return _MissionNotice(message: _loadError!, onRetry: _load);
    }
    final featured = _featuredCategory;
    if (featured == null) {
      return _MissionComplete(streak: _streak);
    }
    final doneCount = _doneToday.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(DesignTokens.space5),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            border: Border.all(color: DesignTokens.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _hasHistory ? 'NEXT BEST SESSION' : 'YOUR FIRST SESSION',
                    style: DesignTokens.body(11, weight: FontWeight.w700)
                        .copyWith(
                          color: DesignTokens.mutedDim,
                          letterSpacing: 1.1,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '$doneCount of ${_missionOrder.length}',
                    style: DesignTokens.body(
                      12,
                      weight: FontWeight.w600,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.space4),
              _MissionProgress(
                categories: _missionOrder,
                doneToday: _doneToday,
                featured: featured,
              ),
              const SizedBox(height: DesignTokens.space5),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: DesignTokens.infoSoft,
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusMedium,
                          ),
                        ),
                        child: Icon(
                          _iconFor(featured),
                          color: DesignTokens.info,
                          size: 23,
                        ),
                      ),
                      if (_isLocked(featured))
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: DesignTokens.surface,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: DesignTokens.ink.withValues(
                                    alpha: 0.1,
                                  ),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                            child: Icon(
                              CupertinoIcons.lock_fill,
                              size: 10,
                              color: DesignTokens.mutedDim,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: DesignTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasHistory ? 'NEXT STEP' : 'START HERE',
                          style:
                              DesignTokens.body(
                                10.5,
                                weight: FontWeight.w700,
                              ).copyWith(
                                color: DesignTokens.primary,
                                letterSpacing: 0.9,
                              ),
                        ),
                        const SizedBox(height: DesignTokens.space1),
                        Text(featured, style: DesignTokens.display(22)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.space3),
              Text(
                _taskLabel(featured),
                style: DesignTokens.body(
                  15,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.inkSoft),
              ),
              const SizedBox(height: DesignTokens.space3),
              Wrap(
                spacing: DesignTokens.space2,
                runSpacing: DesignTokens.space2,
                children: [
                  _MissionMeta(label: '${_durationFor(featured)} min'),
                  _MissionMeta(label: _modeLabel(featured)),
                ],
              ),
              const SizedBox(height: DesignTokens.space2),
              Text(
                _reasonFor(featured, hasHistory: _hasHistory),
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
              ),
              if (_actionError != null) ...[
                const SizedBox(height: DesignTokens.space3),
                Text(
                  _actionError!,
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w600,
                  ).copyWith(color: DesignTokens.danger),
                ),
              ],
              const SizedBox(height: DesignTokens.space5),
              ModernPrimaryButton(
                label: _isLocked(featured)
                    ? 'Unlock to start'
                    : _hasHistory
                    ? 'Start session'
                    : 'Begin your first session',
                icon: _isLocked(featured)
                    ? CupertinoIcons.lock_fill
                    : CupertinoIcons.arrow_right,
                onPressed: _running ? null : () => _openCategory(featured),
                isLoading: _running,
                loadingLabel: 'Opening…',
              ),
              if (_remainingCategories.length > 1)
                Center(
                  child: SizedBox(
                    height: DesignTokens.minTapTarget,
                    child: TextButton(
                      onPressed: _running ? null : _skipForNow,
                      child: Text(
                        'Choose a different focus',
                        style: DesignTokens.body(
                          13,
                          weight: FontWeight.w500,
                        ).copyWith(color: DesignTokens.mutedDim),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  int _durationFor(String category) => switch (category) {
    'Vocabulary' => 8,
    'Grammar' => 12,
    'Listening' => 10,
    'Roleplay' => 15,
    'Writing' => 12,
    _ => 18,
  };

  String _modeLabel(String category) => switch (category) {
    'Vocabulary' => 'Active recall',
    'Grammar' => 'Build accuracy',
    'Listening' => 'Comprehension',
    'Roleplay' => 'Real conversation',
    'Writing' => 'Clear expression',
    _ => 'Speaking readiness',
  };

  String _reasonFor(String category, {required bool hasHistory}) {
    if (!hasHistory && category == 'Vocabulary') {
      return 'Start with a short recall block. It gives you useful words for every session that follows.';
    }
    return switch (category) {
      'Vocabulary' =>
        'A short recall block keeps useful words available when you speak.',
      'Grammar' =>
        'A focused rule review makes your next conversation more precise.',
      'Listening' =>
        'Listening first gives you the phrasing and rhythm to reuse later.',
      'Roleplay' =>
        'A realistic scene turns today’s language into a usable response.',
      'Writing' =>
        'Writing gives you time to build a clear sentence before speaking.',
      _ =>
        'A live speaking block turns today’s preparation into confident French.',
    };
  }

  IconData _iconFor(String category) => switch (category) {
    'Vocabulary' => CupertinoIcons.square_stack_3d_up,
    'Grammar' => CupertinoIcons.book,
    'Listening' => CupertinoIcons.headphones,
    'Roleplay' => CupertinoIcons.bubble_left_bubble_right,
    'Writing' => CupertinoIcons.pencil,
    _ => CupertinoIcons.waveform,
  };

  String _taskLabel(String category) => switch (category) {
    'Vocabulary' => 'Learn or review some words',
    'Grammar' => 'Practice a grammar point',
    'Listening' => 'Read or listen to a short story',
    'Roleplay' => 'Have a live roleplay conversation',
    'Writing' => 'Write a short passage',
    _ => 'Talk with ${ActiveTutor.current.displayName}',
  };
}

class _MissionMeta extends StatelessWidget {
  const _MissionMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.space3,
        vertical: DesignTokens.space2,
      ),
      decoration: BoxDecoration(
        color: DesignTokens.canvasDim,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
      ),
      child: Text(
        label,
        style: DesignTokens.label(11).copyWith(color: DesignTokens.mutedDim),
      ),
    );
  }
}

class _MissionProgress extends StatelessWidget {
  const _MissionProgress({
    required this.categories,
    required this.doneToday,
    required this.featured,
  });

  final List<String> categories;
  final Set<String> doneToday;
  final String featured;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < categories.length; index++) ...[
          if (index > 0)
            Expanded(
              child: Container(
                height: 3,
                color: doneToday.contains(categories[index - 1])
                    ? DesignTokens.success
                    : DesignTokens.canvasDim,
              ),
            ),
          _CategoryDot(
            done: doneToday.contains(categories[index]),
            isNext: categories[index] == featured,
          ),
        ],
      ],
    );
  }
}

class _CategoryDot extends StatelessWidget {
  const _CategoryDot({required this.done, required this.isNext});

  final bool done;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: done
            ? DesignTokens.success
            : isNext
            ? DesignTokens.primary
            : DesignTokens.canvasDim,
        shape: BoxShape.circle,
      ),
      child: done
          ? const Icon(CupertinoIcons.checkmark, color: Colors.white, size: 14)
          : null,
    );
  }
}

class _MissionComplete extends StatelessWidget {
  const _MissionComplete({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignTokens.space5),
      decoration: BoxDecoration(
        color: DesignTokens.successSoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            CupertinoIcons.checkmark_seal_fill,
            color: DesignTokens.success,
            size: 28,
          ),
          const SizedBox(height: DesignTokens.space3),
          Text('Today’s path is complete', style: DesignTokens.display(22)),
          const SizedBox(height: DesignTokens.space1),
          Text(
            'You practiced all 6 skills today.',
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
          ),
          if (streak > 0) ...[
            const SizedBox(height: DesignTokens.space3),
            Row(
              children: [
                const Icon(
                  CupertinoIcons.flame_fill,
                  size: 16,
                  color: DesignTokens.success,
                ),
                const SizedBox(width: DesignTokens.space2),
                Text(
                  streak == 1 ? '1-day streak' : '$streak-day streak',
                  style: DesignTokens.body(
                    13.5,
                    weight: FontWeight.w600,
                  ).copyWith(color: DesignTokens.success),
                ),
              ],
            ),
          ],
          const SizedBox(height: DesignTokens.space2),
          Text(
            'Want to keep going? Practice any skill in the Practice tab.',
            style: DesignTokens.body(
              13,
            ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MissionNotice extends StatelessWidget {
  const _MissionNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.space5),
      decoration: BoxDecoration(
        color: DesignTokens.infoSoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: DesignTokens.body(15).copyWith(height: 1.4)),
          const SizedBox(height: DesignTokens.space3),
          SizedBox(
            width: 160,
            child: ModernPrimaryButton(label: 'Try again', onPressed: onRetry),
          ),
        ],
      ),
    );
  }
}
