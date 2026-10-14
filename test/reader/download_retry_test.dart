import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/setting/real_sr/service/download_retry.dart';

void main() {
  test('retries a failed transfer and returns the first success', () async {
    final seen = <int>[];
    final result = await retryTransfer<String>(
      (attempt) async {
        seen.add(attempt);
        if (attempt < 3) throw StateError('断流 $attempt');
        return 'ok';
      },
      delay: (_) => Duration.zero,
    );
    expect(result, 'ok');
    expect(seen, [1, 2, 3]);
  });

  test('gives up after the last attempt and rethrows the final error', () async {
    var calls = 0;
    final retried = <int>[];
    await expectLater(
      retryTransfer<void>(
        (attempt) async {
          calls++;
          throw StateError('断流 $attempt');
        },
        delay: (_) => Duration.zero,
        onRetry: (attempt, _) => retried.add(attempt),
      ),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', '断流 3'),
      ),
    );
    expect(calls, 3);
    expect(retried, [1, 2]);
  });

  test('does not retry when the first attempt succeeds', () async {
    var calls = 0;
    await retryTransfer<void>((_) async => calls++);
    expect(calls, 1);
  });
}
