import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/services/serial_request_queue.dart';

void main() {
  group('SerialRequestQueue', () {
    test(
      'serializes different targets and coalesces the same target',
      () async {
        final queue = SerialRequestQueue<String, int>();
        final firstGate = Completer<int>();
        final secondGate = Completer<int>();
        final started = <String>[];

        final first = queue.run('unit-3-reading', () async {
          started.add('reading');
          return firstGate.future;
        });
        final duplicate = queue.run('unit-3-reading', () async {
          started.add('duplicate');
          return 99;
        });
        final second = queue.run('unit-3-vocabulary', () async {
          started.add('vocabulary');
          return secondGate.future;
        });

        expect(identical(first, duplicate), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(started, ['reading']);

        firstGate.complete(1);
        expect(await first, 1);
        await Future<void>.delayed(Duration.zero);
        expect(started, ['reading', 'vocabulary']);

        secondGate.complete(2);
        expect(await second, 2);
      },
    );

    test('a failed request does not block a later target', () async {
      final queue = SerialRequestQueue<String, int>();
      final failed = queue.run('unit-3-reading', () async {
        throw StateError('temporary generation failure');
      });
      final following = queue.run('unit-3-writing', () async => 3);

      await expectLater(failed, throwsA(isA<StateError>()));
      expect(await following, 3);
    });

    test('waitForIdle includes every queued target', () async {
      final queue = SerialRequestQueue<String, void>();
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      final started = <String>[];

      final first = queue.run('first', () async {
        started.add('first');
        await firstGate.future;
      });
      final second = queue.run('second', () async {
        started.add('second');
        await secondGate.future;
      });
      final idle = queue.waitForIdle();

      await Future<void>.delayed(Duration.zero);
      expect(started, ['first']);
      firstGate.complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(started, ['first', 'second']);

      var didBecomeIdle = false;
      unawaited(idle.then((_) => didBecomeIdle = true));
      await Future<void>.delayed(Duration.zero);
      expect(didBecomeIdle, isFalse);
      secondGate.complete();
      await second;
      await idle;
      expect(didBecomeIdle, isTrue);
    });

    test(
      'the same key can be requested again after its run completes',
      () async {
        final queue = SerialRequestQueue<String, int>();
        var calls = 0;

        expect(await queue.run('unit-3-listening', () async => ++calls), 1);
        expect(await queue.run('unit-3-listening', () async => ++calls), 2);
        expect(calls, 2);
      },
    );
  });
}
