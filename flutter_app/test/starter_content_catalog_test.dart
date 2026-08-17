import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/services/starter_content_service.dart';

void main() {
  test('starter catalog has five image-backed themes', () {
    final seeds = StarterContentCatalog.seeds;

    expect(seeds, hasLength(5));
    expect(seeds.map((seed) => seed.key).toSet(), hasLength(5));
    expect(
      seeds.every((seed) => seed.coverAsset.startsWith('assets/')),
      isTrue,
    );
    expect(seeds.every((seed) => seed.sentences.length >= 4), isTrue);
    expect(seeds.every((seed) => seed.words.length == 5), isTrue);
  });
}
