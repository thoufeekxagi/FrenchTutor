import '../../widgets/adaptive/adaptive.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../data/database/account_deletion.dart';
import '../../design/app_router.dart';
import '../../models/pilot_access.dart';
import '../../models/profile.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../services/app_tour.dart';
import '../../services/auth_service.dart';
import '../../services/referral_service.dart';
import '../../services/subscription_gate_service.dart';
import '../../services/tutor_voice_preview.dart';
import 'orchestration_lab_screen.dart';
import 'product_guide_screen.dart';
import '../../widgets/kicker_text.dart';

const availableModels = [
  'meta-llama/llama-3.3-70b-instruct:free',
  'google/gemma-3-27b-it:free',
  'mistralai/mistral-small-3.1-24b-instruct:free',
];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  double _narrationRate = 0.42;
  int _newCardsPerDay = 20;
  int _practicePasses = 5;
  DateTime _roadmapStartDate = DateTime.now();
  String _modelOverride = '';
  String _openRouterKey = '';
  TutorPersona _persona = ActiveTutor.current;
  String _languageMix = 'balanced';
  String _voiceSpeed = 'natural';
  bool _deletingAccount = false;
  ReferralStats? _referralStats;
  int _bonusSecondsBalance = 0;
  bool _redeeming = false;
  final _redeemController = TextEditingController();
  late final TutorVoicePreviewer _previewer = TutorVoicePreviewer()
    ..addListener(() {
      if (mounted) setState(() {});
    });
  late Profile _profile;
  late PilotAccessSnapshot _access;

  @override
  void initState() {
    super.initState();
    _profile = ref.read(learningStoreProvider).profile();
    _access = ref.read(pilotAccessServiceProvider).snapshot();
    _loadSettings();
    _loadReferralInfo();
  }

  @override
  void dispose() {
    _previewer.dispose();
    _redeemController.dispose();
    super.dispose();
  }

  Future<void> _loadReferralInfo() async {
    final stats = await ReferralService.shared.myReferralStats();
    final bonusSeconds = await ReferralService.shared.refreshBonusBalance();
    if (!mounted) return;
    setState(() {
      _referralStats = stats;
      _bonusSecondsBalance = bonusSeconds;
    });
  }

  Future<void> _copyReferralCode() async {
    final code = _referralStats?.code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invite code copied')));
  }

  Future<void> _redeemCode() async {
    final code = _redeemController.text.trim();
    if (code.isEmpty || _redeeming) return;
    final installationId = ref
        .read(pilotInfrastructureStoreProvider)
        .installationId('app');
    setState(() => _redeeming = true);
    final result = await ReferralService.shared.redeem(
      code,
      installationId: installationId,
    );
    if (!mounted) return;
    setState(() => _redeeming = false);

    final message = switch (result.outcome) {
      RedeemOutcome.success =>
        'You and your friend each got ${result.bonusMinutes} bonus minutes!',
      RedeemOutcome.alreadyRedeemed =>
        'You\'ve already redeemed an invite code.',
      RedeemOutcome.deviceAlreadyUsed =>
        'An invite code has already been redeemed on this device.',
      RedeemOutcome.invalidCode => 'That code doesn\'t look right.',
      RedeemOutcome.cannotRedeemOwnCode =>
        'That\'s your own code — share it with a friend instead.',
      RedeemOutcome.codeLimitReached =>
        'That code has already been used the maximum number of times.',
      RedeemOutcome.networkError =>
        'Couldn\'t reach the server, try again in a moment.',
    };
    if (result.outcome == RedeemOutcome.success) {
      _redeemController.clear();
      setState(
        () => _bonusSecondsBalance =
            ReferralService.shared.cachedBonusSecondsBalance,
      );
    }
    await showPSConfirmDialog(
      context,
      title: result.outcome == RedeemOutcome.success
          ? 'Invite redeemed!'
          : 'Couldn\'t redeem code',
      message: message,
      confirmLabel: 'OK',
      cancelLabel: 'OK',
    );
  }

  void _saveProfile(void Function(Profile) mutate) {
    setState(() => mutate(_profile));
    ref.read(learningStoreProvider).saveProfile(_profile);
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
      _modelOverride = prefs.getString('openrouter_model_override') ?? '';
      _openRouterKey = prefs.getString('openrouter_api_key') ?? '';
      final timestamp = prefs.getInt('roadmap_start_date');
      if (timestamp != null) {
        _roadmapStartDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    });
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

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
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
              // Selected = the same azure gradient as the onboarding hero,
              // never an off-palette ink/brass combination.
              color: selected ? null : Passeport.parchmentDim,
              gradient: selected
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        DesignTokens.primaryDeep,
                        DesignTokens.primary,
                        DesignTokens.secondary,
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? Colors.transparent : Passeport.hairline,
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
                        style: Passeport.body(14, weight: FontWeight.w700)
                            .copyWith(
                              color: selected ? Colors.white : Passeport.ink,
                            ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _previewer.play(p),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _previewer.loadingId == p.id
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Passeport.sky,
                                ),
                              )
                            : Icon(
                                _previewer.playingId == p.id
                                    ? CupertinoIcons.stop_circle_fill
                                    : CupertinoIcons.play_circle_fill,
                                color: selected
                                    ? Colors.white
                                    : Passeport.sky,
                                size: 19,
                              ),
                      ),
                    ),
                    if (selected)
                      const Icon(
                        CupertinoIcons.checkmark_circle_fill,
                        color: Colors.white,
                        size: 17,
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${p.accent.label} French',
                  style: Passeport.body(10.5, weight: FontWeight.w700).copyWith(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.9)
                        : Passeport.maroon,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  p.tagline,
                  style: Passeport.body(10.5).copyWith(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.75)
                        : Passeport.slateDim,
                  ),
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

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showPSConfirmDialog(
      context,
      title: 'Sign out?',
      message:
          'You can sign back in anytime with the same Apple, Google, or email account.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (shouldSignOut) {
      await AuthService.shared.signOut();
      // No manual navigation needed — AuthGate's own auth-state listener
      // switches to the sign-in screen automatically once the session clears.
    }
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
    final result = await AuthService.shared.deleteAccount();
    if (!mounted) return;

    if (result.outcome != AuthOutcome.success) {
      setState(() => _deletingAccount = false);
      await showPSConfirmDialog(
        context,
        title: 'Couldn\'t delete account',
        message:
            result.message ??
            'Something went wrong. Please try again, or email '
                'thoufeek@agiventures.ca and we\'ll delete it for you.',
        confirmLabel: 'OK',
        cancelLabel: 'OK',
      );
      return;
    }

    // The server-side account is gone — now clear everything this device
    // holds locally so no trace of the deleted account remains.
    wipeLocalDatabase(ref.read(databaseProvider));
    await clearLocalPreferences();
    await AuthService.shared.signOut();
    // No manual navigation needed — AuthGate's auth-state listener switches
    // to the sign-in screen automatically once the session clears.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchment,
      appBar: AppBar(
        backgroundColor: Passeport.parchment,
        title: Text('Settings', style: Passeport.display(22)),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: PSContentColumn(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          children: [
            _PasseportCard(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    AppRouter.push(context, (_) => const ProductGuideScreen()),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Passeport.infoSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        CupertinoIcons.question_circle_fill,
                        color: Passeport.info,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'How ParleSprint works',
                            style: Passeport.body(15, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Missions, cards, voice controls, Marie, and progress',
                            style: Passeport.body(
                              12,
                            ).copyWith(color: Passeport.slateDim),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: Passeport.slateDim,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // --- Interactive walkthrough replay ---
            _PasseportCard(
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
                        color: Passeport.infoSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        CupertinoIcons.play_circle_fill,
                        color: Passeport.info,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Replay the walkthrough',
                            style: Passeport.body(15, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'The guided tour of Home plays now; the call tour plays on your next call',
                            style: Passeport.body(
                              12,
                            ).copyWith(color: Passeport.slateDim),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: Passeport.slateDim,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // --- Learning goal & pace (drives queue budgets and Marie's framing) ---
            _PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Learning', color: Passeport.slateDim),
                  const SizedBox(height: 6),
                  _ChoiceRow(
                    label: 'Goal',
                    options: const [
                      ('tef_canada', 'TEF Canada'),
                      ('everyday', 'Everyday'),
                      ('unsure', 'Exploring'),
                    ],
                    selected: _profile.goal,
                    onChanged: (v) => _saveProfile((p) => p.goal = v),
                  ),
                  Divider(height: 16, color: Passeport.hairline),
                  _ChoiceRow(
                    label: 'Session length',
                    options: const [
                      ('quick', 'Quick'),
                      ('standard', 'Standard'),
                      ('deep', 'Deep'),
                    ],
                    selected: _profile.sessionLength,
                    onChanged: (v) => _saveProfile((p) => p.sessionLength = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // --- Tutor (P2.1/P2.3): persona, language mix, voice speed ---
            _PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Your tutor', color: Passeport.slateDim),
                  const SizedBox(height: 4),
                  Text(
                    'Applies from your next call, a call in progress keeps '
                    'the tutor it started with.',
                    style: Passeport.body(
                      11,
                    ).copyWith(color: Passeport.slateDim),
                  ),
                  const SizedBox(height: 12),
                  _personaGrid(),
                  Divider(height: 22, color: Passeport.hairline),
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
                  Divider(height: 16, color: Passeport.hairline),
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

            // --- Roadmap ---
            _PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Roadmap', color: Passeport.slateDim),
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
                            style: Passeport.body(
                              12.5,
                            ).copyWith(color: Passeport.slateDim),
                          ),
                          const Spacer(),
                          Text(
                            DateFormat.yMMMd().format(_roadmapStartDate),
                            style: Passeport.mono(
                              12,
                              weight: FontWeight.w500,
                            ).copyWith(color: Passeport.maroon),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            CupertinoIcons.calendar,
                            size: 14,
                            color: Passeport.maroon,
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
            _PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Lesson voice', color: Passeport.slateDim),
                  const SizedBox(height: 10),
                  Text(
                    'Narration rate',
                    style: Passeport.body(
                      12.5,
                    ).copyWith(color: Passeport.slateDim),
                  ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: Passeport.maroon,
                      inactiveTrackColor: Passeport.maroon.withValues(
                        alpha: 0.2,
                      ),
                      thumbColor: Passeport.maroon,
                      overlayColor: Passeport.maroon.withValues(alpha: 0.12),
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
                          style: Passeport.body(
                            12.5,
                          ).copyWith(color: Passeport.text),
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
                              style: Passeport.body(
                                12.5,
                              ).copyWith(color: Passeport.text),
                            ),
                            Text(
                              'How many times you repeat a new word before Marie may suggest the next one',
                              style: Passeport.mono(
                                10,
                              ).copyWith(color: Passeport.slateDim),
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

            if (kDebugMode) ...[
              _PasseportCard(
                child: GestureDetector(
                  onTap: () => AppRouter.push(
                    context,
                    (_) => const OrchestrationLabScreen(),
                  ),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.lab_flask,
                          size: 21,
                          color: Passeport.brass,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Orchestration Lab',
                                style: Passeport.body(
                                  14,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Preview personas, constraints, and competency paths',
                                style: Passeport.body(
                                  11.5,
                                ).copyWith(color: Passeport.slateDim),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.chevron_forward,
                          size: 16,
                          color: Passeport.slateDim,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _PasseportCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KickerText('Developer', color: Passeport.slateDim),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          'Force unlock premium',
                          style: Passeport.body(12.5),
                        ),
                        const Spacer(),
                        Switch.adaptive(
                          value: DevSubscriptionOverride.enabled,
                          activeThumbColor: Passeport.maroon,
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
                      'Bypasses subscription/invite-code checks for testing. '
                      'Debug builds only — compiled out entirely from release.',
                      style: Passeport.body(
                        11.5,
                      ).copyWith(color: Passeport.slateDim),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // --- AI tutor (OpenRouter) — developer build only ---
            if (kDebugMode)
              _PasseportCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KickerText(
                      'AI tutor (OpenRouter)',
                      color: Passeport.slateDim,
                    ),
                    const SizedBox(height: 10),
                    _SettingsRow(
                      label: 'Key status',
                      value: _openRouterKey.isEmpty ? 'Not set' : 'Configured',
                    ),
                    Divider(height: 1, color: Passeport.hairline),
                    const SizedBox(height: 10),
                    Text(
                      'Preferred model',
                      style: Passeport.body(
                        12.5,
                      ).copyWith(color: Passeport.slateDim),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Passeport.hairline),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _modelOverride,
                          isExpanded: true,
                          style: Passeport.body(
                            12.5,
                          ).copyWith(color: Passeport.text),
                          dropdownColor: Passeport.parchment,
                          icon: const Icon(
                            CupertinoIcons.chevron_down,
                            color: Passeport.maroon,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(
                                'Auto (fallback chain)',
                                style: Passeport.body(12.5),
                              ),
                            ),
                            ...availableModels.map(
                              (model) => DropdownMenuItem(
                                value: model,
                                child: Text(
                                  model,
                                  style: Passeport.mono(11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _modelOverride = v);
                            _saveString('openrouter_model_override', v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (kDebugMode) const SizedBox(height: 12),

            // --- Notetaker ---
            _PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Notetaker', color: Passeport.slateDim),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text('Floating notetaker', style: Passeport.body(12.5)),
                      const Spacer(),
                      Switch.adaptive(
                        value: ref.read(notetakerStateProvider).isEnabled,
                        activeThumbColor: Passeport.maroon,
                        onChanged: (v) {
                          setState(
                            () => ref.read(notetakerStateProvider).isEnabled = v,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Shows a draggable note bubble during lessons so you can '
                    'jot things down while listening or writing.',
                    style: Passeport.body(
                      11,
                    ).copyWith(color: Passeport.slateDim),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Access', color: Passeport.slateDim),
                  const SizedBox(height: 4),
                  _SettingsRow(
                    label: 'Founding pass',
                    value: _entitlementLabel(_access.entitlement.status),
                  ),
                  Divider(height: 1, color: Passeport.hairline),
                  _SettingsRow(
                    label: 'Tracked speaking today',
                    value:
                        '${(_access.remainingSeconds / 60).ceil()} min remaining',
                  ),
                  Divider(height: 1, color: Passeport.hairline),
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

            // --- Invite a friend (referral bonus minutes) ---
            _PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Invite a friend', color: Passeport.slateDim),
                  const SizedBox(height: 4),
                  Text(
                    'Share your code. When a friend redeems it, you both get '
                    '120 bonus minutes.',
                    style: Passeport.body(
                      11,
                    ).copyWith(color: Passeport.slateDim),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _referralStats == null ? null : _copyReferralCode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Passeport.parchmentDim,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _referralStats?.code ?? 'Loading…',
                              style: Passeport.mono(
                                16,
                                weight: FontWeight.w700,
                              ).copyWith(color: Passeport.maroon),
                            ),
                          ),
                          const Icon(
                            CupertinoIcons.doc_on_doc,
                            size: 16,
                            color: Passeport.slateDim,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SettingsRow(
                    label: 'Friends redeemed',
                    value: _referralStats == null
                        ? '—'
                        : '${_referralStats!.successfulRedemptions} of ${_referralStats!.maxRedemptions}',
                  ),
                  Divider(height: 1, color: Passeport.hairline),
                  _SettingsRow(
                    label: 'Bonus balance',
                    value: '${(_bonusSecondsBalance / 60).floor()} min',
                  ),
                  Divider(height: 16, color: Passeport.hairline),
                  Text(
                    'Have an invite code?',
                    style: Passeport.body(
                      12.5,
                    ).copyWith(color: Passeport.slateDim),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _redeemController,
                          textCapitalization: TextCapitalization.characters,
                          style: Passeport.mono(14),
                          decoration: InputDecoration(
                            hintText: 'e.g. AB12CD',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _redeeming ? null : _redeemCode,
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Passeport.maroon,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _redeeming
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Redeem',
                                  style: Passeport.body(
                                    13,
                                    weight: FontWeight.w700,
                                  ).copyWith(color: Colors.white),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // --- Account ---
            _PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Account', color: Passeport.slateDim),
                  const SizedBox(height: 4),
                  _SettingsRow(
                    label: 'Signed in as',
                    value:
                        AuthService.shared.currentSession?.user.email ??
                        'Signed in',
                  ),
                  Divider(height: 1, color: Passeport.hairline),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _confirmSignOut,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Sign out',
                        style: Passeport.body(
                          13,
                          weight: FontWeight.w600,
                        ).copyWith(color: Passeport.danger),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: Passeport.hairline),
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
                                const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Passeport.danger,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Deleting account…',
                                  style: Passeport.body(
                                    13,
                                    weight: FontWeight.w600,
                                  ).copyWith(color: Passeport.danger),
                                ),
                              ],
                            )
                          : Text(
                              'Delete account',
                              style: Passeport.body(
                                13,
                                weight: FontWeight.w600,
                              ).copyWith(color: Passeport.danger),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // --- About & support ---
            _PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('ParleSprint', color: Passeport.slateDim),
                  const SizedBox(height: 4),
                  _SettingsRow(label: 'Version', value: '0.9 pilot'),
                  Divider(height: 1, color: Passeport.hairline),
                  _SettingsRow(
                    label: 'Feedback',
                    value: 'thoufeek@agiventures.ca',
                  ),
                  Divider(height: 1, color: Passeport.hairline),
                  _LegalLinkRow(
                    label: 'Privacy Policy',
                    url: 'https://parlesprint.com/privacy',
                  ),
                  Divider(height: 1, color: Passeport.hairline),
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
          style: Passeport.body(12.5).copyWith(color: Passeport.slateDim),
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
                  color: isSelected ? Passeport.maroon : Passeport.parchmentDim,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  o.$2,
                  style: Passeport.body(
                    11.5,
                    weight: FontWeight.w600,
                  ).copyWith(color: isSelected ? Colors.white : Passeport.text),
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

class _PasseportCard extends StatelessWidget {
  const _PasseportCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Passeport.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: DesignTokens.cardShadow,
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
                  style: Passeport.body(
                    12.5,
                  ).copyWith(color: Passeport.text),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 14,
                color: Passeport.slateDim,
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
              style: Passeport.body(12.5).copyWith(color: Passeport.slateDim),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Passeport.body(
                12,
                weight: FontWeight.w600,
              ).copyWith(color: Passeport.text),
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
              ? Passeport.maroon.withValues(alpha: 0.1)
              : Passeport.slate.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? Passeport.maroon : Passeport.slate,
        ),
      ),
    );
  }
}
