import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/services/starter_cover_resolver.dart';

void main() {
  test('restores bundled artwork when a starter row has no remote cover', () {
    expect(
      StarterCoverResolver.resolve(title: 'La lanterne du jardin'),
      'asset:assets/starter_covers/lantern.png',
    );
  });

  test('keeps a private or generated cover URL when one exists', () {
    const coverUrl = 'https://example.com/generated-cover.jpg';

    expect(
      StarterCoverResolver.resolve(
        title: 'La lanterne du jardin',
        coverUrl: coverUrl,
      ),
      coverUrl,
    );
  });

  test('does not invent artwork for unknown generated content', () {
    expect(StarterCoverResolver.resolve(title: 'A brand-new lesson'), isNull);
  });
}
