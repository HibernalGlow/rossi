import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/download/download_retry.dart';

void main() {
  group('isRateLimitedError', () {
    test('identifies HTTP 429 status', () {
      expect(isRateLimitedError(Exception('HTTP 429 Too Many Requests')), isTrue);
      expect(isRateLimitedError('Status code: 429'), isTrue);
    });

    test('identifies HTTP 509 Bandwidth Exceeded', () {
      expect(isRateLimitedError('509 Bandwidth Limit Exceeded'), isTrue);
    });

    test('identifies Cloudflare rate limiting', () {
      expect(isRateLimitedError('Cloudflare Ray ID error rate limit exceeded'), isTrue);
      expect(isRateLimitedError('Error: Too Many Requests from host'), isTrue);
    });

    test('returns false for generic errors', () {
      expect(isRateLimitedError(Exception('Socket closed')), isFalse);
      expect(isRateLimitedError('Connection reset by peer'), isFalse);
      expect(isRateLimitedError('404 Not Found'), isFalse);
    });
  });

  group('range input parsing logic', () {
    Set<int> parseRange(String input, int maxIndex) {
      final result = <int>{};
      final parts = input.split(RegExp(r'[,，\s]+'));
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.contains('-')) {
          final rangeParts = trimmed.split('-');
          if (rangeParts.length == 2) {
            final start = int.tryParse(rangeParts[0].trim());
            final end = int.tryParse(rangeParts[1].trim());
            if (start != null && end != null) {
              final from = start < end ? start : end;
              final to = start < end ? end : start;
              for (var i = from; i <= to; i++) {
                if (i >= 1 && i <= maxIndex) result.add(i);
              }
            }
          }
        } else {
          final single = int.tryParse(trimmed);
          if (single != null && single >= 1 && single <= maxIndex) {
            result.add(single);
          }
        }
      }
      return result;
    }

    test('parses single and range selections correctly', () {
      final res = parseRange('1-3, 5, 8-10', 20);
      expect(res, {1, 2, 3, 5, 8, 9, 10});
    });

    test('clamps to maxIndex', () {
      final res = parseRange('1-10, 25-30', 12);
      expect(res, {1, 2, 3, 4, 5, 6, 7, 8, 9, 10});
    });

    test('supports chinese comma and reverse range like 5-2', () {
      final res = parseRange('5-2，7', 10);
      expect(res, {2, 3, 4, 5, 7});
    });
  });
}
