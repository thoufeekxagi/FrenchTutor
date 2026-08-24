import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../models/speak_curriculum.dart';
import '../../providers/database_provider.dart';
import '../../services/adaptive_curriculum_service.dart';
import '../../services/daily_summary_service.dart';
import '../../services/notification_permission_service.dart';
import '../../services/notification_scheduler_service.dart';
import 'speak_ui.dart';

/// The deep learning controls live inside the same visual system as the
/// primary app. Keeping them separate from the compact settings landing page
/// mirrors Speak's focused, drill-down settings flow.
class SpeakAdvancedSettingsScreen extends ConsumerStatefulWidget {
  const SpeakAdvancedSettingsScreen({super.key});

  @override
  ConsumerState<SpeakAdvancedSettingsScreen> createState() =>
      _SpeakAdvancedSettingsScreenState();
}

class _SpeakAdvancedSettingsScreenState
    extends ConsumerState<SpeakAdvancedSettingsScreen> {
  var _voiceRecognition = true;
  var _autoMode = true;
  var _speaking = true;
  var _roleplay = true;
  var _stories = false;
  var _listening = true;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learningStoreProvider).profile();
    final level = _normaliseLevel(profile.level);
    final minutes = switch (profile.sessionLength) {
      'quick' => 5,
      'deep' => 20,
      _ => 10,
    };
    final selectedFocus = AdaptiveCurriculumService.focusSkills(profile);
    final selectedGoal = _normaliseGoal(profile.goal);
    final remindersEnabled = profile.reminderTime != null;

    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          SpeakHeader(
            title: 'Learning controls',
            subtitle: 'Shape the way your course feels.',
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(Icons.arrow_back_rounded, color: SpeakColors.inkSoft),
            ),
          ),
          const SizedBox(height: 26),
          _sectionLabel('Learning goal'),
          const SizedBox(height: 9),
          SpeakCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Change the problem your next lessons solve. Completed lessons stay unchanged; future sessions follow this goal.',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in _goalOptions)
                      SpeakPill(
                        label: option.$2,
                        selected: option.$1 == selectedGoal,
                        onTap: () => _saveGoal(option.$1),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _sectionLabel('Course focus'),
          const SizedBox(height: 9),
          SpeakCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All six skills remain available. These choices decide which skills receive the strongest weighting in the next generated sessions.',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final skill
                        in AdaptiveCurriculumService.coreFocusSkills)
                      SpeakPill(
                        label: skill.label,
                        selected: selectedFocus.contains(skill),
                        onTap: () => _toggleFocus(skill, selectedFocus),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _saveAllFocus,
                  icon: const Icon(Icons.done_all_rounded, size: 17),
                  label: const Text('Use all six equally'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _sectionLabel('Course level'),
          const SizedBox(height: 9),
          SpeakCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The path uses this to choose the difficulty of every next session.',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in LearnerLevel.cefrValues)
                      SpeakPill(
                        label: option.toUpperCase(),
                        selected: option == level,
                        onTap: () => _saveLevel(option),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _sectionLabel('Daily practice'),
          const SizedBox(height: 9),
          SpeakCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A shorter promise is better than a plan you stop using.',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in [5, 10, 15, 20])
                      SpeakPill(
                        label: '$option min',
                        selected: option == minutes,
                        onTap: () => _saveMinutes(option),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _sectionLabel('Study schedule'),
          const SizedBox(height: 9),
          SpeakCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Keep the plan matched to the time you actually have.',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final day in _studyDays)
                      SpeakPill(
                        label: day.$2,
                        selected: profile.preferredDays.contains(day.$1),
                        onTap: () => _toggleStudyDay(day.$1, profile),
                      ),
                  ],
                ),
                Divider(height: 26, color: SpeakColors.line),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily reminder',
                            style: DesignTokens.body(
                              14,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            remindersEnabled
                                ? '${profile.reminderTime} · ${profile.timeZone ?? 'Local time'}'
                                : 'Reminders are off',
                            style: DesignTokens.body(
                              11.5,
                            ).copyWith(color: SpeakColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: remindersEnabled,
                      onChanged: _toggleReminders,
                      activeThumbColor: SpeakColors.accent,
                    ),
                  ],
                ),
                if (remindersEnabled) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _editReminderTime,
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text('Change time · ${profile.reminderTime}'),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _requestNotifications,
                  icon: Icon(
                    profile.notificationPermissionState == 'granted'
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    size: 18,
                  ),
                  label: Text(
                    profile.notificationPermissionState == 'granted'
                        ? 'Notifications enabled'
                        : 'Enable notifications',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _sectionLabel('Practice modes'),
          const SizedBox(height: 9),
          SpeakCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _toggle(
                  'Speaking',
                  'Say the useful line out loud',
                  _speaking,
                  (value) => setState(() => _speaking = value),
                ),
                Divider(height: 1, color: SpeakColors.line),
                _toggle(
                  'Roleplay',
                  'Use it in a real situation',
                  _roleplay,
                  (value) => setState(() => _roleplay = value),
                ),
                Divider(height: 1, color: SpeakColors.line),
                _toggle(
                  'Stories',
                  'Meet the phrase in context',
                  _stories,
                  (value) => setState(() => _stories = value),
                ),
                Divider(height: 1, color: SpeakColors.line),
                _toggle(
                  'Listening',
                  'Train your ear before speaking',
                  _listening,
                  (value) => setState(() => _listening = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _sectionLabel('Session behavior'),
          const SizedBox(height: 9),
          SpeakCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _toggle(
                  'Voice recognition',
                  'Let the tutor listen for pronunciation feedback',
                  _voiceRecognition,
                  (value) => setState(() => _voiceRecognition = value),
                ),
                Divider(height: 1, color: SpeakColors.line),
                _toggle(
                  'Auto mode',
                  'Keep the conversation moving naturally',
                  _autoMode,
                  (value) => setState(() => _autoMode = value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _normaliseLevel(String value) {
    return LearnerLevel.cefrValues.contains(value) ? value : 'a1';
  }

  String _normaliseGoal(String value) {
    return _goalOptions.any((option) => option.$1 == value)
        ? value
        : 'everyday';
  }

  static const _goalOptions = [
    ('everyday', 'Everyday'),
    ('tef_canada', 'TEF / TCF'),
    ('work', 'Professional'),
    ('relocation', 'Relocation'),
    ('travel', 'Travel'),
    ('culture', 'Culture'),
  ];

  static const _studyDays = [
    ('mon', 'Mon'),
    ('tue', 'Tue'),
    ('wed', 'Wed'),
    ('thu', 'Thu'),
    ('fri', 'Fri'),
    ('sat', 'Sat'),
    ('sun', 'Sun'),
  ];

  void _saveProfile(void Function(Profile) mutate) {
    final store = ref.read(learningStoreProvider);
    final profile = store.profile();
    mutate(profile);
    store.saveProfile(profile);
    unawaited(
      NotificationSchedulerService.sync(
        profile,
        summary: DailySummaryService(store: store).compute(),
      ),
    );
    // This immediately versions the adaptive route. Completed sessions are
    // retained by the store; only future sessions are regenerated.
    ref.read(adaptiveCourseStoreProvider).ensureCurrentPlan(profile);
    if (mounted) setState(() {});
  }

  void _saveGoal(String value) {
    _saveProfile((profile) => profile.goal = value);
  }

  void _toggleFocus(SpeakSkill skill, List<SpeakSkill> selected) {
    final next = selected.toList();
    if (next.contains(skill)) {
      if (next.length == 1) return;
      next.remove(skill);
    } else {
      next.add(skill);
    }
    _saveProfile(
      (profile) => profile.interests = next.map((item) => item.label).toList(),
    );
  }

  void _saveAllFocus() {
    _saveProfile(
      (profile) => profile.interests = AdaptiveCurriculumService.coreFocusSkills
          .map((skill) => skill.label)
          .toList(),
    );
  }

  void _toggleStudyDay(String day, Profile current) {
    final days = current.preferredDays.toList();
    if (days.contains(day)) {
      if (days.length == 1) return;
      days.remove(day);
    } else {
      days.add(day);
    }
    _saveProfile((profile) => profile.preferredDays = days);
  }

  void _toggleReminders(bool enabled) {
    _saveProfile(
      (profile) => profile.reminderTime = enabled
          ? (profile.reminderTime ?? '19:00')
          : null,
    );
  }

  Future<void> _requestNotifications() async {
    final state = await NotificationPermissionService.request();
    if (!mounted) return;
    _saveProfile((profile) => profile.notificationPermissionState = state);
  }

  Future<void> _editReminderTime() async {
    final parts = (_profileReminderTime()).split(':');
    final initialHour = int.tryParse(parts.first)?.clamp(0, 23) ?? 19;
    final initialMinute = int.tryParse(parts.last)?.clamp(0, 59) ?? 0;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var hour = initialHour;
        var minute = initialMinute;
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Choose your French reminder time',
                          style: DesignTokens.display(18),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _timeWheel(
                          label: 'Hour',
                          value: hour,
                          count: 24,
                          onChanged: (value) =>
                              setSheetState(() => hour = value),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(':', style: DesignTokens.display(27)),
                      ),
                      Expanded(
                        child: _timeWheel(
                          label: 'Minute',
                          value: minute,
                          count: 60,
                          onChanged: (value) =>
                              setSheetState(() => minute = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(
                        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                      ),
                      child: const Text('Save reminder time'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted || picked == null) return;
    _saveProfile((profile) => profile.reminderTime = picked);
  }

  String _profileReminderTime() {
    final value = ref.read(learningStoreProvider).profile().reminderTime;
    return value ?? '19:00';
  }

  Widget _timeWheel({
    required String label,
    required int value,
    required int count,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: DesignTokens.body(
            11,
            weight: FontWeight.w700,
          ).copyWith(color: SpeakColors.inkSoft),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 138,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: SpeakColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SpeakColors.line),
            ),
            child: ListWheelScrollView.useDelegate(
              controller: FixedExtentScrollController(initialItem: value),
              itemExtent: 42,
              diameterRatio: 1.35,
              perspective: 0.003,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: onChanged,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: count,
                builder: (context, index) => Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: DesignTokens.display(index == value ? 25 : 19)
                        .copyWith(
                          color: index == value
                              ? SpeakColors.accent
                              : SpeakColors.inkSoft.withValues(alpha: .58),
                          fontWeight: index == value
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _saveLevel(String value) {
    _saveProfile((profile) => profile.level = value);
  }

  void _saveMinutes(int value) {
    _saveProfile(
      (profile) => profile.sessionLength = switch (value) {
        5 => 'quick',
        20 => 'deep',
        _ => 'standard',
      },
    );
  }

  Widget _sectionLabel(String label) => Text(
    label.toUpperCase(),
    style: DesignTokens.label(
      10,
    ).copyWith(color: SpeakColors.inkSoft, letterSpacing: 1),
  );

  Widget _toggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: DesignTokens.body(
                    11.5,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: SpeakColors.accent,
          ),
        ],
      ),
    );
  }
}
