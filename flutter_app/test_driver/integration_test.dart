import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host-side driver for `tool/e2e.sh`. Screenshots and the probe report are
/// written to `artifacts/e2e/` so they can be read after a run instead of
/// guessing what the device showed.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('artifacts/e2e/shots/$name.png')
      ..createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return true;
  },
  responseDataCallback: (data) async {
    if (data == null) return;
    File('artifacts/e2e/probe.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  },
);
