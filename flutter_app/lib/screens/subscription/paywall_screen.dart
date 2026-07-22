import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../config/theme.dart';
import '../../models/pilot_access.dart';
import '../../providers/database_provider.dart';
import '../../services/revenue_cat_service.dart';
import '../../services/subscription_invite_service.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/passeport_primary_button.dart';

/// The entitlement identifier configured in the RevenueCat dashboard (both
/// the 3-month and 12-month products are attached to this one entitlement).
/// Must match exactly what's named there.
const proEntitlementId = 'ParleSprint Pro';

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
      // Optimistic local write so SubscriptionGateService reflects this
      // immediately — the webhook will also sync it to Supabase shortly,
      // but that round-trip shouldn't be what gates the UI right now.
      final hasEntitlement = await RevenueCatService.shared
          .hasActiveEntitlement(proEntitlementId);
      if (hasEntitlement && mounted) {
        ref
            .read(pilotInfrastructureStoreProvider)
            .saveEntitlement(
              PilotEntitlement(
                productId: package.storeProduct.identifier,
                status: PilotEntitlementStatus.active,
                source: 'revenuecat_purchase',
                verifiedAt: DateTime.now(),
              ),
            );
      }
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
          'Code applied — ${result.monthsGranted} month${result.monthsGranted == 1 ? '' : 's'} of full access added.',
        InviteRedeemOutcome.alreadyRedeemed => 'You already used this code.',
        InviteRedeemOutcome.codeInactive => 'This code is no longer active.',
        InviteRedeemOutcome.codeLimitReached =>
          'This code has reached its redemption limit.',
        InviteRedeemOutcome.invalidCode => 'That code isn\'t valid.',
        InviteRedeemOutcome.networkError =>
          'Couldn\'t reach the server — try again.',
      };
    });
    if (result.outcome == InviteRedeemOutcome.success && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
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
    );
  }

  Widget _buildLoading() {
    return const Center(child: CircularProgressIndicator());
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
          _Header(),
          const SizedBox(height: DesignTokens.space6),
          const _BenefitsList(),
          const SizedBox(height: DesignTokens.space6),
          for (final package in packages) ...[
            _PlanCard(
              package: package,
              selected: package.identifier == _selected?.identifier,
              highlight: package.packageType == PackageType.annual,
              onTap: () => setState(() => _selected = package),
            ),
            const SizedBox(height: DesignTokens.space3),
          ],
          const SizedBox(height: DesignTokens.space3),
          PasseportPrimaryButton(
            label: _purchasing ? 'Processing…' : _ctaLabel(),
            onPressed: _purchasing ? null : _purchase,
          ),
          const SizedBox(height: DesignTokens.space4),
          _buildRedeemSection(),
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
          _Header(),
          const SizedBox(height: DesignTokens.space6),
          Text(
            'Subscriptions aren\'t available on this device yet. If you have an invite code, you can redeem it below.',
            style: Passeport.body(15).copyWith(color: DesignTokens.mutedDim),
          ),
          const SizedBox(height: DesignTokens.space5),
          _buildRedeemSection(forceOpen: true),
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
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'Enter code',
                  filled: true,
                  fillColor: DesignTokens.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: DesignTokens.hairline),
                  ),
                ),
              ),
            ),
            const SizedBox(width: DesignTokens.space2),
            TextButton(
              onPressed: _redeeming ? null : _redeemCode,
              child: Text(_redeeming ? '…' : 'Apply'),
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
  @override
  Widget build(BuildContext context) {
    return Text(
      'Full access to ParleSprint',
      style: Passeport.display(28),
    );
  }
}

class _BenefitsList extends StatelessWidget {
  const _BenefitsList();

  static const _benefits = [
    'Unlimited daily missions and speaking practice',
    'Full grammar, listening, and reading library',
    'Personalized review across every session',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final benefit in _benefits)
          Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.space2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  size: 20,
                  color: DesignTokens.success,
                ),
                const SizedBox(width: DesignTokens.space3),
                Expanded(
                  child: Text(benefit, style: Passeport.body(15)),
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

  @override
  Widget build(BuildContext context) {
    final intro = package.storeProduct.introductoryPrice;
    final hasTrial = intro != null && intro.price == 0;
    return GestureDetector(
      onTap: onTap,
      child: PasseportCard(
        padding: DesignTokens.space4,
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
                      if (highlight) ...[
                        const SizedBox(width: DesignTokens.space2),
                        _Badge(label: 'Best value'),
                      ],
                    ],
                  ),
                  const SizedBox(height: DesignTokens.space1),
                  Text(
                    hasTrial
                        ? '7 days free, then ${package.storeProduct.priceString}'
                        : package.storeProduct.priceString,
                    style: Passeport.body(14).copyWith(
                      color: DesignTokens.mutedDim,
                    ),
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
            color: DesignTokens.ink.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: Icon(
            CupertinoIcons.xmark,
            size: 16,
            color: DesignTokens.mutedDim,
          ),
        ),
      ),
    );
  }
}
