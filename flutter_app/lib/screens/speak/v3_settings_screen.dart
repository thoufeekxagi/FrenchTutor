import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/account_deletion.dart';
import '../../data/database/local_data_reset.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../models/tutor_persona.dart';
import '../../providers/appearance_provider.dart';
import '../../providers/database_provider.dart';
import '../../services/app_appearance_settings.dart';
import '../../services/auth_service.dart';
import '../../services/notification_permission_service.dart';
import '../../services/notification_scheduler_service.dart';
import '../../services/revenue_cat_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/tutor_helper_settings_panel.dart';
import '../../widgets/v3/v3_surface.dart';
import '../../v3/tutors/v3_tutor_picker_sheet.dart';
import '../../v3/progress/v3_french_fingerprint_screen.dart';
import '../../v3/progress/v3_streak_calendar_screen.dart';
import '../subscription/speak_paywall_screen.dart';
import '../settings/privacy_ai_screen.dart';

/// The canonical settings surface. Product choices are edited in modal
/// sheets, so account, learning, and device controls stay on one calm page.
class V3SettingsScreen extends ConsumerStatefulWidget {
  const V3SettingsScreen({super.key, this.onReplayPractice});

  final VoidCallback? onReplayPractice;

  @override
  ConsumerState<V3SettingsScreen> createState() => _V3SettingsScreenState();
}

class _V3SettingsScreenState extends ConsumerState<V3SettingsScreen> {
  var _busy = false;
  var _tutor = ActiveTutor.current;

  Profile get _profile => ref.read(learningStoreProvider).profile();

  @override
  void initState() {
    super.initState();
    // The v3 product is dedicated to TCF Canada. Older profiles may still
    // carry one of the legacy general-purpose goals; normalize only the
    // shared course key used by the existing TCF/TEF curriculum engine.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profile = _profile;
      if (profile.goal != 'tef_canada') {
        profile.goal = 'tef_canada';
        ref.read(learningStoreProvider).saveProfile(profile);
      }
    });
  }

  void _saveProfile(void Function(Profile profile) update) {
    final profile = _profile;
    update(profile);
    ref.read(learningStoreProvider).saveProfile(profile);
    setState(() {});
  }

  Future<void> _pickTutor() async {
    final picked = await showV3TutorPickerSheet(
      context: context,
      selected: _tutor,
    );
    if (picked == null || !mounted) return;
    await ActiveTutor.set(picked);
    if (mounted) setState(() => _tutor = picked);
  }

  Future<void> _pickLevel() async {
    final value = await showV3Picker<String>(
      context: context,
      title: 'Current level',
      selected: _profile.level,
      options: const [
        V3PickerOption(value: 'a1', label: 'A1', description: 'Starting out'),
        V3PickerOption(
          value: 'a2',
          label: 'A2',
          description: 'Everyday basics',
        ),
        V3PickerOption(
          value: 'b1',
          label: 'B1',
          description: 'Independent speaker',
        ),
        V3PickerOption(
          value: 'b2',
          label: 'B2',
          description: 'Confident and nuanced',
        ),
      ],
    );
    if (value != null) _saveProfile((profile) => profile.level = value);
  }

  Future<void> _pickSessionLength() async {
    final value = await showV3Picker<String>(
      context: context,
      title: 'Session length',
      selected: _profile.sessionLength,
      options: const [
        V3PickerOption(
          value: 'quick',
          label: 'Quick',
          description: '5 minutes',
        ),
        V3PickerOption(
          value: 'standard',
          label: 'Standard',
          description: '10 minutes',
        ),
        V3PickerOption(value: 'deep', label: 'Deep', description: '20 minutes'),
      ],
    );
    if (value != null) {
      _saveProfile((profile) => profile.sessionLength = value);
    }
  }

  Future<void> _editReminder() async {
    final profile = _profile;
    final parts = (profile.reminderTime ?? '19:00').split(':');
    var time = TimeOfDay(
      hour: (int.tryParse(parts.first) ?? 19).clamp(0, 23),
      minute: (int.tryParse(parts.last) ?? 0).clamp(0, 59),
    );
    var enabled = profile.reminderTime != null;
    final days = <String>{
      ...profile.preferredDays.where(
        (day) => _studyDays.any((d) => d.$1 == day),
      ),
    };
    if (days.isEmpty) days.addAll(const ['mon', 'tue', 'wed', 'thu', 'fri']);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: BoxDecoration(
              color: DesignTokens.canvas,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: DesignTokens.hairline,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Study reminders',
                        style: DesignTokens.display(23),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Text('Remind me to practise')),
                    Switch.adaptive(
                      value: enabled,
                      activeTrackColor: DesignTokens.primary,
                      onChanged: (value) =>
                          setSheetState(() => enabled = value),
                    ),
                  ],
                ),
                if (enabled) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: sheetContext,
                        initialTime: time,
                      );
                      if (picked != null) {
                        setSheetState(() => time = picked);
                      }
                    },
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text('At ${time.format(context)}'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'On these days',
                    style: DesignTokens.body(13, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final day in _studyDays)
                        FilterChip(
                          label: Text(day.$2),
                          selected: days.contains(day.$1),
                          selectedColor: DesignTokens.primarySoft,
                          checkmarkColor: DesignTokens.primary,
                          onSelected: (selected) => setSheetState(() {
                            if (selected) {
                              days.add(day.$1);
                            } else {
                              days.remove(day.$1);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: enabled && days.isEmpty
                        ? null
                        : () => Navigator.of(sheetContext).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: DesignTokens.primary,
                      foregroundColor: DesignTokens.onPrimary,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || saved != true) return;

    final updated = _profile
      ..reminderTime = enabled
          ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
          : null
      ..preferredDays = [
        for (final day in _studyDays)
          if (days.contains(day.$1)) day.$1,
      ];
    if (enabled && updated.notificationPermissionState != 'granted') {
      updated.notificationPermissionState =
          await NotificationPermissionService.request();
    }
    ref.read(learningStoreProvider).saveProfile(updated);
    await NotificationSchedulerService.sync(updated);
    if (!mounted) return;
    setState(() {});
    if (enabled && updated.notificationPermissionState != 'granted') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder saved. Allow notifications to receive it.'),
        ),
      );
    }
  }

  Future<void> _openMembership() async {
    await AppRouter.push(
      context,
      (_) => const SpeakPaywallScreen(),
      fullscreenDialog: true,
    );
    unawaited(RevenueCatService.shared.refreshCustomerInfo());
  }

  Future<void> _signOut() async {
    final confirmed = await showPSConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'Your account stays safe and can be opened again anytime.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await AuthService.shared.signOut();
    wipeLocalUserData(ref.read(databaseProvider));
    await clearLocalPreferences();
    await AuthService.shared.rememberSignedOut();
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showPSConfirmDialog(
      context,
      title: 'Delete account?',
      message: 'This permanently removes your account and learning data.',
      confirmLabel: 'Delete account',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final database = ref.read(databaseProvider);
    final result = await AuthService.shared.deleteAccount();
    if (result.outcome == AuthOutcome.success) {
      await AuthService.shared.signOutLocallyImmediately();
      wipeLocalDatabase(database);
      await clearLocalPreferences();
      await AuthService.shared.rememberSignedOut();
      return;
    }
    if (mounted) {
      setState(() => _busy = false);
      await showPSConfirmDialog(
        context,
        title: 'Could not delete account',
        message: result.message ?? 'Please try again.',
        confirmLabel: 'OK',
        cancelLabel: 'Close',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return V3Scaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
        children: [
          V3Header(
            title: 'Settings',
            leading: const V3BackButton(key: ValueKey('settings.back')),
          ),
          const SizedBox(height: 18),
          V3SectionLabel('TCF Canada'),
          const SizedBox(height: 9),
          V3Row(
            icon: Icons.flag_outlined,
            title: 'Level',
            value: LearnerLevel.displayLabel(profile.level),
            onTap: _pickLevel,
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.track_changes_rounded,
            title: 'Course',
            value: 'TCF Canada',
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.timer_outlined,
            title: 'Session length',
            value: _lengthLabel(profile.sessionLength),
            onTap: _pickSessionLength,
          ),
          const SizedBox(height: 8),
          V3Row(
            key: const ValueKey('settings.tutor'),
            icon: Icons.record_voice_over_outlined,
            title: 'Tutor',
            value: _tutor.displayName,
            onTap: _pickTutor,
          ),
          const SizedBox(height: 20),
          V3SectionLabel('Preferences'),
          const SizedBox(height: 9),
          Semantics(
            container: true,
            label: 'Dark mode',
            toggled: ref.watch(appearanceSettingsProvider).darkMode,
            child: KeyedSubtree(
              key: const ValueKey('settings.darkMode'),
              child: _toggleRow(
                Icons.dark_mode_outlined,
                'Dark mode',
                'Use a darker appearance',
                ref.watch(appearanceSettingsProvider).darkMode,
                (value) => AppAppearanceSettings.shared.setDarkMode(value),
              ),
            ),
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.notifications_none_rounded,
            title: 'Study reminder',
            value: _reminderLabel(profile),
            onTap: _editReminder,
          ),
          const SizedBox(height: 20),
          V3SectionLabel('Your progress'),
          const SizedBox(height: 9),
          V3Row(
            key: const ValueKey('settings.streak'),
            icon: Icons.local_fire_department_outlined,
            title: 'Streak calendar',
            subtitle: 'Your weekly rhythm and recent practice',
            onTap: () =>
                AppRouter.push(context, (_) => const V3StreakCalendarScreen()),
          ),
          const SizedBox(height: 8),
          V3Row(
            key: const ValueKey('settings.fingerprint'),
            icon: Icons.hub_outlined,
            title: 'French fingerprint',
            subtitle: 'Explore words shaped by your practice',
            onTap: () => AppRouter.push(
              context,
              (_) => const V3FrenchFingerprintScreen(),
            ),
          ),
          const SizedBox(height: 20),
          V3SectionLabel('Tutor'),
          const SizedBox(height: 9),
          V3Card(
            padding: EdgeInsets.zero,
            child: Material(
              color: DesignTokens.surface,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: Icon(
                    Icons.tune_rounded,
                    color: DesignTokens.primary,
                  ),
                  title: Text(
                    'Tutor helper',
                    style: DesignTokens.body(15, weight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Choose where ${_tutor.displayName} can offer help',
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: DesignTokens.muted),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  children: const [TutorHelperSettingsPanel()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          V3SectionLabel('Account & help'),
          const SizedBox(height: 9),
          V3Row(
            icon: Icons.workspace_premium_outlined,
            title: 'Membership',
            onTap: _openMembership,
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy & AI',
            onTap: () =>
                AppRouter.push(context, (_) => const PrivacyAiScreen()),
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.logout_rounded,
            title: 'Sign out',
            accent: DesignTokens.danger,
            onTap: _signOut,
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.delete_outline_rounded,
            title: _busy ? 'Deleting account…' : 'Delete account',
            accent: DesignTokens.danger,
            onTap: _busy ? null : _deleteAccount,
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(
    IconData icon,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return V3Card(
      padding: const EdgeInsets.fromLTRB(14, 8, 7, 8),
      child: Row(
        children: [
          Icon(icon, color: DesignTokens.nightAccent, size: 23),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(
                    15,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.nightText),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
            ),
          ),
          V3Toggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  String _lengthLabel(String value) => switch (value) {
    'quick' => '5 min',
    'deep' => '20 min',
    _ => '10 min',
  };

  String _reminderLabel(Profile profile) {
    final value = profile.reminderTime;
    if (value == null) return 'Off';
    final parts = value.split(':');
    final time = TimeOfDay(
      hour: (int.tryParse(parts.first) ?? 19).clamp(0, 23),
      minute: (int.tryParse(parts.last) ?? 0).clamp(0, 59),
    ).format(context);
    final weekdays = const ['mon', 'tue', 'wed', 'thu', 'fri'];
    final days = profile.preferredDays.toSet();
    final label = days.containsAll(weekdays) && days.length == weekdays.length
        ? 'Weekdays'
        : '${days.length} ${days.length == 1 ? 'day' : 'days'}';
    return '$label · $time';
  }

  static const _studyDays = [
    ('mon', 'M'),
    ('tue', 'T'),
    ('wed', 'W'),
    ('thu', 'T'),
    ('fri', 'F'),
    ('sat', 'S'),
    ('sun', 'S'),
  ];
}
