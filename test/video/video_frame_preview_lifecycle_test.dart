import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/service/video_frame_preview.dart';

void main() {
  late Directory root;
  final providers = <VideoFramePreviewProvider>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('preview-lifecycle-');
  });
  tearDown(() async {
    for (final provider in providers) {
      await provider.dispose();
    }
    providers.clear();
    await root.delete(recursive: true);
  });

  VideoFramePreviewProvider create(_Transport transport) {
    final provider = VideoFramePreviewProvider(
      transport: transport,
      cacheDirOverride: root.path,
    );
    providers.add(provider);
    return provider;
  }

  test('播放中悬停只用缓存，不截取当前帧或改变播放位置', () async {
    final transport = _Transport()..isPlaying = true;
    final provider = create(transport);
    expect(await provider.request(const Duration(seconds: 10)), isNull);
    expect(transport.screenshots, isEmpty);
    expect(transport.seeks, isEmpty);
    provider.cache.put(const Duration(seconds: 10), 'cached.jpg');
    expect(
      (await provider.request(const Duration(seconds: 10)))?.filePath,
      'cached.jpg',
    );
  });

  test('退出一页不删除其它页的缓存，另一页仍能继续截图', () async {
    final a = create(_Transport());
    final b = create(_Transport());
    const at = Duration(seconds: 5);
    await a.request(at);
    await b.request(at);
    await _until(() => a.peek(at) != null && b.peek(at) != null);
    final aFile = File(a.peek(at)!.filePath);
    final bFile = File(b.peek(at)!.filePath);
    expect(aFile.parent.path, isNot(bFile.parent.path));
    await a.dispose();
    expect(await aFile.exists(), isFalse);
    expect(await bFile.exists(), isTrue);
    expect(await root.exists(), isTrue);
    await b.request(const Duration(seconds: 10));
    await _until(() => b.peek(const Duration(seconds: 10)) != null);
  });

  test('退出时等待正在写入的截图，释放后不再重建缓存', () async {
    final transport = _Transport()..gate = Completer<void>();
    final provider = create(transport);
    await provider.request(const Duration(seconds: 5));
    await _until(() => transport.screenshots.isNotEmpty);
    var disposed = false;
    final disposal = provider.dispose().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, isFalse);
    transport.gate!.complete();
    await disposal;
    expect(await File(transport.screenshots.single).parent.exists(), isFalse);
    expect(provider.cache.length, 0);
    await provider.request(const Duration(seconds: 10));
    expect(transport.screenshots, hasLength(1));
  });

  test('截图抛错不会卡死后续预览任务', () async {
    final transport = _Transport()..failNext = true;
    final provider = create(transport);
    await provider.request(const Duration(seconds: 5));
    await _until(() => transport.screenshots.isNotEmpty);
    await provider.request(const Duration(seconds: 10));
    await _until(() => provider.peek(const Duration(seconds: 10)) != null);
    expect(provider.peek(const Duration(seconds: 5)), isNull);
    expect(transport.screenshots, hasLength(2));
  });
}

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

class _Transport implements VideoTransport {
  @override
  bool isPlaying = false;
  final seeks = <Duration>[];
  final screenshots = <String>[];
  Completer<void>? gate;
  bool failNext = false;

  @override
  Future<void> seekPaused(Duration to) async => seeks.add(to);

  @override
  Future<String?> screenshot(String path) async {
    screenshots.add(path);
    if (failNext) {
      failNext = false;
      throw FileSystemException('写入失败', path);
    }
    if (gate != null) await gate!.future;
    await File(path).writeAsBytes([1, 2, 3]);
    return path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
