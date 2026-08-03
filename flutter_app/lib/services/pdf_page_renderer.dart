import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

/// Rasterizes each page of a PDF into a JPEG image so it can travel through
/// the same [VisionScanService] pipeline as a camera/gallery photo — one
/// image-handling code path regardless of where the image came from.
class PdfPageRenderer {
  Future<List<Uint8List>> renderPages(
    Uint8List pdfBytes, {
    double resolutionScale = 2.0,
  }) async {
    final doc = await PdfDocument.openData(pdfBytes);
    try {
      final pages = <Uint8List>[];
      for (var i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        try {
          final rendered = await page.render(
            width: page.width * resolutionScale,
            height: page.height * resolutionScale,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
          );
          if (rendered != null) pages.add(rendered.bytes);
        } finally {
          await page.close();
        }
      }
      return pages;
    } finally {
      await doc.close();
    }
  }
}
