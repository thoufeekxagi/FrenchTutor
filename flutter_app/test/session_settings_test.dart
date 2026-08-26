import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/services/session_settings.dart';

void main() {
  test('exposes the four supported local playback rates', () {
    expect(SessionSettings.playbackRates, [0.5, 0.75, 1.0, 1.5]);
    expect(
      SessionSettings.playbackRates
          .map(SessionSettings.playbackRateLabel)
          .toList(),
      ['0.5', '0.75', '1', '1.5'],
    );
  });
}
