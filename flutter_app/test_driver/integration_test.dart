import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

final _artifactDirectory =
    Platform.environment['E2E_ARTIFACT_DIR'] ?? 'artifacts/e2e';

/// Host-side driver for `tool/e2e.sh`. Screenshots and the probe report are
/// written to `artifacts/e2e/` by default. Other runners may set
/// `E2E_ARTIFACT_DIR` to preserve artifacts from earlier runs.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('$_artifactDirectory/shots/$name.png')
      ..createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return true;
  },
  responseDataCallback: (data) async {
    if (data == null) return;
    File('$_artifactDirectory/probe.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  },
);
