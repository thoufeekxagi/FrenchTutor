import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';
import '../../models/pilot_access.dart';
import '../../providers/database_provider.dart';
import '../../services/product_analytics.dart';
import '../../services/revenue_cat_service.dart';
import '../../services/subscription_invite_service.dart';
import '../../widgets/passeport_primary_button.dart';

/// The entitlement identifier configured in the RevenueCat dashboard (both
/// the 3-month and 12-month products are attached to this one entitlement).
/// Must match exactly what's named there.
const proEntitlementId = 'ParleSprint Pro';

/// Required on any subscription paywall per App Store Review Guideline
/// 3.1.2 — the terms/privacy links must be reachable from the purchase
/// screen itself, not just from the App Store product page.
const _termsUrl = 'https://parlesprint.com/terms';
const _privacyUrl = 'https://parlesprint.com/privacy';

/// Shown as a fullscreen dialog once a non-subscribed learner exhausts their
/// free missions (SubscriptionGateService.shouldShowPaywall), or before
/// starting locked content directly. Dismissible — this is a soft paywall,
/// not a hard lockout screen.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  Offerings? _offerings;
  Package? _selected;
  bool _loading = true;
  bool _purchasing = false;
  bool _showRedeem = false;
  bool _redeeming = false;
  String? _redeemMessage;
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final offerings = await RevenueCatService.shared.fetchOfferings();
    if (!mounted) return;
    final current = offerings?.current;
    setState(() {
      _offerings = offerings;
      _selected = current?.annual ?? current?.availablePackages.firstOrNull;
      _loading = false;
    });
  }

  Future<void> _purchase() async {
    final package = _selected;
    if (package == null || _purchasing) return;
    setState(() => _purchasing = true);
    final success = await RevenueCatService.shared.purchasePackage(package);
    if (!mounted) return;
    if (success) {
      // Optimistic local write so SubscriptionGateService (and the Settings
      // subscription card) reflect this immediately — the webhook will also
      // sync it to Supabase shortly, but that round-trip shouldn't be what
      // gates the UI or leaves "renews on / days left" blank right now.
      final activeInfo = await RevenueCatService.shared.activeEntitlementInfo(
        proEntitlementId,
      );
      if (activeInfo != null && mounted) {
        ref
            .read(pilotInfrastructureStoreProvider)
            .saveEntitlement(
              PilotEntitlement(
                productId: package.storeProduct.identifier,
                status: PilotEntitlementStatus.active,
                source: 'revenuecat_purchase',
                expiresAt: activeInfo.expirationDate == null
                    ? null
                    : DateTime.tryParse(activeInfo.expirationDate!),
                verifiedAt: DateTime.now(),
              ),
            );
        // The write above is a plain SQLite row — nothing about it tells
        // Riverpod anything changed. Every screen that gates on subscription
        // status (Practice tab, Keep Practising, Settings) must actually be
        // watching this provider for that invalidation to reach it; this is
        // the other half of that fix, not a substitute for it.
        ref.invalidate(subscriptionGateServiceProvider);
        ref.invalidate(pilotAccessServiceProvider);
      }
      ProductAnalytics.capture(
        'subscription_purchased',
        properties: {'product_id': package.storeProduct.identifier},
      );
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() => _purchasing = false);
    }
  }

  Future<void> _redeemCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _redeeming) return;
    setState(() {
      _redeeming = true;
      _redeemMessage = null;
    });
    final result = await SubscriptionInviteService.shared.redeem(code);
    if (!mounted) return;
    setState(() {
      _redeeming = false;
      _redeemMessage = switch (result.outcome) {
        InviteRedeemOutcome.success =>
          'Code applied. ${result.monthsGranted} month${result.monthsGranted == 1 ? '' : 's'} of full access added.',
        InviteRedeemOutcome.alreadyRedeemed => 'You already used this code.',
        InviteRedeemOutcome.codeInactive => 'This code is no longer active.',
        InviteRedeemOutcome.codeLimitReached =>
          'This code has reached its redemption limit.',
        InviteRedeemOutcome.invalidCode => 'That code isn\'t valid.',
        InviteRedeemOutcome.networkError =>
          'Couldn\'t reach the server. Try again.',
      };
    });
    if (result.outcome == InviteRedeemOutcome.success && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Full-bleed gradient backdrop behind a transparent Scaffold — same
    // pattern as auth_screen.dart/onboarding, so it never shrinks behind the
    // keyboard or shows a seam at the Scaffold's resizing edge.
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: DesignTokens.heroGradient),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Stack(
              children: [
                _loading ? _buildLoading() : _buildContent(),
                Positioned(
                  top: DesignTokens.space2,
                  right: DesignTokens.space2,
                  child: _CloseButton(
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white)),
    );
  }

  Widget _buildContent() {
    final packages = _offerings?.current?.availablePackages ?? const [];
    if (!RevenueCatService.shared.isConfigured || packages.isEmpty) {
      return _buildInviteOnlyFallback();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.space5,
        DesignTokens.space6 * 1.5,
        DesignTokens.space5,
        DesignTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(hasTrial: _ctaLabel().contains('Free')),
          const SizedBox(height: DesignTokens.space5),
          const _BenefitsList(),
          const SizedBox(height: DesignTokens.space6),
          Container(
            padding: const EdgeInsets.all(DesignTokens.space5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [DesignTokens.surface, DesignTokens.primarySoft],
              ),
              borderRadius: BorderRadius.circular(DesignTokens.radiusCard * 1.25),
              boxShadow: DesignTokens.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final package in packages) ...[
                  _PlanCard(
                    package: package,
                    selected: package.identifier == _selected?.identifier,
                    highlight: package.packageType == PackageType.annual,
                    onTap: () => setState(() => _selected = package),
                  ),
                  const SizedBox(height: DesignTokens.space3),
                ],
                if (packages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: DesignTokens.space2,
                    ),
                    child: Text(
                      // Real, honest urgency — no fabricated "was" price.
                      // This genuinely is today's price, and it genuinely
                      // won't stay this low forever.
                      'These are our launch prices. They go up as we add '
                      'more features.',
                      style: Passeport.body(
                        12,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                  ),
                const SizedBox(height: DesignTokens.space1),
                PasseportPrimaryButton(
                  label: _purchasing ? 'Processing…' : _ctaLabel(),
                  onPressed: _purchasing ? null : _purchase,
                ),
                const SizedBox(height: DesignTokens.space3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_shield_fill,
                      size: 14,
                      color: DesignTokens.mutedDim,
                    ),
                    const SizedBox(width: DesignTokens.space1),
                    Text(
                      'Secure via App Store · Cancel anytime',
                      style: Passeport.body(12).copyWith(
                        color: DesignTokens.mutedDim,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.space3),
                _buildRedeemSection(),
              ],
            ),
          ),
          const SizedBox(height: DesignTokens.space4),
          const _LegalLinks(),
        ],
      ),
    );
  }

  Widget _buildInviteOnlyFallback() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.space5,
        DesignTokens.space6 * 1.5,
        DesignTokens.space5,
        DesignTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          const SizedBox(height: DesignTokens.space6),
          Container(
            padding: const EdgeInsets.all(DesignTokens.space5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [DesignTokens.surface, DesignTokens.primarySoft],
              ),
              borderRadius: BorderRadius.circular(DesignTokens.radiusCard * 1.25),
              boxShadow: DesignTokens.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Subscriptions aren\'t available on this device yet. If you have an invite code, you can redeem it below.',
                  style: Passeport.body(15).copyWith(color: DesignTokens.mutedDim),
                ),
                const SizedBox(height: DesignTokens.space5),
                _buildRedeemSection(forceOpen: true),
              ],
            ),
          ),
          const SizedBox(height: DesignTokens.space4),
          const _LegalLinks(),
        ],
      ),
    );
  }

  String _ctaLabel() {
    final intro = _selected?.storeProduct.introductoryPrice;
    if (intro != null && intro.price == 0) {
      return 'Subscribe & Try 7 Days Free';
    }
    return 'Subscribe Now';
  }

  Widget _buildRedeemSection({bool forceOpen = false}) {
    final open = forceOpen || _showRedeem;
    if (!open) {
      return Center(
        child: TextButton(
          onPressed: () => setState(() => _showRedeem = true),
          child: Text(
            'Have an invite code?',
            style: Passeport.body(14, weight: FontWeight.w600).copyWith(
              color: DesignTokens.primary,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Invite code',
          style: Passeport.body(13, weight: FontWeight.w600).copyWith(
            color: DesignTokens.mutedDim,
          ),
        ),
        const SizedBox(height: DesignTokens.space2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                style: Passeport.mono(14),
                decoration: InputDecoration(
                  hintText: 'e.g. AB12CD',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.space3,
                    vertical: 14,
                  ),
                  filled: true,
                  fillColor: DesignTokens.canvasDim,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusSmall,
                    ),
                    borderSide: BorderSide(color: DesignTokens.hairline),
                  ),
                ),
              ),
            ),
            const SizedBox(width: DesignTokens.space2),
            GestureDetector(
              onTap: _redeeming ? null : _redeemCode,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.space4,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DesignTokens.primary,
                  borderRadius: BorderRadius.circular(
                    DesignTokens.radiusSmall,
                  ),
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
                        'Apply',
                        style: Passeport.body(
                          13,
                          weight: FontWeight.w700,
                        ).copyWith(color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
        if (_redeemMessage != null) ...[
          const SizedBox(height: DesignTokens.space2),
          Text(
            _redeemMessage!,
            style: Passeport.body(13).copyWith(color: DesignTokens.mutedDim),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.hasTrial = false});

  /// Whether the currently selected/available plan actually carries a free
  /// introductory offer — only known from RevenueCat's `introductoryPrice`,
  /// never assumed. Claiming a trial that isn't configured for the selected
  /// plan is a false statement on a paywall (App Store Guideline 3.1.2 risk),
  /// so the subtitle below must match what `_ctaLabel()`/`_PlanCard` show,
  /// not a fixed marketing line.
  final bool hasTrial;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Full access to\nParleSprint',
          style: Passeport.display(30).copyWith(color: Colors.white),
        ),
        const SizedBox(height: DesignTokens.space2),
        Text(
          hasTrial
              ? 'Start your 7-day free trial. Cancel anytime.'
              : 'Unlock every mission, lab, and speaking session.',
          style: Passeport.body(15).copyWith(
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

class _BenefitsList extends StatelessWidget {
  const _BenefitsList();

  static const _benefits = [
    (CupertinoIcons.mic_fill, 'Unlimited daily missions and speaking practice'),
    (CupertinoIcons.book_fill, 'Full grammar, listening, and reading library'),
    (CupertinoIcons.repeat, 'Personalized review across every session'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (icon, label) in _benefits)
          Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.space3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: Colors.white),
                ),
                const SizedBox(width: DesignTokens.space3),
                Expanded(
                  child: Text(
                    label,
                    style: Passeport.body(15).copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.package,
    required this.selected,
    required this.highlight,
    required this.onTap,
  });

  final Package package;
  final bool selected;
  final bool highlight;
  final VoidCallback onTap;

  String get _title => switch (package.packageType) {
    PackageType.annual => '12-Month Plan',
    PackageType.threeMonth => '3-Month Plan',
    _ => package.storeProduct.title,
  };

  /// Explicit subscription length + auto-renewal terms, spelled out in
  /// plain words next to the price — not just implied by the plan name.
  /// Required content per App Store Review Guideline 3.1.2; a previous
  /// submission was rejected for omitting this.
  String get _termsLine => switch (package.packageType) {
    PackageType.annual => '1 Year subscription. Billed annually. Cancel anytime.',
    PackageType.threeMonth =>
      '3 Month subscription. Billed every 3 months. Cancel anytime.',
    _ => 'Auto-renewing subscription. Cancel anytime.',
  };

  @override
  Widget build(BuildContext context) {
    final intro = package.storeProduct.introductoryPrice;
    final hasTrial = intro != null && intro.price == 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? DesignTokens.primarySoft.withValues(alpha: 0.35) : DesignTokens.canvasDim,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          border: Border.all(
            color: selected ? DesignTokens.primary : DesignTokens.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(DesignTokens.space4),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              color: selected ? DesignTokens.primary : DesignTokens.muted,
              size: 24,
            ),
            const SizedBox(width: DesignTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _title,
                        style: Passeport.body(16, weight: FontWeight.w600),
                      ),
                      const SizedBox(width: DesignTokens.space2),
                      const _Badge(label: 'Launch price'),
                      if (highlight) ...[
                        const SizedBox(width: DesignTokens.space2),
                        const _Badge(label: 'Best value'),
                      ],
                    ],
                  ),
                  const SizedBox(height: DesignTokens.space1),
                  if (hasTrial)
                    Text(
                      '7 days free, then ${package.storeProduct.priceString}',
                      style: Passeport.body(14).copyWith(
                        color: DesignTokens.mutedDim,
                      ),
                    )
                  else
                    Text(
                      package.storeProduct.priceString,
                      style: Passeport.body(14, weight: FontWeight.w600).copyWith(
                        color: DesignTokens.primaryDeep,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    _termsLine,
                    style: Passeport.body(
                      11.5,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Passeport.body(11, weight: FontWeight.w700).copyWith(
          color: DesignTokens.primaryDeep,
        ),
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final style = Passeport.body(12).copyWith(
      color: Colors.white.withValues(alpha: 0.7),
      decoration: TextDecoration.underline,
      decorationColor: Colors.white.withValues(alpha: 0.4),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => _open(_termsUrl),
          child: Text('Terms of Service', style: style),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space2),
          child: Text(
            '·',
            style: Passeport.body(12).copyWith(color: Colors.white.withValues(alpha: 0.5)),
          ),
        ),
        GestureDetector(
          onTap: () => _open(_privacyUrl),
          child: Text('Privacy Policy', style: style),
        ),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            CupertinoIcons.xmark,
            size: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
