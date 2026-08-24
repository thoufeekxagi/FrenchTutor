import 'dart:async';
import 'dart:io' show Platform;

import '../../widgets/adaptive/adaptive.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../data/database/account_deletion.dart';
import '../../data/database/local_data_reset.dart';
import '../../design/app_router.dart';
import '../../models/pilot_access.dart';
import '../../models/profile.dart';
import '../../models/speak_curriculum.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../services/app_tour.dart';
import '../../services/auth_service.dart';
import '../../services/adaptive_curriculum_service.dart';
import '../../services/srs_service.dart';
import '../../services/subscription_gate_service.dart';
import '../../services/notification_scheduler_service.dart';
import '../../services/tutor_voice_preview.dart';
import '../subscription/speak_paywall_screen.dart';
import 'orchestration_lab_screen.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/tutor_helper_settings_panel.dart';
import '../../widgets/web/web_constrained_view.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  double _narrationRate = 0.42;
  int _newCardsPerDay = 20;
  int _autoQueueSize = 5;
  int _practicePasses = 5;
  DateTime _roadmapStartDate = DateTime.now();
  TutorPersona _persona = ActiveTutor.current;
  String _languageMix = 'balanced';
  String _voiceSpeed = 'natural';
  bool _deletingAccount = false;
  late final TutorVoicePreviewer _previewer = TutorVoicePreviewer()
    ..addListener(() {
      if (mounted) setState(() {});
    });
  late Profile _profile;
  late PilotAccessSnapshot _access;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _profile = ref.read(learningStoreProvider).profile();
    _access = ref.read(pilotAccessServiceProvider).snapshot();
    _loadSettings();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _appVersion = '${info.version} (${info.buildNumber})');
  }

  @override
  void dispose() {
    _previewer.dispose();
    super.dispose();
  }

  void _saveProfile(void Function(Profile) mutate) {
    setState(() => mutate(_profile));
    ref.read(learningStoreProvider).saveProfile(_profile);
    // Keep the OS schedule synchronized when reminder settings are changed
    // from the legacy Settings surface as well as Learning controls.
    unawaited(NotificationSchedulerService.sync(_profile));
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _narrationRate = prefs.getDouble('lesson_narration_rate') ?? 0.42;
      _newCardsPerDay = prefs.getInt('srs_new_cards_per_day') ?? 20;
      _practicePasses = (prefs.getInt('practice_passes_per_word') ?? 5).clamp(
        2,
        10,
      );
      final timestamp = prefs.getInt('roadmap_start_date');
      if (timestamp != null) {
        _roadmapStartDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    });
    final queueSize = await SRSService.autoQueueSize;
    if (!mounted) return;
    setState(() => _autoQueueSize = queueSize);
    final mix = await TutorTuning.languageMix();
    final speed = await TutorTuning.voiceSpeed();
    if (!mounted) return;
    setState(() {
      _persona = ActiveTutor.current;
      _languageMix = mix;
      _voiceSpeed = speed;
    });
  }

  Future<void> _saveDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  Future<void> _saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _pickRoadmapStartDate() async {
    final picked = await showPSDatePicker(
      context,
      initial: _roadmapStartDate,
      first: DateTime(2024),
      last: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _roadmapStartDate = picked);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('roadmap_start_date', picked.millisecondsSinceEpoch);
    }
  }

  /// 2×2 persona picker: one row per accent, one card per tutor.
  Widget _personaGrid() {
    Widget card(TutorPersona p) {
      final selected = _persona.id == p.id;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() => _persona = p);
            ActiveTutor.set(p);
          },
          child: AnimatedContainer(
            duration: DesignTokens.durationFast,
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected
                  ? DesignTokens.primarySoft
                  : DesignTokens.canvasDim,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? Colors.transparent : DesignTokens.hairline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.displayName,
                        style: DesignTokens.body(14, weight: FontWeight.w700)
                            .copyWith(
                              color: selected
                                  ? DesignTokens.primaryDeep
                                  : DesignTokens.ink,
                            ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _previewer.play(p),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _previewer.loadingId == p.id
                            ? SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: DesignTokens.info,
                                ),
                              )
                            : Icon(
                                _previewer.playingId == p.id
                                    ? CupertinoIcons.stop_circle_fill
                                    : CupertinoIcons.play_circle_fill,
                                color: selected
                                    ? DesignTokens.secondary
                                    : DesignTokens.info,
                                size: 19,
                              ),
                      ),
                    ),
                    if (selected)
                      Icon(
                        CupertinoIcons.checkmark_circle_fill,
                        color: DesignTokens.primary,
                        size: 17,
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${p.accent.label} French',
                  style: DesignTokens.body(10.5, weight: FontWeight.w700)
                      .copyWith(
                        color: selected
                            ? DesignTokens.primaryDeep
                            : DesignTokens.primary,
                        letterSpacing: 0.4,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  p.tagline,
                  style: DesignTokens.body(
                    10.5,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget row(TutorAccent accent) {
      final pair = TutorPersona.byAccent(accent);
      return Row(
        children: [card(pair[0]), const SizedBox(width: 10), card(pair[1])],
      );
    }

    return Column(
      children: [
        row(TutorAccent.france),
        const SizedBox(height: 10),
        row(TutorAccent.quebec),
      ],
    );
  }

  /// Level drives every AI generation call in the app (grammar, writing,
  /// story, reading, listening, and the live-call persona calibration) —
  /// every one of those reads `profile().level` fresh at generation time,
  /// so changing it here is enough to change all of them from the very next
  /// session onward, nothing else needs updating. The confirmation exists so
  /// a stray tap can't silently reset calibration mid-plan — this is a
  /// deliberate "I've improved" or "this was too hard" decision, not a
  /// cosmetic preference like language mix or voice speed.
  Future<void> _confirmLevelChange(String newLevel) async {
    if (newLevel == _profile.level) return;
    final confirmed = await showPSConfirmDialog(
      context,
      title: 'Change your level to ${LearnerLevel.displayLabel(newLevel)}?',
      message:
          'This changes how everything is calibrated for you from now on: '
          'grammar, writing, stories, reading, listening, and your live '
          'sessions with your tutor will all match ${LearnerLevel.displayLabel(newLevel)} '
          "going forward. It won't change anything you've already done.",
      confirmLabel: 'Change to ${LearnerLevel.displayLabel(newLevel)}',
    );
    if (!confirmed || !mounted) return;
    _saveProfile((p) => p.level = newLevel);
  }

  Widget _courseFocusEditor() {
    final selected = AdaptiveCurriculumService.focusSkills(_profile);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KickerText('Course focus', color: DesignTokens.mutedDim),
        const SizedBox(height: 5),
        Text(
          'Every course uses the complete learning loop. These choices shape the lessons you see most often.',
          style: DesignTokens.body(11).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final skill in AdaptiveCurriculumService.coreFocusSkills)
              FilterChip(
                label: Text(skill.label),
                selected: selected.contains(skill),
                onSelected: (value) => _toggleCourseFocus(skill, value),
                selectedColor: DesignTokens.primarySoft,
                checkmarkColor: DesignTokens.primary,
                labelStyle: DesignTokens.body(
                  12,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.ink),
                side: BorderSide(color: DesignTokens.hairline),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _saveProfile(
            (profile) => profile.interests = AdaptiveCurriculumService
                .coreFocusSkills
                .map((skill) => skill.label)
                .toList(),
          ),
          icon: const Icon(CupertinoIcons.checkmark_alt_circle, size: 17),
          label: const Text('Use all six equally'),
        ),
      ],
    );
  }

  void _toggleCourseFocus(SpeakSkill skill, bool selected) {
    final current = AdaptiveCurriculumService.focusSkills(_profile).toList();
    if (selected) {
      if (!current.contains(skill)) current.add(skill);
    } else {
      // Keep one declared emphasis so the generated route never becomes
      // ambiguous. Other skills still remain available as supporting work.
      if (current.length == 1) return;
      current.remove(skill);
    }
    _saveProfile(
      (profile) =>
          profile.interests = current.map((focus) => focus.label).toList(),
    );
  }

  Widget _scheduleEditor() {
    const days = [
      ('mon', 'M'),
      ('tue', 'T'),
      ('wed', 'W'),
      ('thu', 'T'),
      ('fri', 'F'),
      ('sat', 'S'),
      ('sun', 'S'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KickerText('Study schedule', color: DesignTokens.mutedDim),
        const SizedBox(height: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _editReminderTime,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Text(
                  'Reminder time',
                  style: DesignTokens.body(
                    12.5,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
                const Spacer(),
                Text(
                  _profile.reminderTime ?? 'Not set',
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.primary),
                ),
                const SizedBox(width: 5),
                Icon(
                  CupertinoIcons.chevron_forward,
                  size: 14,
                  color: DesignTokens.primary,
                ),
              ],
            ),
          ),
        ),
        Divider(height: 18, color: DesignTokens.hairline),
        Text(
          'Study days',
          style: DesignTokens.body(12.5).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final day in days)
              FilterChip(
                label: Text(day.$2),
                selected: _profile.preferredDays.contains(day.$1),
                onSelected: (selected) => _togglePreferredDay(day.$1, selected),
                selectedColor: DesignTokens.primarySoft,
                checkmarkColor: DesignTokens.primary,
                labelStyle: DesignTokens.body(
                  12,
                  weight: FontWeight.w700,
                ).copyWith(color: DesignTokens.ink),
                side: BorderSide(color: DesignTokens.hairline),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _editReminderTime() async {
    final parts = (_profile.reminderTime ?? '19:00').split(':');
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
              decoration: BoxDecoration(
                color: DesignTokens.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
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
                        icon: const Icon(CupertinoIcons.xmark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _settingsReminderWheel(
                          label: 'Hour',
                          initialValue: hour,
                          itemCount: 24,
                          onChanged: (value) =>
                              setSheetState(() => hour = value),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(':', style: DesignTokens.display(27)),
                      ),
                      Expanded(
                        child: _settingsReminderWheel(
                          label: 'Minute',
                          initialValue: minute,
                          itemCount: 60,
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

  Widget _settingsReminderWheel({
    required String label,
    required int initialValue,
    required int itemCount,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: DesignTokens.body(
            11,
            weight: FontWeight.w700,
          ).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 138,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DesignTokens.canvas,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DesignTokens.hairline),
            ),
            child: ListWheelScrollView.useDelegate(
              controller: FixedExtentScrollController(
                initialItem: initialValue,
              ),
              itemExtent: 42,
              diameterRatio: 1.35,
              perspective: 0.003,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: onChanged,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: itemCount,
                builder: (context, index) => Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: DesignTokens.display(index == initialValue ? 25 : 19)
                        .copyWith(
                          color: index == initialValue
                              ? DesignTokens.primary
                              : DesignTokens.mutedDim.withValues(alpha: .58),
                          fontWeight: index == initialValue
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

  void _togglePreferredDay(String day, bool selected) {
    final days = _profile.preferredDays.toList();
    if (selected) {
      if (!days.contains(day)) days.add(day);
    } else {
      if (days.length == 1) return;
      days.remove(day);
    }
    _saveProfile((profile) => profile.preferredDays = days);
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showPSConfirmDialog(
      context,
      title: 'Sign out?',
      message:
          'You can sign back in anytime with the same Apple, Google, or email account.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!shouldSignOut) return;
    // Sign out first so AuthGate can move to the account screen immediately;
    // a slow outbox/network request must never make the user wait here.
    await AuthService.shared.signOut();
    // Wipes the local cache so a different account signing in on this same
    // device (shared phone, resold device, a reviewer switching accounts)
    // never sees this account's data — local reads have no per-user
    // scoping, so without this a second sign-in would see the first
    // account's full history until Supabase sync happened to layer over it.
    // Deliberately NOT the same helper "Delete account" uses
    // (`wipeLocalDatabase` in account_deletion.dart) — that one also wipes
    // `installations`, which is fine for a permanent deletion but would let
    // a casual sign-out/sign-in cycle mint a fresh device fingerprint. Sign-
    // out keeps the device identity; only the account-scoped data is cleared.
    wipeLocalUserData(ref.read(databaseProvider));
    await clearLocalPreferences();
    await AuthService.shared.rememberSignedOut();
    // No manual navigation needed — AuthGate's local sign-out signal and
    // auth-state listener switch to the sign-in screen automatically.
  }

  Future<void> _confirmDeleteAccount() async {
    final shouldDelete = await showPSConfirmDialog(
      context,
      title: 'Delete account?',
      message:
          'This permanently deletes your account and all your learning '
          'data, both on this device and on our servers. This can\'t be '
          'undone.',
      confirmLabel: 'Delete account',
      destructive: true,
    );
    if (!shouldDelete || !mounted) return;

    setState(() => _deletingAccount = true);
    final database = ref.read(databaseProvider);
    final result = await AuthService.shared.deleteAccount();

    if (result.outcome != AuthOutcome.success) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      await showPSConfirmDialog(
        context,
        title: 'Couldn\'t delete account',
        message:
            result.message ??
            'Something went wrong. Please try again, or email '
                'thoufeek@agiventures.ca and we\'ll delete it for you.',
        confirmLabel: 'OK',
        cancelLabel: 'Close',
      );
      return;
    }

    // HTTP 200 confirms server deletion. Move to login immediately, then
    // clear the device cache without making the user wait for remote logout.
    await AuthService.shared.signOutLocallyImmediately();
    try {
      wipeLocalDatabase(database);
      await clearLocalPreferences();
      await AuthService.shared.rememberSignedOut();
    } finally {
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      }
    }
  }

  String _entitlementLabel(PilotEntitlementStatus status) {
    return switch (status) {
      PilotEntitlementStatus.localPreview => 'Local preview',
      PilotEntitlementStatus.active => 'Active',
      PilotEntitlementStatus.grace => 'Grace period',
      PilotEntitlementStatus.inactive => 'Not active',
      PilotEntitlementStatus.verificationUnavailable => 'Check unavailable',
    };
  }

  /// Maps a raw RevenueCat product id to a plan name a learner can actually
  /// read.
  String _planName(String productId) {
    final normalized = productId.toLowerCase().replaceAll('-', '_');
    if (normalized.contains('12month') ||
        normalized.contains('annual') ||
        normalized.contains('year')) {
      return 'Annual Plan';
    }
    if (normalized.contains('3month') || normalized.contains('quarter')) {
      return '3-Month Plan';
    }
    if (normalized.contains('month')) return 'Monthly Plan';
    if (productId == 'app_review') return 'Reviewer access';
    return 'Free';
  }

  int _daysRemaining(DateTime expiresAt) {
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 0;
    return (remaining.inHours / 24).ceil();
  }

  Future<void> _openManageSubscriptions() async {
    final url = Platform.isIOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _openPaywall() async {
    await AppRouter.push(
      context,
      (_) => const SpeakPaywallScreen(),
      fullscreenDialog: true,
    );
    // `_access` is a plain snapshot taken once in initState, not something
    // Riverpod re-fetches on its own — without this, Settings keeps showing
    // "Free" after a successful purchase until the screen happens to be
    // torn down and rebuilt some other way.
    if (mounted) {
      setState(() => _access = ref.read(pilotAccessServiceProvider).snapshot());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        backgroundColor: DesignTokens.canvas,
        title: Text('Profile', style: DesignTokens.display(22)),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: WebConstrainedView(
        maxWidth: 920,
        child: PSContentColumn(
          measure: PSMeasure.content,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            children: [
              // --- Interactive walkthrough replay ---
              _ModernCard(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await AppTour.reset();
                    AppTour.pendingHomeReplay = true;
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: DesignTokens.infoSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          CupertinoIcons.play_circle_fill,
                          color: DesignTokens.info,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Replay the walkthrough',
                              style: DesignTokens.body(
                                15,
                                weight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'The guided tour of Home plays now; the call tour plays on your next call',
                              style: DesignTokens.body(
                                12,
                              ).copyWith(color: DesignTokens.mutedDim),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: DesignTokens.mutedDim,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // --- Subscription: plan, renewal/days left, upgrade/manage ---
              // Placed right under the walkthrough replay, near the top —
              // this is the single highest-intent action in Settings and
              // shouldn't be buried below Learning/Tutor preferences.
              Builder(
                builder: (context) {
                  final entitlement = _access.entitlement;
                  final subscribed = entitlement.grantsAccess;
                  final expiresAt = entitlement.expiresAt;
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: DesignTokens.surface,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusCard,
                      ),
                      border: Border.all(
                        color: DesignTokens.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.sparkles,
                              size: 16,
                              color: DesignTokens.primaryDeep,
                            ),
                            const SizedBox(width: 6),
                            KickerText(
                              'Subscription',
                              color: DesignTokens.primaryDeep,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _SettingsRow(
                          label: 'Plan',
                          value: subscribed
                              ? _planName(entitlement.productId)
                              : 'Free',
                        ),
                        if (subscribed && expiresAt != null) ...[
                          Divider(height: 1, color: DesignTokens.hairline),
                          _SettingsRow(
                            label: 'Renews',
                            value: DateFormat.yMMMd().format(expiresAt),
                          ),
                          Divider(height: 1, color: DesignTokens.hairline),
                          _SettingsRow(
                            label: 'Days left',
                            value: '${_daysRemaining(expiresAt)}',
                          ),
                        ],
                        const SizedBox(height: 10),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: subscribed
                              ? _openManageSubscriptions
                              : _openPaywall,
                          child: Container(
                            height: 46,
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: subscribed
                                  ? DesignTokens.canvasDim
                                  : DesignTokens.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (!subscribed) ...[
                                  Icon(
                                    CupertinoIcons.sparkles,
                                    size: 15,
                                    color: DesignTokens.onPrimary,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  subscribed
                                      ? 'Manage subscription'
                                      : 'Unlock full access',
                                  style:
                                      DesignTokens.body(
                                        14,
                                        weight: FontWeight.w700,
                                      ).copyWith(
                                        color: subscribed
                                            ? DesignTokens.mutedDim
                                            : Colors.white,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // --- Learning goal & pace (drives queue budgets and Marie's framing) ---
              _ModernCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KickerText('Learning', color: DesignTokens.mutedDim),
                    const SizedBox(height: 6),
                    _ChoiceRow(
                      label: 'Level',
                      options: [
                        for (final level in LearnerLevel.cefrValues)
                          (level, LearnerLevel.displayLabel(level)),
                      ],
                      selected: _profile.level,
                      onChanged: _confirmLevelChange,
                    ),
                    Divider(height: 16, color: DesignTokens.hairline),
                    _ChoiceRow(
                      label: 'Goal',
                      options: const [
                        ('tef_canada', 'TEF Canada'),
                        ('everyday', 'Everyday'),
                        ('work', 'Professional'),
                        ('relocation', 'Relocation'),
                        ('travel', 'Travel'),
                        ('culture', 'Culture'),
                        ('unsure', 'Exploring'),
                      ],
                      selected: _profile.goal,
                      onChanged: (v) => _saveProfile((p) => p.goal = v),
                    ),
                    Divider(height: 16, color: DesignTokens.hairline),
                    _ChoiceRow(
                      label: 'Session length',
                      options: const [
                        ('quick', 'Quick'),
                        ('standard', 'Standard'),
                        ('deep', 'Deep'),
                      ],
                      selected: _profile.sessionLength,
                      onChanged: (v) =>
                          _saveProfile((p) => p.sessionLength = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // --- Course focus: every skill stays available; these choices
              // control which foundations receive the strongest route weight.
              _ModernCard(child: _courseFocusEditor()),
              const SizedBox(height: 12),

              // --- Study schedule (the same preferences captured in onboarding) ---
              _ModernCard(child: _scheduleEditor()),
              const SizedBox(height: 12),

              // --- Tutor (P2.1/P2.3): persona, language mix, voice speed ---
              _ModernCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KickerText('Your tutor', color: DesignTokens.mutedDim),
                    const SizedBox(height: 4),
                    Text(
                      'Applies from your next call, a call in progress keeps '
                      'the tutor it started with.',
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                    const SizedBox(height: 12),
                    _personaGrid(),
                    Divider(height: 22, color: DesignTokens.hairline),
                    _ChoiceRow(
                      label: 'English / French mix',
                      options: const [
                        ('gentle', 'Gentle'),
                        ('balanced', 'Balanced'),
                        ('immersive', 'Immersion'),
                      ],
                      selected: _languageMix,
                      onChanged: (v) {
                        setState(() => _languageMix = v);
                        TutorTuning.saveLanguageMix(v);
                      },
                    ),
                    Divider(height: 16, color: DesignTokens.hairline),
                    _ChoiceRow(
                      label: 'Tutor speaking pace',
                      options: const [
                        ('slower', 'Slower'),
                        ('natural', 'Natural'),
                        ('faster', 'Faster'),
                      ],
                      selected: _voiceSpeed,
                      onChanged: (v) {
                        setState(() => _voiceSpeed = v);
                        TutorTuning.saveVoiceSpeed(v);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // --- Tutor helper: one source, independent preference per skill ---
              const TutorHelperSettingsPanel(),
              const SizedBox(height: 12),

              // --- Roadmap ---
              _ModernCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KickerText('Roadmap', color: DesignTokens.mutedDim),
                    const SizedBox(height: 10),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _pickRoadmapStartDate,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Text(
                              'Start date',
                              style: DesignTokens.body(
                                12.5,
                              ).copyWith(color: DesignTokens.mutedDim),
                            ),
                            const Spacer(),
                            Text(
                              DateFormat.yMMMd().format(_roadmapStartDate),
                              style: DesignTokens.mono(
                                12,
                                weight: FontWeight.w500,
                              ).copyWith(color: DesignTokens.primary),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              CupertinoIcons.calendar,
                              size: 14,
                              color: DesignTokens.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // --- Lesson voice ---
              _ModernCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KickerText('Lesson voice', color: DesignTokens.mutedDim),
                    const SizedBox(height: 10),
                    Text(
                      'Narration rate',
                      style: DesignTokens.body(
                        12.5,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                    const SizedBox(height: 4),
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: DesignTokens.primary,
                        inactiveTrackColor: DesignTokens.primary.withValues(
                          alpha: 0.2,
                        ),
                        thumbColor: DesignTokens.primary,
                        overlayColor: DesignTokens.primary.withValues(
                          alpha: 0.12,
                        ),
                      ),
                      child: Slider(
                        value: _narrationRate,
                        min: 0.3,
                        max: 0.55,
                        onChanged: (v) {
                          setState(() => _narrationRate = v);
                          _saveDouble('lesson_narration_rate', v);
                        },
                      ),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'New cards/day (labs): $_newCardsPerDay',
                            style: DesignTokens.body(
                              12.5,
                            ).copyWith(color: DesignTokens.text),
                          ),
                          const Spacer(),
                          _StepperButton(
                            icon: CupertinoIcons.minus,
                            onTap: _newCardsPerDay > 5
                                ? () {
                                    setState(() => _newCardsPerDay -= 5);
                                    _saveInt(
                                      'srs_new_cards_per_day',
                                      _newCardsPerDay,
                                    );
                                  }
                                : null,
                          ),
                          const SizedBox(width: 8),
                          _StepperButton(
                            icon: CupertinoIcons.plus,
                            onTap: _newCardsPerDay < 50
                                ? () {
                                    setState(() => _newCardsPerDay += 5);
                                    _saveInt(
                                      'srs_new_cards_per_day',
                                      _newCardsPerDay,
                                    );
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    // How many honest attempts a NEW word needs in a live session before
                    // Marie is allowed to offer moving on (familiar words need two fewer).
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Practice passes per word: $_practicePasses',
                                style: DesignTokens.body(
                                  12.5,
                                ).copyWith(color: DesignTokens.text),
                              ),
                              Text(
                                'How many times you repeat a new word before ${ActiveTutor.current.displayName} may suggest the next one',
                                style: DesignTokens.mono(
                                  10,
                                ).copyWith(color: DesignTokens.mutedDim),
                              ),
                            ],
                          ),
                        ),
                        _StepperButton(
                          icon: CupertinoIcons.minus,
                          onTap: _practicePasses > 2
                              ? () {
                                  setState(() => _practicePasses -= 1);
                                  _saveInt(
                                    'practice_passes_per_word',
                                    _practicePasses,
                                  );
                                }
                              : null,
                        ),
                        const SizedBox(width: 8),
                        _StepperButton(
                          icon: CupertinoIcons.plus,
                          onTap: _practicePasses < 10
                              ? () {
                                  setState(() => _practicePasses += 1);
                                  _saveInt(
                                    'practice_passes_per_word',
                                    _practicePasses,
                                  );
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // --- Vocabulary practice ---
              _ModernCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KickerText(
                      'Vocabulary practice',
                      color: DesignTokens.mutedDim,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Words per practice: $_autoQueueSize',
                                style: DesignTokens.body(
                                  12.5,
                                ).copyWith(color: DesignTokens.text),
                              ),
                              Text(
                                'How many words the Auto queue shows each time. Smaller means less repetition if you practice more than once a day',
                                style: DesignTokens.mono(
                                  10,
                                ).copyWith(color: DesignTokens.mutedDim),
                              ),
                            ],
                          ),
                        ),
                        _StepperButton(
                          icon: CupertinoIcons.minus,
                          onTap: _autoQueueSize > 1
                              ? () {
                                  setState(() => _autoQueueSize -= 1);
                                  SRSService.setAutoQueueSize(_autoQueueSize);
                                }
                              : null,
                        ),
                        const SizedBox(width: 8),
                        _StepperButton(
                          icon: CupertinoIcons.plus,
                          onTap: _autoQueueSize < 10
                              ? () {
                                  setState(() => _autoQueueSize += 1);
                                  SRSService.setAutoQueueSize(_autoQueueSize);
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (kDebugMode) ...[
                _ModernCard(
                  child: GestureDetector(
                    onTap: () => AppRouter.push(
                      context,
                      (_) => const OrchestrationLabScreen(),
                    ),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.lab_flask,
                            size: 21,
                            color: DesignTokens.mastery,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Orchestration Lab',
                                  style: DesignTokens.body(
                                    14,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Preview personas, constraints, and competency paths',
                                  style: DesignTokens.body(
                                    11.5,
                                  ).copyWith(color: DesignTokens.mutedDim),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            CupertinoIcons.chevron_forward,
                            size: 16,
                            color: DesignTokens.mutedDim,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _ModernCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KickerText('Developer', color: DesignTokens.mutedDim),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'Force unlock premium',
                            style: DesignTokens.body(12.5),
                          ),
                          const Spacer(),
                          Switch.adaptive(
                            value: DevSubscriptionOverride.enabled,
                            activeThumbColor: DesignTokens.primary,
                            onChanged: (v) {
                              DevSubscriptionOverride.set(v).then((_) {
                                if (mounted) setState(() {});
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Bypasses subscription checks for testing. '
                        'Debug builds only, compiled out entirely from release.',
                        style: DesignTokens.body(
                          11.5,
                        ).copyWith(color: DesignTokens.mutedDim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // --- Notetaker ---
              _ModernCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KickerText('Notetaker', color: DesignTokens.mutedDim),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          'Floating notetaker',
                          style: DesignTokens.body(12.5),
                        ),
                        const Spacer(),
                        Switch.adaptive(
                          value: ref.read(notetakerStateProvider).isEnabled,
                          activeThumbColor: DesignTokens.primary,
                          onChanged: (v) {
                            setState(
                              () => ref.read(notetakerStateProvider).isEnabled =
                                  v,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Shows a draggable note bubble during lessons so you can '
                      'jot things down while listening or writing.',
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              _ModernCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KickerText(
                      'Subscription access',
                      color: DesignTokens.mutedDim,
                    ),
                    const SizedBox(height: 4),
                    _SettingsRow(
                      label: 'Access status',
                      value: _entitlementLabel(_access.entitlement.status),
                    ),
                    Divider(height: 1, color: DesignTokens.hairline),
                    _SettingsRow(
                      label: 'Tracked speaking today',
                      value:
                          '${(_access.remainingSeconds / 60).ceil()} min remaining',
                    ),
                    Divider(height: 1, color: DesignTokens.hairline),
                    _SettingsRow(
                      label: 'Verification',
                      value: _access.serverAuthoritative
                          ? 'Cloud verified'
                          : 'Local preview',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // --- Account ---
              _ModernCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KickerText('Account', color: DesignTokens.mutedDim),
                    const SizedBox(height: 4),
                    _SettingsRow(
                      label: 'Account name',
                      value: AuthService.shared.signedInDisplayName,
                    ),
                    Divider(height: 1, color: DesignTokens.hairline),
                    _SettingsRow(
                      label: 'Email',
                      value:
                          AuthService.shared.signedInEmailLabel ??
                          'Not provided by this sign-in',
                    ),
                    Divider(height: 1, color: DesignTokens.hairline),
                    _SettingsRow(
                      label: 'Signed in with',
                      value: AuthService.shared.signedInProvider,
                    ),
                    Divider(height: 1, color: DesignTokens.hairline),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Your password is never displayed in the app.',
                        style: DesignTokens.body(
                          11.5,
                        ).copyWith(color: DesignTokens.mutedDim),
                      ),
                    ),
                    Divider(height: 1, color: DesignTokens.hairline),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _confirmSignOut,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Sign out',
                          style: DesignTokens.body(
                            13,
                            weight: FontWeight.w600,
                          ).copyWith(color: DesignTokens.danger),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: DesignTokens.hairline),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _deletingAccount ? null : _confirmDeleteAccount,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.centerLeft,
                        child: _deletingAccount
                            ? Row(
                                children: [
                                  SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: DesignTokens.danger,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Deleting account…',
                                    style: DesignTokens.body(
                                      13,
                                      weight: FontWeight.w600,
                                    ).copyWith(color: DesignTokens.danger),
                                  ),
                                ],
                              )
                            : Text(
                                'Delete account',
                                style: DesignTokens.body(
                                  13,
                                  weight: FontWeight.w600,
                                ).copyWith(color: DesignTokens.danger),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // --- About & support ---
              _ModernCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KickerText('ParleSprint', color: DesignTokens.mutedDim),
                    const SizedBox(height: 4),
                    _SettingsRow(
                      label: 'Version',
                      value: _appVersion.isEmpty ? 'N/A' : _appVersion,
                    ),
                    Divider(height: 1, color: DesignTokens.hairline),
                    _SettingsRow(
                      label: 'Feedback',
                      value: 'thoufeekbaber1@gmail.com',
                    ),
                    Divider(height: 1, color: DesignTokens.hairline),
                    _LegalLinkRow(
                      label: 'Privacy Policy',
                      url: 'https://parlesprint.com/privacy',
                    ),
                    Divider(height: 1, color: DesignTokens.hairline),
                    _LegalLinkRow(
                      label: 'Terms of Service',
                      url: 'https://parlesprint.com/terms',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline pill selector for short exclusive choices.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: DesignTokens.body(12.5).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((o) {
            final isSelected = o.$1 == selected;
            return GestureDetector(
              onTap: () => onChanged(o.$1),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? DesignTokens.primary
                      : DesignTokens.canvasDim,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  o.$2,
                  style: DesignTokens.body(11.5, weight: FontWeight.w600)
                      .copyWith(
                        color: isSelected
                            ? DesignTokens.onPrimary
                            : DesignTokens.text,
                      ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable helpers
// ---------------------------------------------------------------------------

class _ModernCard extends StatelessWidget {
  const _ModernCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: DesignTokens.surfaceShadow,
      ),
      child: child,
    );
  }
}

/// A tappable settings row that opens an external URL (App Store/Play Store
/// review both expect a reachable privacy policy from inside the app, not
/// just on the marketing site).
class _LegalLinkRow extends StatelessWidget {
  const _LegalLinkRow({required this.label, required this.url});
  final String label;
  final String url;

  Future<void> _open() async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser available on this device — nothing more we can do here.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: DesignTokens.body(
                    12.5,
                  ).copyWith(color: DesignTokens.text),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 14,
                color: DesignTokens.mutedDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: DesignTokens.body(
                12.5,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: DesignTokens.body(
                12,
                weight: FontWeight.w600,
              ).copyWith(color: DesignTokens.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: enabled
              ? DesignTokens.primary.withValues(alpha: 0.1)
              : DesignTokens.muted.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? DesignTokens.primary : DesignTokens.muted,
        ),
      ),
    );
  }
}
