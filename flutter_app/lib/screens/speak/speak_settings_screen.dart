import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database/account_deletion.dart';
import '../../data/database/local_data_reset.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/pilot_access.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../services/app_tour.dart';
import '../../services/auth_service.dart';
import '../../services/revenue_cat_service.dart';
import '../../services/tutor_voice_preview.dart';
import '../subscription/speak_paywall_screen.dart';
import '../../widgets/adaptive/adaptive.dart';
import 'speak_advanced_settings_screen.dart';
import 'speak_ui.dart';
import 'v3_settings_screen.dart';

class SpeakSettingsScreen extends ConsumerStatefulWidget {
  const SpeakSettingsScreen({super.key, this.onReplayPractice});

  final VoidCallback? onReplayPractice;

  @override
  ConsumerState<SpeakSettingsScreen> createState() =>
      _SpeakSettingsScreenState();
}

class _SpeakSettingsScreenState extends ConsumerState<SpeakSettingsScreen>
    with WidgetsBindingObserver {
  var _dailyReminder = true;
  var _wifiOnly = false;
  var _haptics = true;
  var _deletingAccount = false;
  var _accountDetailsExpanded = false;
  var _deletionDots = 1;
  Timer? _deletionTimer;
  TutorPersona _tutor = ActiveTutor.current;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Refresh once when the Membership row is opened so a purchase or offer
    // redemption completed outside this screen is reflected immediately.
    unawaited(RevenueCatService.shared.refreshCustomerInfo());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(RevenueCatService.shared.refreshCustomerInfo());
    }
  }

  String get _deletionLabel => 'Deleting account${'.' * _deletionDots}';

  void _startDeletionAnimation() {
    _deletionTimer?.cancel();
    _deletionDots = 1;
    _deletionTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted || !_deletingAccount) return;
      setState(
        () => _deletionDots = _deletionDots == 3 ? 1 : _deletionDots + 1,
      );
    });
  }

  void _stopDeletionAnimation() {
    _deletionTimer?.cancel();
    _deletionTimer = null;
  }

  void _returnToAuthGate() {
    if (!mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopDeletionAnimation();
    super.dispose();
  }

  String _membershipPlan(String productId) {
    final normalized = productId.toLowerCase().replaceAll('-', '_');
    if (normalized.contains('12month') ||
        normalized.contains('annual') ||
        normalized.contains('year')) {
      return 'Annual plan';
    }
    if (normalized.contains('3month') || normalized.contains('quarter')) {
      return '3-month plan';
    }
    if (normalized.contains('month')) return 'Monthly plan';
    return 'Active subscription';
  }

  String _membershipSubtitle(PilotEntitlement entitlement) {
    if (!entitlement.isPaidActive) {
      return 'Premium plans and restore purchase';
    }
    final plan = _membershipPlan(entitlement.productId);
    final expiresAt = entitlement.expiresAt;
    if (expiresAt == null) return '$plan · Active';
    return '$plan · Renews ${DateFormat.yMMMd().format(expiresAt.toLocal())}';
  }

  Future<void> _openMembership() async {
    final entitlement = ref
        .read(pilotAccessServiceProvider)
        .snapshot()
        .entitlement;
    if (!entitlement.isPaidActive) {
      await AppRouter.push(
        context,
        (_) => const SpeakPaywallScreen(),
        fullscreenDialog: true,
      );
      if (mounted) setState(() {});
      return;
    }
    final url = defaultTargetPlatform == TargetPlatform.iOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _openUrl(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openSupport() async {
    await _openUrl(
      Uri(
        scheme: 'mailto',
        path: 'thoufeekbaber1@gmail.com',
        queryParameters: {
          'subject': 'ParleSprint support',
          'body': 'Hi Thoufeek,\n\nI need help with ParleSprint.\n\n',
        },
      ),
    );
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

    // Sign out first so the app shell changes immediately; a slow network
    // sync must never leave the user staring at the authenticated screen.
    await AuthService.shared.signOut();
    // Keep device-level installation identity, but remove all account data so
    // a different account on this device cannot see the previous user's data.
    wipeLocalUserData(ref.read(databaseProvider));
    await clearLocalPreferences();
    await AuthService.shared.rememberSignedOut();
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
    _startDeletionAnimation();
    final database = ref.read(databaseProvider);
    final result = await AuthService.shared.deleteAccount();

    if (result.outcome != AuthOutcome.success) {
      _stopDeletionAnimation();
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

    // HTTP 200 confirms that the server-side account is gone. Sign out
    // locally immediately, then clear this pushed settings route so the
    // signed-out AuthGate is visible instead of leaving the deletion label
    // stranded above it.
    _stopDeletionAnimation();
    await AuthService.shared.signOutLocallyImmediately();
    try {
      wipeLocalDatabase(database);
      await clearLocalPreferences();
      await AuthService.shared.rememberSignedOut();
    } finally {
      _returnToAuthGate();
    }
  }

  Future<void> _chooseLanguage() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Learning language', style: DesignTokens.display(22)),
              const SizedBox(height: 6),
              Text(
                'ParleSprint currently teaches French. Your CEFR level controls how much English support appears around the French.',
                style: DesignTokens.body(
                  13,
                ).copyWith(color: SpeakColors.inkSoft),
              ),
              const SizedBox(height: 18),
              SpeakCard(
                color: SpeakColors.blueSoft,
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: SpeakColors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'French',
                        style: DesignTokens.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      'Active',
                      style: DesignTokens.body(
                        12,
                        weight: FontWeight.w700,
                      ).copyWith(color: SpeakColors.blue),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseTutor() async {
    final picked = await showModalBottomSheet<TutorPersona>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _TutorPickerSheet(selected: _tutor),
    );
    if (picked == null || !mounted) return;
    await ActiveTutor.set(picked);
    if (mounted) setState(() => _tutor = picked);
  }

  Future<void> _replayPracticeTour() async {
    await AppTour.resetPractice();
    if (!mounted) return;
    if (widget.onReplayPractice == null) {
      AppTour.pendingPracticeReplay = true;
      await Navigator.of(context).maybePop();
      return;
    }
    await Navigator.of(context).maybePop();
    widget.onReplayPractice!();
  }

  @override
  Widget build(BuildContext context) {
    // Keep this legacy route name as a compatibility boundary for existing
    // Home, Speaking, and Reading entry points. Settings itself is now one
    // canonical V3 surface with modal editing.
    return V3SettingsScreen(onReplayPractice: widget.onReplayPractice);
    /*
    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          SpeakHeader(
            title: 'Settings',
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: SpeakColors.inkSoft,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _section('Account', [
            _accountRow(),
            _row(
              Icons.workspace_premium_outlined,
              'Membership',
              _membershipSubtitle(
                ref.watch(pilotAccessServiceProvider).snapshot().entitlement,
              ),
              onTap: _openMembership,
            ),
            _row(
              Icons.logout_rounded,
              'Sign out',
              'Sign out of this device',
              onTap: _confirmSignOut,
              accentColor: DesignTokens.danger,
              destructive: true,
            ),
            _row(
              Icons.delete_outline_rounded,
              _deletingAccount ? _deletionLabel : 'Delete account',
              'Permanently remove your account and learning data',
              onTap: _deletingAccount ? null : _confirmDeleteAccount,
              accentColor: DesignTokens.danger,
              destructive: true,
            ),
          ]),
          const SizedBox(height: 20),
          _section('Preferences', [
            _toggleRow(
              Icons.notifications_none_rounded,
              'Daily reminder',
              'Keep your practice consistent',
              _dailyReminder,
              (value) => setState(() => _dailyReminder = value),
            ),
            _toggleRow(
              Icons.wifi_rounded,
              'Download on Wi-Fi only',
              'Save lessons for offline practice',
              _wifiOnly,
              (value) => setState(() => _wifiOnly = value),
            ),
            _toggleRow(
              Icons.vibration_rounded,
              'Haptics',
              'Use gentle feedback while you practise',
              _haptics,
              (value) => setState(() => _haptics = value),
            ),
            _toggleRow(
              Icons.edit_note_rounded,
              'Floating notetaker',
              'Keep a draggable note bubble available during lessons',
              ref.read(notetakerStateProvider).isEnabled,
              (value) => setState(
                () => ref.read(notetakerStateProvider).isEnabled = value,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          _section('Learning', [
            _row(
              Icons.translate_rounded,
              'Language',
              'French · CEFR-guided support',
              onTap: _chooseLanguage,
            ),
            _row(
              Icons.record_voice_over_outlined,
              'Tutor voice',
              _tutor.displayName,
              onTap: _chooseTutor,
            ),
            _row(
              Icons.tune_rounded,
              'Advanced learning controls',
              'Goals, speech and review settings',
              onTap: () => AppRouter.push(
                context,
                (_) => const SpeakAdvancedSettingsScreen(),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          _section('Support', [
            _row(
              Icons.school_outlined,
              'Replay Practice walkthrough',
              'See what Free Talk, skills, review, and exams do',
              onTap: _replayPracticeTour,
            ),
            _row(
              Icons.help_outline_rounded,
              'Help center',
              'Get answers and contact support',
              onTap: _openSupport,
            ),
            _row(
              Icons.info_outline_rounded,
              'About ParleSprint',
              'Visit parlesprint.com',
              onTap: () => _openUrl(Uri.parse('https://parlesprint.com')),
            ),
            _row(
              Icons.privacy_tip_outlined,
              'Privacy policy',
              'How ParleSprint handles your data',
              onTap: () =>
                  _openUrl(Uri.parse('https://parlesprint.com/privacy')),
            ),
            _row(
              Icons.description_outlined,
              'Terms and Conditions',
              'Read ParleSprint\'s terms',
              onTap: () => _openUrl(Uri.parse('https://parlesprint.com/terms')),
            ),
          ]),
        ],
      ),
    );
    */
  }

  Widget _section(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: DesignTokens.label(
            10,
          ).copyWith(color: SpeakColors.inkSoft, letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        SpeakCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: SpeakColors.line),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    IconData icon,
    String title,
    String subtitle, {
    required VoidCallback? onTap,
    Color? accentColor,
    bool destructive = false,
    bool expanded = false,
  }) {
    final titleStyle = DesignTokens.body(14, weight: FontWeight.w700);
    final rowColor = accentColor ?? SpeakColors.blue;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: rowColor, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: destructive
                        ? titleStyle.copyWith(color: rowColor)
                        : titleStyle,
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
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.chevron_right_rounded,
              color: SpeakColors.inkSoft,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountRow() {
    final name = AuthService.shared.signedInDisplayName;
    final email = AuthService.shared.signedInEmailLabel;
    final provider = AuthService.shared.signedInProvider;
    return Column(
      children: [
        _row(
          Icons.person_outline_rounded,
          'Profile',
          name,
          onTap: () => setState(
            () => _accountDetailsExpanded = !_accountDetailsExpanded,
          ),
          expanded: _accountDetailsExpanded,
        ),
        if (_accountDetailsExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(47, 0, 14, 14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: DesignTokens.canvas,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _compactAccountDetail(
                    'Email',
                    email ?? 'Not provided by this sign-in',
                  ),
                  const SizedBox(height: 7),
                  _compactAccountDetail('Signed in with', provider),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _compactAccountDetail(String label, String value) {
    return RichText(
      text: TextSpan(
        style: DesignTokens.body(11.5).copyWith(color: SpeakColors.inkSoft),
        children: [
          TextSpan(
            text: '$label  ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Icon(icon, color: SpeakColors.blue, size: 21),
          const SizedBox(width: 12),
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
            activeThumbColor: SpeakColors.blue,
          ),
        ],
      ),
    );
  }
}

class _TutorPickerSheet extends StatefulWidget {
  const _TutorPickerSheet({required this.selected});

  final TutorPersona selected;

  @override
  State<_TutorPickerSheet> createState() => _TutorPickerSheetState();
}

class _TutorPickerSheetState extends State<_TutorPickerSheet> {
  late final TutorVoicePreviewer _previewer;

  @override
  void initState() {
    super.initState();
    _previewer = TutorVoicePreviewer();
  }

  @override
  void dispose() {
    _previewer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tutor voice', style: DesignTokens.display(22)),
            const SizedBox(height: 6),
            Text(
              'Choose a voice for future sessions. You can preview each one before saving.',
              style: DesignTokens.body(13).copyWith(color: SpeakColors.inkSoft),
            ),
            const SizedBox(height: 14),
            for (final tutor in TutorPersona.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(tutor),
                  child: SpeakCard(
                    color: tutor.id == widget.selected.id
                        ? SpeakColors.blueSoft
                        : Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        ClipOval(
                          child: SizedBox.square(
                            dimension: 40,
                            child: Image.asset(
                              tutor.portraitAsset,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              errorBuilder: (context, error, stackTrace) =>
                                  CircleAvatar(
                                    backgroundColor: SpeakColors.blue,
                                    child: Text(
                                      tutor.initial,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tutor.displayName,
                                style: DesignTokens.body(
                                  14,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                tutor.tagline,
                                style: DesignTokens.body(
                                  11,
                                ).copyWith(color: SpeakColors.inkSoft),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Preview ${tutor.displayName}',
                          onPressed: () async {
                            if (_previewer.playingId == tutor.id) {
                              await _previewer.stop();
                            } else {
                              await _previewer.play(tutor);
                            }
                            if (mounted) setState(() {});
                          },
                          icon: Icon(
                            _previewer.playingId == tutor.id
                                ? Icons.stop_circle_outlined
                                : Icons.play_circle_outline_rounded,
                            color: SpeakColors.blue,
                          ),
                        ),
                        if (tutor.id == widget.selected.id)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: SpeakColors.blue,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
