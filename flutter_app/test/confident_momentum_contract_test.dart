import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/design/tokens.dart';

void main() {
  test('active tokens match the Northstar Studio contract', () {
    expect(DesignTokens.primary, const Color(0xFF2259C7));
    expect(DesignTokens.secondary, const Color(0xFF0F7F78));
    expect(DesignTokens.success, const Color(0xFF2D8A5B));
    expect(DesignTokens.mastery, const Color(0xFFB97823));
    expect(DesignTokens.danger, const Color(0xFFC95757));
    expect(DesignTokens.minTapTarget, greaterThanOrEqualTo(48));
    expect(DesignTokens.radiusCard, 18);
    expect(DesignTokens.radiusMedium, 12);
  });
}
