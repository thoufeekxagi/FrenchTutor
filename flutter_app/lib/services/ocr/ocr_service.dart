/// On-device OCR leaf service. Native (iOS/Android) resolves to ML Kit text
/// recognition (Apple's Vision framework under the hood on iOS, Google's ML
/// Kit on Android) — free, fast, private, no network round trip. There is no
/// web branch yet: `master` predates the web app shell (see CLAUDE.md).
library;

export 'ocr_service_unsupported.dart' if (dart.library.io) 'ocr_service_native.dart';
