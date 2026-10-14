import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/download/download_storage_summary.dart';

DownloadStorageStat _stat(int bytes, {bool measured = true}) {
  return DownloadStorageStat(bytes: bytes, measured: measured, rootCount: 1);
}

void main() {
  group('下载占用统计', () {
    test('合计只加量到过的那些', () {
      expect(
        totalDownloadStorageBytes([_stat(100), _stat(250), _stat(7)]),
        357,
      );
    });

    test('没量到的不掺数：既不算 0 也不让总数变小', () {
      // 那本漫画可能在旧布局里、也可能还没统计；把它当 0 会让「共占用」说出假话。
      final total = totalDownloadStorageBytes([
        _stat(1024),
        DownloadStorageStat.unmeasured,
        _stat(2048),
      ]);

      expect(total, 3072);
      expect(totalDownloadStorageBytes([DownloadStorageStat.unmeasured]), 0);
    });

    test('一本都没量到时 hasMeasuredStorage 为假，界面就不该报「共占用」', () {
      expect(
        hasMeasuredStorage([
          DownloadStorageStat.unmeasured,
          DownloadStorageStat.unmeasured,
        ]),
        isFalse,
      );
      expect(
        hasMeasuredStorage([DownloadStorageStat.unmeasured, _stat(0)]),
        isTrue,
      );
      // 量到过但真的是空目录：measured 为真、字节为 0，这两件事要能分开表达。
      expect(_stat(0).measured, isTrue);
      expect(_stat(0).bytes, 0);
    });

    test('可读形式按 B / KB / MB / GB 四档，KB 起一位小数', () {
      expect(formatDownloadBytes(0), '0 B');
      expect(formatDownloadBytes(1023), '1023 B');
      // 边界：刚好 1 KiB 起换算。
      expect(formatDownloadBytes(1024), '1.0 KB');
      expect(formatDownloadBytes(1536), '1.5 KB');
      expect(formatDownloadBytes(1024 * 1024), '1.0 MB');
      expect(formatDownloadBytes(1024 * 1024 * 1024), '1.0 GB');
      expect(formatDownloadBytes((3.5 * 1024 * 1024 * 1024).round()), '3.5 GB');
    });
  });
}
