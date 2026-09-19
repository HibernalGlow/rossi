import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/reader/super_resolution_queue.dart';

void main() {
  test(
    'new current page overtakes queued prefetch and stale pages are removed',
    () async {
      final queue = SuperResolutionQueue<int>();
      final gate = Completer<void>();
      final done = Completer<void>();
      final order = <int>[];
      queue.replace([
        (
          0,
          () async {
            order.add(0);
            await gate.future;
          },
        ),
        (1, () async => order.add(1)),
        (2, () async => order.add(2)),
      ]);
      await Future<void>.delayed(Duration.zero);
      queue.replace([
        (0, () async => fail('must not duplicate running inference')),
        (8, () async => order.add(8)),
        (
          9,
          () async {
            order.add(9);
            done.complete();
          },
        ),
      ]);
      gate.complete();
      await done.future;
      expect(order, [0, 8, 9]);
      queue.dispose();
    },
  );

  test('disposal stops queued background work', () async {
    final queue = SuperResolutionQueue<int>();
    final gate = Completer<void>();
    queue.replace([
      (0, () => gate.future),
      (1, () async => fail('disposed queue must not start inference')),
    ]);
    await Future<void>.delayed(Duration.zero);
    queue.dispose();
    gate.complete();
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'targets alternate adjacent pages and obey edges and disabled prefetch',
    () {
      expect(superResolutionTargets(3, 10, 3, 2), [3, 4, 2, 5, 1, 6]);
      expect(superResolutionTargets(0, 2, 3, 2), [0, 1]);
      expect(superResolutionTargets(9, 10, 3, 2), [9, 8, 7]);
      expect(superResolutionTargets(3, 10, 0, 0), [3]);
    },
  );
}
