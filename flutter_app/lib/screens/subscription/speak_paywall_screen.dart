import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/tokens.dart';
import '../../models/pilot_access.dart';
import '../../providers/database_provider.dart';
import '../../services/product_analytics.dart';
import '../../services/revenue_cat_service.dart';
import '../speak/speak_ui.dart';

const speakProEntitlementId = 'ParleSprint Pro';
const _termsUrl = 'https://parlesprint.com/terms';
const _privacyUrl = 'https://parlesprint.com/privacy';

class SpeakPaywallScreen extends ConsumerStatefulWidget {
  const SpeakPaywallScreen({super.key});

  @override
  ConsumerState<SpeakPaywallScreen> createState() => _SpeakPaywallScreenState();
}

class _SpeakPaywallScreenState extends ConsumerState<SpeakPaywallScreen> {
  Offerings? _offerings;
  Package? _selected;
  var _loading = true;
  var _purchasing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final offerings = await RevenueCatService.shared.fetchOfferings();
    if (!mounted) return;
    final packages = offerings?.current?.availablePackages ?? const <Package>[];
    setState(() {
      _offerings = offerings;
      _selected =
          offerings?.current?.annual ??
          (packages.isEmpty ? null : packages.first);
      _loading = false;
    });
  }

  Future<void> _purchase() async {
    final package = _selected;
    if (package == null || _purchasing) return;
    setState(() {
      _purchasing = true;
      _message = null;
    });
    final success = await RevenueCatService.shared.purchasePackage(package);
    if (!mounted) return;
    if (!success) {
      setState(() {
        _purchasing = false;
        _message = 'The purchase could not be completed. You can try again.';
      });
      return;
    }
    final info = await RevenueCatService.shared.activeEntitlementInfo(
      speakProEntitlementId,
    );
    if (info != null && mounted) {
      ref
          .read(pilotInfrastructureStoreProvider)
          .saveEntitlement(
            PilotEntitlement(
              productId: package.storeProduct.identifier,
              status: PilotEntitlementStatus.active,
              source: 'revenuecat_purchase',
              expiresAt: info.expirationDate == null
                  ? null
                  : DateTime.tryParse(info.expirationDate!),
              verifiedAt: DateTime.now(),
            ),
          );
      ref.invalidate(subscriptionGateServiceProvider);
      ref.invalidate(pilotAccessServiceProvider);
    }
    ProductAnalytics.capture(
      'subscription_purchased',
      properties: {'product_id': package.storeProduct.identifier},
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _restore() async {
    if (!RevenueCatService.shared.isConfigured) {
      setState(
        () => _message =
            'Restore is available after App Store billing is configured.',
      );
      return;
    }
    try {
      final info = await Purchases.restorePurchases();
      if (!mounted) return;
      if (info.entitlements.active.containsKey(speakProEntitlementId)) {
        ref.invalidate(subscriptionGateServiceProvider);
        ref.invalidate(pilotAccessServiceProvider);
        Navigator.of(context).pop(true);
      } else {
        setState(
          () => _message = 'No active ParleSprint subscription was found.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Restore could not be completed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpeakColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: SpeakColors.blue),
              )
            : Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(false),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: SpeakColors.inkSoft,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'Join learners who are already speaking French.',
                        textAlign: TextAlign.center,
                        style: DesignTokens.display(27),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Keep your course path, live roleplays, smart review and saved progress.',
                        textAlign: TextAlign.center,
                        style: DesignTokens.body(
                          14,
                        ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                      ),
                      const SizedBox(height: 22),
                      _benefit(
                        'Speak curriculum',
                        'A clear level-based route from A1 to B2',
                        Icons.route_rounded,
                      ),
                      _benefit(
                        'Roleplay and speaking',
                        'Practise the moments you actually need',
                        Icons.mic_rounded,
                      ),
                      _benefit(
                        'Smart review',
                        'Bring useful phrases back before you forget them',
                        Icons.bolt_rounded,
                      ),
                      const SizedBox(height: 16),
                      _plans(),
                      const SizedBox(height: 14),
                      if (_message != null)
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: DesignTokens.body(
                            12,
                          ).copyWith(color: SpeakColors.inkSoft),
                        ),
                      const SizedBox(height: 12),
                      SpeakPrimaryButton(
                        label: _purchasing ? 'Processing…' : _ctaLabel(),
                        icon: Icons.workspace_premium_rounded,
                        onTap: _purchasing ? () {} : _purchase,
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: _restore,
                          child: Text(
                            'Restore purchase',
                            style: DesignTokens.body(
                              12,
                              weight: FontWeight.w700,
                            ).copyWith(color: SpeakColors.blue),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Cancel anytime in your App Store account. By continuing, you agree to the Terms and Privacy Policy.',
                        textAlign: TextAlign.center,
                        style: DesignTokens.body(
                          10.5,
                        ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _legal('Terms of Use (EULA)', _termsUrl),
                          const Text('  ·  '),
                          _legal('Privacy', _privacyUrl),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _benefit(String title, String subtitle, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: SpeakColors.blueSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: SpeakColors.blue, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(13, weight: FontWeight.w700),
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
        ],
      ),
    );
  }

  Widget _plans() {
    final packages =
        _offerings?.current?.availablePackages ?? const <Package>[];
    if (packages.isEmpty) {
      return SpeakCard(
        child: Text(
          'Subscriptions are temporarily unavailable on this device. Please try again later or contact support.',
          style: DesignTokens.body(13).copyWith(color: SpeakColors.inkSoft),
        ),
      );
    }
    return Column(
      children: [
        for (final package in packages) ...[
          _plan(package),
          const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _plan(Package package) {
    final selected = package.identifier == _selected?.identifier;
    final annual = package.packageType == PackageType.annual;
    final trialSummary = _trialSummary(package);
    return GestureDetector(
      onTap: () => setState(() => _selected = package),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? SpeakColors.blue : SpeakColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? SpeakColors.blue : SpeakColors.line,
              size: 21,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    annual ? 'Premium · Best value' : 'Premium',
                    style: DesignTokens.body(14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    package.storeProduct.priceString,
                    style: DesignTokens.display(20).copyWith(
                      color: SpeakColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _billingTerms(package),
                    style: DesignTokens.body(
                      11.5,
                      weight: FontWeight.w600,
                    ).copyWith(color: SpeakColors.inkSoft),
                  ),
                  if (trialSummary != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      trialSummary,
                      style: DesignTokens.body(
                        10.5,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                  ],
                ],
              ),
            ),
            if (annual) ...[
              const SizedBox(width: 10),
              const SpeakPill(label: 'BEST VALUE', selected: true),
            ],
          ],
        ),
      ),
    );
  }

  String _ctaLabel() {
    final price = _selected?.storeProduct.priceString;
    return price == null ? 'Subscribe' : 'Subscribe for $price';
  }

  String _billingTerms(Package package) => switch (package.packageType) {
    PackageType.annual =>
      'Billed annually · auto-renews yearly · cancel anytime',
    PackageType.threeMonth =>
      'Billed every 3 months · auto-renews · cancel anytime',
    PackageType.monthly => 'Billed monthly · auto-renews · cancel anytime',
    PackageType.weekly => 'Billed weekly · auto-renews · cancel anytime',
    _ => 'Billed for each subscription period · cancel anytime',
  };

  String? _trialSummary(Package package) {
    final intro = package.storeProduct.introductoryPrice;
    if (intro == null) return null;
    final unit = switch (intro.periodUnit) {
      PeriodUnit.day => 'day',
      PeriodUnit.week => 'week',
      PeriodUnit.month => 'month',
      PeriodUnit.year => 'year',
      PeriodUnit.unknown => 'period',
    };
    final units = intro.periodNumberOfUnits * intro.cycles;
    final label = '$units $unit${units == 1 ? '' : 's'}';
    if (intro.price == 0) {
      return 'Includes $label free, then ${package.storeProduct.priceString} is billed.';
    }
    return 'Introductory price ${intro.priceString}, then ${package.storeProduct.priceString} is billed.';
  }

  Widget _legal(String label, String url) => GestureDetector(
    onTap: () => launchUrl(Uri.parse(url)),
    child: Text(
      label,
      style: DesignTokens.body(
        10.5,
        weight: FontWeight.w700,
      ).copyWith(color: SpeakColors.blue),
    ),
  );
}
