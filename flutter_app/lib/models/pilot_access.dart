const parlesprintProEntitlementId = 'ParleSprint Pro';

enum PilotEntitlementStatus {
  localPreview,
  active,
  grace,
  inactive,
  verificationUnavailable,
}

class PilotEntitlement {
  const PilotEntitlement({
    required this.productId,
    required this.status,
    required this.source,
    this.expiresAt,
    this.verifiedAt,
  });

  final String productId;
  final PilotEntitlementStatus status;
  final String source;
  final DateTime? expiresAt;
  final DateTime? verifiedAt;

  /// Whether [expiresAt] (if set) has passed. A stored `active`/`grace`
  /// status is never re-checked against wall-clock time on its own — a
  /// sandbox purchase (or a real one) can expire long after the row was
  /// written, and nothing else revisits it until the next sign-in triggers
  /// a fresh server hydration. Callers deciding live access must gate on
  /// this, not on `status` alone.
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get grantsAccess =>
      !isExpired &&
      !_isLegacyCodeGrant &&
      (status == PilotEntitlementStatus.localPreview ||
          status == PilotEntitlementStatus.active ||
          status == PilotEntitlementStatus.grace);

  /// Historical invite-code rows are retained for audit/future migration,
  /// but can never unlock the App Store build.
  bool get _isLegacyCodeGrant =>
      productId.trim().toLowerCase().startsWith('invite:');

  /// Narrower than [grantsAccess]: true only for a real, unexpired paid
  /// subscription; excludes `localPreview` (the no-entitlement-row default).
  /// What
  /// [SubscriptionGateService] and the daily AI-minutes tier should check.
  bool get isPaidActive =>
      !isExpired &&
      !_isLegacyCodeGrant &&
      (status == PilotEntitlementStatus.active ||
          status == PilotEntitlementStatus.grace);
}

class PilotAccessSnapshot {
  const PilotAccessSnapshot({
    required this.entitlement,
    required this.dailyLimitSeconds,
    required this.usedSeconds,
    required this.serverAuthoritative,
  });

  final PilotEntitlement entitlement;
  final int dailyLimitSeconds;
  final int usedSeconds;
  final bool serverAuthoritative;

  int get remainingSeconds =>
      (dailyLimitSeconds - usedSeconds).clamp(0, dailyLimitSeconds);
  bool get canStartAiSession =>
      entitlement.grantsAccess && remainingSeconds > 0;
}
