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

  bool get grantsAccess =>
      status == PilotEntitlementStatus.localPreview ||
      status == PilotEntitlementStatus.active ||
      status == PilotEntitlementStatus.grace;
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
