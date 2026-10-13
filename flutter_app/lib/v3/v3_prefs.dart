import 'package:flutter/foundation.dart';

/// Every v3 progress key goes through here. In debug builds started by the
/// device tests (E2E_SHELL), keys get an `e2e_` prefix, so running a test on
/// the phone can never read or erase the learner's real progress.
String v3Key(String base) =>
    (kDebugMode && const bool.fromEnvironment('E2E_SHELL'))
    ? 'e2e_$base'
    : base;
