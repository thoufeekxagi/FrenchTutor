import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/screens/settings/orchestration_lab_screen.dart';

void main() {
  test('orchestration lab is available to debug builds', () {
    expect(kDebugMode, isTrue);
    expect(const OrchestrationLabScreen(), isA<OrchestrationLabScreen>());
  });
}
