/// Screen: TCF Canada subscription offer. Key prefix: paywall.
/// User arrived to choose premium access from a feature gate or settings.
/// They must understand the course value, available plans, and total price.
/// Primary action: purchase the selected App Store subscription.
/// Secondary actions: choose a plan, restore, return, or open legal links.
/// Success state: the active entitlement is saved and this screen closes.
/// Must not contain: non-TCF goals, unsupported outcomes, or hard-coded prices.
/// States: loading, available, unavailable, purchase error, restore result.
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
import '../../v3/ui/v3_ui.dart';

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
    // This screen is often kept alive while the app appearance changes.
    // Reading the inherited theme makes the stateful paywall rebuild and
    // re-resolve its semantic colors immediately.
    Theme.of(context);
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: _loading
            ? Center(
                child: CircularProgressIndicator(color: DesignTokens.primary),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: DesignTokens.contentMaxWidth,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          key: const ValueKey('paywall.back'),
                          tooltip: 'Back',
                          onPressed: () {
                            ProductAnalytics.capture(
                              'paywall_closed',
                              properties: {'source': widget.source},
                            );
                            Navigator.of(context).pop(false);
                          },
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ONE CLEAR COURSE',
                        textAlign: TextAlign.center,
                        style: DesignTokens.label(11).copyWith(
                          color: DesignTokens.primary,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'One goal: TCF Canada.',
                        textAlign: TextAlign.center,
                        style: DesignTokens.display(29),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'A focused French course from A1 to B2.',
                        textAlign: TextAlign.center,
                        style: DesignTokens.body(
                          14,
                        ).copyWith(color: DesignTokens.muted, height: 1.35),
                      ),
                      const SizedBox(height: 22),
                      _benefit(
                        'Guided French course from A1 to B2',
                        Icons.route_rounded,
                      ),
                      _benefit('Listening practice', Icons.headphones_rounded),
                      _benefit(
                        'Speaking with your tutor',
                        Icons.mic_none_rounded,
                      ),
                      _benefit('Reading practice', Icons.menu_book_outlined),
                      _benefit('Writing practice', Icons.edit_note_rounded),
                      _benefit(
                        'Vocabulary review as you learn',
                        Icons.refresh_rounded,
                      ),
                      const SizedBox(height: 12),
                      _plans(),
                      if (_message != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: DesignTokens.body(
                            12,
                          ).copyWith(color: DesignTokens.inkSoft),
                        ),
                      ],
                      const SizedBox(height: 12),
                      V3Button(
                        key: const ValueKey('paywall.purchase.primary'),
                        label: _purchasing ? 'Processing…' : _ctaLabel(),
                        onTap: _purchasing || _selected == null
                            ? null
                            : _purchase,
                        loading: _purchasing,
                        trailingArrow: false,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _selected == null
                            ? 'Plans are currently unavailable.'
                            : _bottomTerms(_selected!),
                        textAlign: TextAlign.center,
                        style: DesignTokens.body(
                          11,
                        ).copyWith(color: DesignTokens.muted, height: 1.35),
                      ),
                      Center(
                        child: TextButton(
                          key: const ValueKey('paywall.restore'),
                          onPressed: _restore,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          child: Text(
                            'Restore purchase',
                            style: DesignTokens.body(
                              12,
                              weight: FontWeight.w700,
                            ).copyWith(color: DesignTokens.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      const SubscriptionMarketingSections(),
                      if (_selected != null) ...[
                        const SizedBox(height: 24),
                        SubscriptionBottomOffer(
                          price: _selected!.storeProduct.priceString,
                          terms: _bottomTerms(_selected!),
                          ctaLabel: _ctaLabel(),
                          loading: _purchasing,
                          onTap: _purchasing ? null : _purchase,
                        ),
                      ],
                      Text(
                        'Subscriptions renew automatically and can be cancelled in your App Store account.',
                        textAlign: TextAlign.center,
                        style: DesignTokens.body(
                          10.5,
                        ).copyWith(color: DesignTokens.muted, height: 1.35),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 2,
                        children: [
                          _legal(
                            'Terms of Use (EULA)',
                            _termsUrl,
                            'paywall.legal.terms',
                          ),
                          const Text('  ·  '),
                          _legal(
                            'Privacy',
                            _privacyUrl,
                            'paywall.legal.privacy',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _benefit(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DesignTokens.primarySoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: DesignTokens.primary, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: DesignTokens.body(14.5, weight: FontWeight.w700),
            ),
          ),
          Icon(Icons.check_rounded, color: DesignTokens.success, size: 19),
        ],
      ),
    );
  }

  Widget _plans() {
    final packages =
        _offerings?.current?.availablePackages ?? const <Package>[];
    if (packages.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          border: Border.all(color: DesignTokens.hairline),
        ),
        child: Text(
          'Subscriptions are temporarily unavailable on this device. Please try again later or contact support.',
          style: DesignTokens.body(13).copyWith(color: DesignTokens.inkSoft),
        ),
      );
    }
    return Column(
      children: [
        for (final package in packages) ...[
          _plan(package),
          const SizedBox(height: 7),
        ],
      ],
    );
  }

  Widget _plan(Package package) {
    final selected = package.identifier == _selected?.identifier;
    final annual = package.packageType == PackageType.annual;
    final trialSummary = _trialSummary(package);
    return V3Pressable(
      key: ValueKey('paywall.plan.${package.identifier}'),
      label:
          '${_planTitle(package)}, ${package.storeProduct.priceString}, '
          '${_billingTerms(package)}${selected ? ', selected' : ''}',
      selected: selected,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          border: Border.all(
            color: selected ? DesignTokens.primary : DesignTokens.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? DesignTokens.primary : DesignTokens.muted,
              size: 21,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _planTitle(package),
                    style: DesignTokens.body(14.5, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    package.storeProduct.priceString,
                    style: DesignTokens.display(
                      21,
                    ).copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _billingTerms(package),
                    style: DesignTokens.body(
                      11.5,
                      weight: FontWeight.w600,
                    ).copyWith(color: DesignTokens.inkSoft),
                  ),
                  if (trialSummary != null) ...[
                    const SizedBox(height: 1),
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
                                  11.5,
                                ).copyWith(color: DesignTokens.inkSoft),
                              ),
                            ),
                          )
                        : Text(
                            trialSummary,
                            style: DesignTokens.body(11.5).copyWith(
                              color: DesignTokens.inkSoft,
                              height: 1.3,
                            ),
                          ),
                  ],
                ],
              ),
            ),
            if (annual) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: DesignTokens.primarySoft,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
                ),
                child: Text(
                  'BEST VALUE',
                  style: DesignTokens.label(
                    10,
                    weight: FontWeight.w800,
                  ).copyWith(color: DesignTokens.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _ctaLabel() {
    final price = _selected?.storeProduct.priceString;
    if (price == null) return 'Continue';
    final period = switch (_selected?.packageType) {
      PackageType.annual => 'year',
      PackageType.threeMonth => '3 months',
      PackageType.monthly => 'month',
      PackageType.weekly => 'week',
      _ => null,
    };
    return period == null ? 'Continue · $price' : 'Continue · $price / $period';
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

  Widget _legal(String label, String url, String key) => TextButton(
    key: ValueKey(key),
    onPressed: () => launchUrl(Uri.parse(url)),
    style: TextButton.styleFrom(
      minimumSize: const Size(44, 48),
      padding: const EdgeInsets.symmetric(horizontal: 5),
    ),
    child: Text(
      label,
      style: DesignTokens.body(
        10.5,
        weight: FontWeight.w700,
      ).copyWith(color: DesignTokens.primary),
    ),
  );
}
