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

  VideoFramePreviewProvider create(
    _Grabber Function() makeGrabber, {
    Duration idleDispose = const Duration(minutes: 1),
  }) {
    final provider = VideoFramePreviewProvider(
      createPreviewTransport: makeGrabber,
      cacheDirOverride: root.path,
      idleDispose: idleDispose,
    )..setSource('file:///movie.mp4');
    providers.add(provider);
    return provider;
  }

  test('解帧走自带解码器：先定位再截图，一台解码器跨多个位置复用', () async {
    final grabber = _Grabber();
    final provider = create(() => grabber);

    await provider.request(const Duration(seconds: 30));
    expect(
      provider.peek(const Duration(seconds: 30)),
      isNull,
      reason: '首次是未命中',
    );
    await _until(() => provider.peek(const Duration(seconds: 30)) != null);

    await provider.request(const Duration(seconds: 40));
    await _until(() => provider.peek(const Duration(seconds: 40)) != null);

    expect(grabber.commands, <String>[
      'open',
      'seek=30s',
      'shot',
      'seek=40s',
      'shot',
    ], reason: '悬停不该每换一个位置就重开一次文件，顺序也必须是先定位再截图');
    expect(grabber.opens, 1);
    expect(grabber.closes, 0);
  });

  test('seek 没落到目标附近就不给帧 —— 宁可不显示，也不显示上一帧', () async {
    // 这条守的是「划到后段却显示前段画面」：screenshot 截的是当前解码位置，
    // seek 没落位时它给的就是上一帧。
    final grabber = _Grabber()..landSeek = false;
    final provider = create(() => grabber);

    await provider.request(const Duration(seconds: 30));
    await _until(() => grabber.commands.contains('seek=30s'));
    // 落位闸门是 3 s，等它给出结论。
    await Future<void>.delayed(const Duration(milliseconds: 3400));

    expect(grabber.commands, isNot(contains('shot')));
    expect(provider.peek(const Duration(seconds: 30)), isNull);
  });

  test('打不开的源不再反复重开：这一页剩下的时间走占位', () async {
    final grabbers = <_Grabber>[];
    final provider = create(() {
      final grabber = _Grabber()..openFails = true;
      grabbers.add(grabber);
      return grabber;
    });

    await provider.request(const Duration(seconds: 10));
    await _until(() => grabbers.length == 1 && grabbers.first.closes == 1);
    await provider.request(const Duration(seconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(grabbers, hasLength(1), reason: '坏源不该每悬停一次就重开一台播放器');
    expect(provider.peek(const Duration(seconds: 20)), isNull);
  });

  test('空闲超时释放解码器，再悬停重开一台', () async {
    final grabbers = <_Grabber>[];
    final provider = create(() {
      final grabber = _Grabber();
      grabbers.add(grabber);
      return grabber;
    }, idleDispose: const Duration(milliseconds: 60));

    await provider.request(const Duration(seconds: 30));
    await _until(() => provider.peek(const Duration(seconds: 30)) != null);
    expect(grabbers, hasLength(1));
    await _until(() => grabbers.first.closes == 1);

    await provider.request(const Duration(seconds: 40));
    await _until(() => provider.peek(const Duration(seconds: 40)) != null);
    expect(grabbers, hasLength(2), reason: '空闲释放后要能重新起一台');
    expect(grabbers.last.opens, 1);
  });

  test('换源丢掉旧解码器与旧缓存', () async {
    final grabbers = <_Grabber>[];
    final provider = create(() {
      final grabber = _Grabber();
      grabbers.add(grabber);
      return grabber;
    });

    await provider.request(const Duration(seconds: 30));
    await _until(() => provider.peek(const Duration(seconds: 30)) != null);

    provider.setSource('file:///other.mp4');
    expect(
      provider.peek(const Duration(seconds: 30)),
      isNull,
      reason: '缓存按文件隔离',
    );
    await _until(() => grabbers.first.closes == 1);

    await provider.request(const Duration(seconds: 30));
    await _until(() => provider.peek(const Duration(seconds: 30)) != null);
    expect(grabbers, hasLength(2));
    expect(grabbers.last.commands.first, 'open');
  });

  test('翻页后旧解帧立刻收手，不陪它把超时等满', () async {
    // 卡住第一台的 open，模拟「文件打开很慢」；第二台要能正常起来。
    // 断言失败时也得放行，否则 tearDown 会陪着它挂到超时。
    final openGate = Completer<void>();
    addTearDown(() {
      if (!openGate.isCompleted) openGate.complete();
    });
    final grabbers = <_Grabber>[];
    final provider = create(() {
      final grabber = _Grabber();
      if (grabbers.isEmpty) grabber.openGate = openGate;
      grabbers.add(grabber);
      return grabber;
    });

    await provider.request(const Duration(seconds: 10));
    await _until(() => grabbers.isNotEmpty && grabbers.first.opens == 1);
    provider.setSource('file:///other.mp4');
    openGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(grabbers.single.closes, 1, reason: '旧解码器要被放下');
    expect(provider.peek(const Duration(seconds: 10)), isNull);
    // 这一页的预览要能立刻起新的：旧解帧若还在等时长，调度器是占着的。
    await provider.request(const Duration(seconds: 10));
    await _until(() => provider.peek(const Duration(seconds: 10)) != null);
    expect(grabbers, hasLength(2));
  });

  test('退出一页不删除其它页的缓存，另一页仍能继续截图', () async {
    final a = create(_Grabber.new);
    final b = create(_Grabber.new);
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
    final grabber = _Grabber()..gate = Completer<void>();
    final provider = create(() => grabber);
    await provider.request(const Duration(seconds: 5));
    await _until(() => grabber.paths.isNotEmpty);
    var disposed = false;
    final disposal = provider.dispose().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, isFalse);
    grabber.gate!.complete();
    await disposal;
    expect(await File(grabber.paths.single).parent.exists(), isFalse);
    expect(provider.cache.length, 0);
    expect(grabber.closes, 1, reason: '页面退出要连解码器一起放下');
    await provider.request(const Duration(seconds: 10));
    expect(grabber.paths, hasLength(1));
  });

  test('截图抛错不会卡死后续预览任务', () async {
    final grabber = _Grabber()..failNextShot = true;
    final provider = create(() => grabber);
    await provider.request(const Duration(seconds: 5));
    await _until(() => grabber.paths.isNotEmpty);
    await provider.request(const Duration(seconds: 10));
    await _until(() => provider.peek(const Duration(seconds: 10)) != null);
    expect(provider.peek(const Duration(seconds: 5)), isNull);
    expect(grabber.paths, hasLength(2));
  });
}

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

/// 预览解码器替身：只要 open / duration / seek / position / screenshot / close
/// 这几件真实用到的事，其余成员经 [noSuchMethod] 直接炸 —— 少写一个就会以
/// 断言失败的形式露出来，而不是静默当成「解不出帧」。
class _Grabber implements VideoTransport {
  _Grabber();

  final List<String> commands = <String>[];
  final List<String> paths = <String>[];
  Duration _pos = Duration.zero;

  @override
  Duration duration = const Duration(minutes: 2);
  bool openFails = false;
  bool landSeek = true;
  bool failNextShot = false;
  Completer<void>? gate;
  Completer<void>? openGate;
  int opens = 0;
  int closes = 0;

  @override
  Duration get position => _pos;

  /// 传输层把「引擎已经给结论」放在这里；预览据此立刻收手，不必把超时等满。
  @override
  String? get failureReason => null;

  @override
  Future<void> open(
    String uri, {
    VideoOpenOptions options = const VideoOpenOptions(),
  }) async {
    opens++;
    commands.add('open');
    if (openGate != null) await openGate!.future;
    if (openFails) throw StateError('打不开');
  }

  @override
  Future<void> close() async => closes++;

  @override
  Future<void> seek(Duration to) async {
    commands.add('seek=${to.inSeconds}s');
    if (landSeek) _pos = to;
  }

  @override
  Future<String?> screenshot(String path) async {
    commands.add('shot');
    paths.add(path);
    if (failNextShot) {
      failNextShot = false;
      throw FileSystemException('写入失败', path);
    }
    if (gate != null) await gate!.future;
    await File(path).writeAsBytes([1, 2, 3]);
    return path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
