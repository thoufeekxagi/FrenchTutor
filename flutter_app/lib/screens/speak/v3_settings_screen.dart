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
import '../../services/auth_service.dart';
import '../../services/revenue_cat_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/tutor_helper_settings_panel.dart';
import '../../widgets/v3/v3_surface.dart';
import '../subscription/speak_paywall_screen.dart';

/// The canonical settings surface. Product choices are edited in modal
/// sheets, so account, learning, and device controls stay on one calm page.
class V3SettingsScreen extends ConsumerStatefulWidget {
  const V3SettingsScreen({super.key, this.onReplayPractice});

  final VoidCallback? onReplayPractice;

  @override
  ConsumerState<V3SettingsScreen> createState() => _V3SettingsScreenState();
}

class _V3SettingsScreenState extends ConsumerState<V3SettingsScreen> {
  var _reminders = true;
  var _wifiOnly = false;
  var _haptics = true;
  var _busy = false;
  var _tutor = ActiveTutor.current;

  Profile get _profile => ref.read(learningStoreProvider).profile();

  void _saveProfile(void Function(Profile profile) update) {
    final profile = _profile;
    update(profile);
    ref.read(learningStoreProvider).saveProfile(profile);
    setState(() {});
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

  Future<void> _pickGoal() async {
    final value = await showV3Picker<String>(
      context: context,
      title: 'Learning goal',
      selected: _profile.goal,
      options: const [
        V3PickerOption(
          value: 'tef_canada',
          label: 'TEF Canada',
          description: 'Build exam-ready French across all skills',
          icon: Icons.flag_rounded,
        ),
        V3PickerOption(
          value: 'everyday',
          label: 'Everyday French',
          description: 'Speak naturally in daily situations',
          icon: Icons.forum_rounded,
        ),
        V3PickerOption(
          value: 'unsure',
          label: 'Explore first',
          description: 'Let the course adapt as you learn',
          icon: Icons.auto_awesome_rounded,
        ),
      ],
    );
    if (value != null) _saveProfile((profile) => profile.goal = value);
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

  Future<void> _pickTutor() async {
    final value = await showV3Picker<TutorPersona>(
      context: context,
      title: 'Conversation tutor',
      selected: _tutor,
      options: [
        for (final tutor in TutorPersona.all)
          V3PickerOption(
            value: tutor,
            label: tutor.displayName,
            description: tutor.tagline,
            icon: tutor.isFemale ? Icons.face_3_outlined : Icons.face_outlined,
          ),
      ],
    );
    if (value == null) return;
    await ActiveTutor.set(value);
    if (mounted) setState(() => _tutor = value);
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
    final appearance = ref.watch(appearanceSettingsProvider);
    return V3Scaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
        children: [
          V3Header(
            title: 'Settings',
            subtitle: 'A few controls for your learning space',
            leading: const V3BackButton(),
          ),
          const SizedBox(height: 18),
          V3SectionLabel('Your learning'),
          const SizedBox(height: 9),
          V3Row(
            icon: Icons.flag_outlined,
            title: 'Level',
            subtitle: 'Every lesson and speaking prompt adapts to this level',
            value: LearnerLevel.displayLabel(profile.level),
            onTap: _pickLevel,
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.track_changes_rounded,
            title: 'Goal',
            subtitle: 'Shapes the next course block and practice mix',
            value: _goalLabel(profile.goal),
            onTap: _pickGoal,
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.timer_outlined,
            title: 'Session length',
            subtitle: 'Controls the size of each recommended practice',
            value: _lengthLabel(profile.sessionLength),
            onTap: _pickSessionLength,
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.record_voice_over_outlined,
            title: 'Tutor',
            subtitle: _tutor.tagline,
            value: _tutor.displayName,
            onTap: _pickTutor,
          ),
          const SizedBox(height: 20),
          V3SectionLabel('Tutor helper by practice area'),
          const SizedBox(height: 9),
          TutorHelperSettingsPanel(dark: appearance.darkMode),
          const SizedBox(height: 20),
          V3SectionLabel('Preferences'),
          const SizedBox(height: 9),
          _toggleRow(
            Icons.notifications_none_rounded,
            'Daily reminder',
            'Keep a small practice habit alive',
            _reminders,
            (value) => setState(() => _reminders = value),
          ),
          const SizedBox(height: 8),
          _toggleRow(
            Icons.wifi_rounded,
            'Wi-Fi downloads only',
            'Avoid using mobile data for saved lessons',
            _wifiOnly,
            (value) => setState(() => _wifiOnly = value),
          ),
          const SizedBox(height: 8),
          _toggleRow(
            Icons.vibration_rounded,
            'Haptics',
            'Use gentle touch feedback for key actions',
            _haptics,
            (value) => setState(() => _haptics = value),
          ),
          const SizedBox(height: 8),
          _toggleRow(
            Icons.dark_mode_outlined,
            'Dark mode',
            'Use black and gold across every practice area',
            appearance.darkMode,
            (value) => ref.read(appearanceSettingsProvider).setDarkMode(value),
          ),
          const SizedBox(height: 20),
          V3SectionLabel('Account & help'),
          const SizedBox(height: 9),
          V3Row(
            icon: Icons.workspace_premium_outlined,
            title: 'Membership',
            subtitle: 'Manage your plan and restore a purchase',
            onTap: _openMembership,
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.help_outline_rounded,
            title: 'Replay practice tour',
            subtitle: 'See the quick explanation of the Practice tab again',
            onTap: widget.onReplayPractice,
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.logout_rounded,
            title: 'Sign out',
            subtitle: 'Sign out on this device',
            accent: DesignTokens.danger,
            onTap: _signOut,
          ),
          const SizedBox(height: 8),
          V3Row(
            icon: Icons.delete_outline_rounded,
            title: _busy ? 'Deleting account…' : 'Delete account',
            subtitle: 'Permanently remove your account and learning data',
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

  String _goalLabel(String value) => switch (value) {
    'tef_canada' => 'TEF Canada',
    'everyday' => 'Everyday',
    _ => 'Explore',
  };

  String _lengthLabel(String value) => switch (value) {
    'quick' => '5 min',
    'deep' => '20 min',
    _ => '10 min',
  };
}
