import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all screen sources follow the UI v2 token contract', () {
    final screenFiles = Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    expect(screenFiles.length, greaterThanOrEqualTo(40));

    final retiredTerms = RegExp(
      r'Passeport|ProSystemAzure|DesignTokens\.(?:card|parchment|maroon|brass|sage|sky|slate)',
    );
    final directBrandColors = RegExp(r'Color\(0x');

    for (final file in screenFiles) {
      final source = file.readAsStringSync();
      expect(
        retiredTerms.hasMatch(source),
        isFalse,
        reason: '${file.path} still uses a retired visual identifier.',
      );
      expect(
        directBrandColors.hasMatch(source),
        isFalse,
        reason: '${file.path} bypasses semantic DesignTokens.',
      );
    }
  });

  test('Android and iOS keep separate permanent identities', () {
    final androidGradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(androidGradle, contains('com.parlesprint.app'));
    expect(androidGradle, isNot(contains('com.thoufeekx.frenchtutor')));
    expect(iosProject, contains('com.thoufeekx.frenchtutor'));
    expect(iosProject, isNot(contains('com.parlesprint.app')));
  });
}
