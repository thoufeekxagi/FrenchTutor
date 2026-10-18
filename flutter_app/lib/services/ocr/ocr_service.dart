/// OCR seam retained for the deferred V4 Photo Tutor.
///
/// V3 intentionally ships without an OCR engine. The native ML Kit adapter is
/// preserved outside the Flutter app at `docs/v4_deferred/photo_tutor/ocr_service_native.dart`;
/// this adapter returns an empty result until that feature is restored in V4.
library;

export 'ocr_service_unsupported.dart'
    if (dart.library.io) 'ocr_service_native.dart';
