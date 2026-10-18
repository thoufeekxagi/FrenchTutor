import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/v3_cloud_state.dart';

void main() {
  test('finished stories and saved words from both sides are kept', () {
    final merged = V3CloudState.merge(
      V3StateKind.set,
      ['story-a', 'story-b'],
      ['story-b', 'story-c'],
    );
    expect(merged, ['story-a', 'story-b', 'story-c']);
  });

  test('a reinstall can never move a reading position backwards', () {
    final merged =
        V3CloudState.merge(
              V3StateKind.positions,
              ['s1:4', 's2:0'],
              ['s1:9', 's3:2'],
            )
            as List;
    expect(merged.toSet(), {'s1:9', 's2:0', 's3:2'});
  });

  test('an empty phone restores everything from the account', () {
    expect(V3CloudState.merge(V3StateKind.set, null, ['a', 'b']), ['a', 'b']);
    expect(V3CloudState.merge(V3StateKind.positions, null, ['s:3']), ['s:3']);
    expect(V3CloudState.merge(V3StateKind.scalar, null, 'Aisha'), 'Aisha');
  });

  test('an empty account keeps what is on the phone', () {
    expect(V3CloudState.merge(V3StateKind.set, ['a'], null), ['a']);
    expect(V3CloudState.merge(V3StateKind.scalar, 'Aisha', null), 'Aisha');
  });

  test('a scalar takes whichever side was changed last', () {
    final older = DateTime.utc(2026, 10, 1);
    final newer = DateTime.utc(2026, 10, 2);
    expect(
      V3CloudState.merge(
        V3StateKind.scalar,
        'Old',
        'New',
        localAt: older,
        remoteAt: newer,
      ),
      'New',
    );
    expect(
      V3CloudState.merge(
        V3StateKind.scalar,
        'Mine',
        'Theirs',
        localAt: newer,
        remoteAt: older,
      ),
      'Mine',
    );
  });
}
