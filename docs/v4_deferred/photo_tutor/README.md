# Photo Tutor OCR deferred from V3

Photo Tutor is disabled for V3 and planned for V4. The active V3 OCR service
returns an empty result, and the Google ML Kit package is intentionally absent
from `flutter_app/pubspec.yaml`, `pubspec.lock`, and the iOS Pods.

`ocr_service_native.dart` is preserved as reference code only. Before restoring
the feature in V4, review the adapter against current Flutter and ML Kit
versions, add the required dependencies and platform setup, and wire it to an
explicitly approved route. Do not import this file from the V3 app.
