import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/tokens.dart';
import '../../models/pilot_access.dart';
import '../../providers/database_provider.dart';
import '../../services/product_analytics.dart';
import '../../services/revenue_cat_service.dart';
import '../../widgets/subscription_marketing_sections.dart';
import '../speak/speak_ui.dart';

const _termsUrl = 'https://parlesprint.com/terms';
const _privacyUrl = 'https://parlesprint.com/privacy';

class SpeakPaywallScreen extends ConsumerStatefulWidget {
  const SpeakPaywallScreen({super.key, this.source = 'unknown'});

  /// The measured entry point, such as `settings`, `daily_mission`, or
  /// `exam_readiness`. This changes analytics only; all entry points share
  /// the same Apple-compliant purchase surface.
  final String source;

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
    ProductAnalytics.capture(
      'paywall_shown',
      properties: {'source': widget.source},
    );
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
    ProductAnalytics.capture(
      'purchase_started',
      properties: {
        'source': widget.source,
        'product_id': package.storeProduct.identifier,
      },
    );
    setState(() {
      _purchasing = true;
      _message = null;
    });
    final purchaseInfo = await RevenueCatService.shared.purchasePackage(
      package,
    );
    if (!mounted) return;
    if (purchaseInfo == null) {
      ProductAnalytics.capture(
        'purchase_failed',
        properties: {
          'source': widget.source,
          'product_id': package.storeProduct.identifier,
        },
      );
      setState(() {
        _purchasing = false;
        _message = 'The purchase could not be completed. You can try again.';
      });
      return;
    }
    final info = await RevenueCatService.shared.activeEntitlementInfo(
      parlesprintProEntitlementId,
    );
    if (info == null) {
      // A StoreKit transaction can complete even when the RevenueCat product
      // is not attached to the configured entitlement. Do not dismiss the
      // paywall in that state: doing so makes the user look purchased while
      // every premium gate correctly remains locked.
      ProductAnalytics.capture(
        'purchase_entitlement_missing',
        properties: {
          'source': widget.source,
          'product_id': package.storeProduct.identifier,
        },
      );
      setState(() {
        _purchasing = false;
        _message =
            'The purchase completed, but access is still syncing. Tap '
            'Restore Purchase or try again in a moment.';
      });
      return;
    }
    if (mounted) {
      ref
          .read(pilotInfrastructureStoreProvider)
          .saveEntitlement(
            PilotEntitlement(
              productId: info.productIdentifier,
              status: PilotEntitlementStatus.active,
              source: 'revenuecat_purchase',
              expiresAt: info.expirationDate == null
                  ? null
                  : DateTime.tryParse(info.expirationDate!),
              verifiedAt: DateTime.now().toUtc(),
            ),
          );
      ref.invalidate(subscriptionGateServiceProvider);
      ref.invalidate(pilotAccessServiceProvider);
    }
    ProductAnalytics.capture(
      'subscription_purchased',
      properties: {
        'source': widget.source,
        'product_id': package.storeProduct.identifier,
      },
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
      if (info.entitlements.active.containsKey(parlesprintProEntitlementId)) {
        final entitlement =
            info.entitlements.active[parlesprintProEntitlementId];
        if (entitlement != null) {
          ref
              .read(pilotInfrastructureStoreProvider)
              .saveEntitlement(
                PilotEntitlement(
                  productId: entitlement.productIdentifier,
                  status: PilotEntitlementStatus.active,
                  source: 'revenuecat_restore',
                  expiresAt: entitlement.expirationDate == null
                      ? null
                      : DateTime.tryParse(entitlement.expirationDate!),
                  verifiedAt: DateTime.now(),
                ),
              );
        }
        ProductAnalytics.capture(
          'purchase_restored',
          properties: {'source': widget.source},
        );
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
        child: Stack(
          children: [
            _loading
                ? const Center(
                    child: CircularProgressIndicator(color: SpeakColors.blue),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      const SizedBox(height: 54),
                      Text(
                        'Unlock full French access',
                        textAlign: TextAlign.center,
                        style: DesignTokens.display(34),
                      ),
                      const SizedBox(height: 28),
                      _benefit(
                        'A course shaped around you',
                        Icons.route_rounded,
                      ),
                      _benefit(
                        'Live speaking with your tutor',
                        Icons.mic_rounded,
                      ),
                      _benefit(
                        'Reading and listening that teach',
                        Icons.menu_book_rounded,
                      ),
                      _benefit(
                        'Writing and grammar feedback',
                        Icons.edit_note_rounded,
                      ),
                      _benefit('TEF and TCF practice', Icons.verified_rounded),
                      _benefit(
                        'Smart review that remembers',
                        Icons.bolt_rounded,
                      ),
                      const SizedBox(height: 14),
                      _plans(),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 26),
                      const SubscriptionMarketingSections(),
                      const SizedBox(height: 24),
                      SubscriptionBottomOffer(
                        price: _bottomPriceLine(),
                        terms: _selected == null
                            ? 'Select a subscription above to continue.'
                            : _bottomTerms(_selected!),
                        ctaLabel: _ctaLabel(),
                        loading: _purchasing,
                        onTap: _purchasing || _selected == null
                            ? null
                            : _purchase,
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
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    ProductAnalytics.capture(
                      'paywall_closed',
                      properties: {'source': widget.source},
                    );
                    Navigator.of(context).pop(false);
                  },
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: SpeakColors.line),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: DesignTokens.ink,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _benefit(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: SpeakColors.blueSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: SpeakColors.blue, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: DesignTokens.body(16, weight: FontWeight.w700),
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
      onTap: () {
        setState(() => _selected = package);
        ProductAnalytics.capture(
          'paywall_plan_selected',
          properties: {
            'source': widget.source,
            'product_id': package.storeProduct.identifier,
          },
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
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
                    _planTitle(package),
                    style: DesignTokens.body(16, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    package.storeProduct.priceString,
                    style: DesignTokens.display(23).copyWith(
                      color: SpeakColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _billingTerms(package),
                    style: DesignTokens.body(
                      13,
                      weight: FontWeight.w600,
                    ).copyWith(color: SpeakColors.inkSoft),
                  ),
                  if (trialSummary != null) ...[
                    const SizedBox(height: 2),
                    annual
                        ? SizedBox(
                            width: double.infinity,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                trialSummary,
                                maxLines: 1,
                                style: DesignTokens.body(
                                  13,
                                ).copyWith(color: SpeakColors.inkSoft),
                              ),
                            ),
                          )
                        : Text(
                            trialSummary,
                            style: DesignTokens.body(
                              13,
                            ).copyWith(color: SpeakColors.inkSoft, height: 1.3),
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

  String _bottomPriceLine() {
    final selected = _selected;
    if (selected == null) return 'Choose a plan';
    return selected.storeProduct.priceString;
  }

  String _bottomTerms(Package package) {
    final trial = _trialSummary(package);
    return '${_billingTerms(package)}.${trial == null ? '' : ' $trial'}';
  }

  String _planTitle(Package package) => switch (package.packageType) {
    PackageType.annual => 'Annual plan',
    PackageType.threeMonth => '3-month plan',
    PackageType.monthly => 'Monthly plan',
    PackageType.weekly => 'Weekly plan',
    _ => package.storeProduct.title,
  };

  String _periodUnitLabel(PeriodUnit unit) => switch (unit) {
    PeriodUnit.day => 'day',
    PeriodUnit.week => 'week',
    PeriodUnit.month => 'month',
    PeriodUnit.year => 'year',
    PeriodUnit.unknown => 'period',
  };

  String _billingTerms(Package package) => switch (package.packageType) {
    PackageType.annual => 'Billed yearly · auto-renews · cancel anytime',
    PackageType.threeMonth =>
      'Billed every 3 months · auto-renews · cancel anytime',
    PackageType.monthly => 'Billed monthly · auto-renews · cancel anytime',
    PackageType.weekly => 'Billed weekly · auto-renews · cancel anytime',
    _ => 'Auto-renews · cancel anytime',
  };

  String? _trialSummary(Package package) {
    final intro = package.storeProduct.introductoryPrice;
    if (intro == null) return null;
    final unit = _periodUnitLabel(intro.periodUnit);
    final units = intro.periodNumberOfUnits * intro.cycles;
    final label = '$units $unit${units == 1 ? '' : 's'}';
    if (intro.price == 0) {
      return '$label free, then ${package.storeProduct.priceString} '
          '${_renewalLabel(package)}';
    }
    return 'Intro price ${intro.priceString} for $label, then '
        '${package.storeProduct.priceString} ${_renewalLabel(package)}';
  }

  String _renewalLabel(Package package) => switch (package.packageType) {
    PackageType.annual => 'billed yearly',
    PackageType.threeMonth => 'billed every 3 months',
    PackageType.monthly => 'billed monthly',
    PackageType.weekly => 'billed weekly',
    _ => 'billed each period',
  };

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
