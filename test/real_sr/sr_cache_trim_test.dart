/// 超分产物缓存的封顶测试。
///
/// 产物目录以前在 `$TMPDIR`，macOS 每天清临时目录等于免费GC；搬到持久目录后没人清了，
/// 所以「超预算删最旧的、日志不许删」必须由这里守住 —— 否则看几本就吃掉几 GB 磁盘。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

/// 稀疏文件：只写目录项，不占磁盘，所以能便宜地造出 GB 级的产物。
void _sparse(String path, int size, DateTime modified) {
  final file = File(path)..createSync(recursive: true);
  final raf = file.openSync(mode: FileMode.write);
  raf.truncateSync(size);
  raf.closeSync();
  file.setLastModifiedSync(modified);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory cache;
  late int budget;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rossi_sr_trim_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => root.path);
    cache = await SuperResolutionLog.cacheDirectory();
    budget = SuperResolutionLog.cacheBudget;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await root.delete(recursive: true);
  });

  test('超预算时从最旧的产物开始删，删到线内就停', () async {
    // 三份各占预算的一半：总共 1.5× 预算 → 只需删掉最旧的一份。
    final half = budget ~/ 2;
    final base = DateTime(2026, 9, 1);
    _sparse('${cache.path}/sr_oldest.png', half, base);
    _sparse(
      '${cache.path}/sr_middle.png',
      half,
      base.add(const Duration(minutes: 1)),
    );
    _sparse(
      '${cache.path}/sr_newest.png',
      half,
      base.add(const Duration(minutes: 2)),
    );

    await SuperResolutionLog.trimCache();

    expect(
      File('${cache.path}/sr_oldest.png').existsSync(),
      isFalse,
      reason: '最旧的一份没删，缓存仍然超着预算',
    );
    expect(File('${cache.path}/sr_middle.png').existsSync(), isTrue);
    expect(File('${cache.path}/sr_newest.png').existsSync(), isTrue);
  });

  test('没超预算就一个字节都不动，日志文件也不参与', () async {
    _sparse('${cache.path}/sr_small.png', 1024 * 1024, DateTime(2026, 9, 1));
    // 比预算还大的日志：按大小它会先被淘汰，但它不是产物，不许删。
    _sparse(
      '${cache.path}/super_resolution.log',
      budget * 2,
      DateTime(2026, 9, 1),
    );

    await SuperResolutionLog.trimCache();

    expect(File('${cache.path}/sr_small.png').existsSync(), isTrue);
    expect(File('${cache.path}/super_resolution.log').existsSync(), isTrue);
  });
}
