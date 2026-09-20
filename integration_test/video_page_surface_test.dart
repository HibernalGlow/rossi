import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/service/video_progress_store.dart';
import 'package:zephyr/video/view/active_video_scope.dart';
import 'package:zephyr/video/view/video_page_surface.dart';

import 'fixtures/video_page_sample.dart';

// flutter test integration_test/video_page_surface_test.dart -d macos
// 可用 --dart-define=VIDEO_PAGE_TEST_FILE=/absolute/path/video.mp4 验证本地片源。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('视频持续播放，悬停或截图失败不遮挡画面，退出后停止播放', (tester) async {
    final directory = await Directory.systemTemp.createTemp('video-page-');
    Player? player;
    VideoTransport? transport;
    try {
      const externalPath = String.fromEnvironment('VIDEO_PAGE_TEST_FILE');
      final file = externalPath.isNotEmpty
          ? File(externalPath)
          : await File(
              '${directory.path}/sample.mp4',
            ).writeAsBytes(base64Decode(videoPageSampleBase64));
      expect(await file.exists(), isTrue);
      final labels = videoLabels();
      await tester.pumpWidget(
        MaterialApp(
          // 和泳道一样不额外包 Scaffold，验证视频控件自身的 Material 边界。
          home: VideoPageSurface(
            target: VideoPageTarget(
              sourcePath: file.path,
              entryName: file.uri.pathSegments.last,
              pageIndex: 0,
              progressKey: 'video-page-smoke',
              resolveDirectPath: () async => file.path,
              readBytes: () async => throw StateError('本地视频应直接使用原路径'),
            ),
            labels: labels,
            settings: const VideoPageSettings(
              controlsPinned: true,
              volumePercent: 0,
            ),
            progressStore: _MemoryProgressStore(),
          ),
        ),
      );
      await tester.pump();

      // 回归点：播放器必须保存到页面状态，否则永远只有初始转圈，Video 不挂载。
      expect(find.byType(Video), findsOneWidget);
      final video = tester.widget<Video>(find.byType(Video));
      player = video.controller.player;
      final controller = ActiveVideoScope.instance.controller!;
      var firstFrameRendered = false;
      video.controller.waitUntilFirstFrameRendered.then((_) {
        firstFrameRendered = true;
      });
      await _pumpUntil(
        tester,
        () =>
            firstFrameRendered &&
            controller.snapshot.phase == VideoEnginePhase.ready &&
            controller.snapshot.currentTime > const Duration(milliseconds: 200),
        '应渲染首帧并推进播放进度',
      );
      expect(player.state.width, greaterThan(0));
      expect(player.state.height, greaterThan(0));
      expect(controller.snapshot.duration, greaterThan(Duration.zero));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final native = player.platform as NativePlayer;
      expect(
        await native.getProperty('hwdec'),
        Platform.isAndroid ? 'auto-safe' : 'auto',
      );
      debugPrint('Video decoder: ${await native.getProperty('hwdec-current')}');
      for (final key in ['brightness', 'contrast', 'saturation']) {
        expect(double.parse(await native.getProperty(key)), 0);
      }
      expect(
        (await native.getProperty('sub-color')).toLowerCase(),
        '#ffffffff',
      );
      expect(
        (await native.getProperty('sub-back-color')).toLowerCase(),
        '#b3000000',
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip(labels.pause));
      await _pumpUntil(tester, () => !controller.snapshot.playing, '暂停应生效');
      await tester.tap(find.byTooltip(labels.play));
      await _pumpUntil(tester, () => controller.snapshot.playing, '应恢复播放');

      transport = controller.transport!;
      final audioTrack = transport.audioTracks.firstOrNull;
      if (audioTrack != null) {
        // 菜单选择不能再依赖播放进度顺带刷新，暂停时也要收到轨道通知。
        await controller.setPlaying(false);
        await transport.selectAudioTrack(null);
        await _pumpUntil(
          tester,
          () => transport!.audioTracks.every((track) => !track.selected),
          '暂停时关闭音轨应更新选择状态',
        );
        await transport.selectAudioTrack(audioTrack.id);
        await _pumpUntil(
          tester,
          () => transport!.audioTracks.any(
            (track) => track.id == audioTrack.id && track.selected,
          ),
          '暂停时重新选择音轨应更新状态',
        );
        await controller.setPlaying(true);
        await _pumpUntil(tester, () => controller.snapshot.playing, '应恢复播放');
      }
      final shot = '${directory.path}/nested/frame.png';
      expect(await transport.screenshot(shot), shot);
      final codec = await ui.instantiateImageCodec(
        await File(shot).readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      expect(frame.image.width, player.state.width);
      expect(frame.image.height, player.state.height);
      frame.image.dispose();
      codec.dispose();

      // 用普通文件挡住父目录，稳定模拟截图无法写入，而不是依赖磁盘权限。
      final blocked = await File(
        '${directory.path}/blocked',
      ).writeAsString('x');
      expect(await transport.screenshot('${blocked.path}/frame.png'), isNull);

      // 旧命令的错误也不能把正在播放的页面改成黑色失败页。
      final writeError = player.stream.error.firstWhere(
        (error) => error.startsWith('Error writing screenshot'),
      );
      await native.command([
        'screenshot-to-file',
        '${blocked.path}/native-frame.png',
        'video',
      ]);
      await writeError.timeout(const Duration(seconds: 5));
      await tester.pump();
      expect(controller.snapshot.phase, VideoEnginePhase.ready);
      expect(controller.snapshot.failureReason, isNull);

      // 持续悬停进度条 15 秒，检查每秒都继续前进且画面未被错误页覆盖。
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      final bar = tester.getRect(
        find.byKey(const ValueKey('video-progress-bar')),
      );
      final stableVideo = tester.widget<Video>(find.byType(Video));
      final stableMenu = tester.widget<MenuAnchor>(
        find.byType(MenuAnchor).first,
      );
      final start = controller.snapshot.currentTime;
      var previous = start;
      for (var i = 0; i < 15; i++) {
        await mouse.moveTo(
          Offset(bar.left + bar.width * (0.2 + i * 0.04), bar.center.dy),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(controller.snapshot.phase, VideoEnginePhase.ready);
        expect(controller.snapshot.playing, isTrue);
        expect(controller.snapshot.currentTime, greaterThan(previous));
        expect(find.text('Error writing screenshot!'), findsNothing);
        expect(find.byType(Video), findsOneWidget);
        expect(
          tester.widget<Video>(find.byType(Video)),
          same(stableVideo),
          reason: '进度和悬停更新不应重建视频纹理子树',
        );
        expect(
          tester.widget<MenuAnchor>(find.byType(MenuAnchor).first),
          same(stableMenu),
          reason: '进度更新不能重建按钮和菜单',
        );
        expect(tester.takeException(), isNull);
        previous = controller.snapshot.currentTime;
      }
      expect(previous - start, greaterThan(const Duration(seconds: 10)));
      await mouse.removePointer();

      await tester.pumpWidget(const SizedBox.shrink());
      expect(ActiveVideoScope.instance.controller, isNull);
      await _pumpUntil(tester, () => native.disposed, '退出页面应释放播放器和纹理');
      expect(player.state.playing, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await transport?.close();
      await directory.delete(recursive: true);
    }
  });

  testWidgets('切换视频与硬解设置会释放旧会话，慢加载不能重启旧页', (tester) async {
    final directory = await Directory.systemTemp.createTemp('video-lifecycle-');
    final file = await File(
      '${directory.path}/sample.mp4',
    ).writeAsBytes(base64Decode(videoPageSampleBase64));
    final delayedPath = Completer<String?>();
    final players = <NativePlayer>[];
    Widget page(
      String name, {
      bool hardwareDecode = true,
      bool delayed = false,
    }) => MaterialApp(
      home: VideoPageSurface(
        target: VideoPageTarget(
          sourcePath: file.path,
          entryName: name,
          pageIndex: 0,
          progressKey: name,
          resolveDirectPath: () =>
              delayed ? delayedPath.future : Future.value(file.path),
          readBytes: () async => throw StateError('应直接打开本地路径'),
        ),
        labels: videoLabels(),
        settings: VideoPageSettings(
          hardwareDecode: hardwareDecode,
          volumePercent: 0,
        ),
        progressStore: _MemoryProgressStore(),
      ),
    );
    try {
      for (final hardwareDecode in [true, false, true]) {
        final previous = players.lastOrNull;
        final oldController = ActiveVideoScope.instance.controller;
        await tester.pumpWidget(
          page('session-${players.length}', hardwareDecode: hardwareDecode),
        );
        await _pumpUntil(
          tester,
          () =>
              find.byType(Video).evaluate().isNotEmpty &&
              ActiveVideoScope.instance.controller != oldController &&
              ActiveVideoScope.instance.controller?.snapshot.phase ==
                  VideoEnginePhase.ready,
          '切换后新会话应可播放',
        );
        final video = tester.widget<Video>(find.byType(Video));
        final native = video.controller.player.platform as NativePlayer;
        players.add(native);
        if (previous != null) expect(previous.disposed, isTrue);
        await video.controller.waitUntilFirstFrameRendered.timeout(
          const Duration(seconds: 10),
        );
        expect(
          await native.getProperty('hwdec'),
          hardwareDecode ? (Platform.isAndroid ? 'auto-safe' : 'auto') : 'no',
        );
        if (!hardwareDecode) {
          expect(await native.getProperty('hwdec-current'), 'no');
        }
        expect(tester.takeException(), isNull);
      }
      // 在路径尚未就绪时换页：过期异步结果不能打开旧视频或抢走活动控制器。
      await tester.pumpWidget(page('slow', delayed: true));
      await _pumpUntil(
        tester,
        () =>
            find.byType(Video).evaluate().isNotEmpty &&
            ActiveVideoScope.instance.controller?.progressKey == 'slow',
        '慢加载页应创建输出',
      );
      final slow =
          tester.widget<Video>(find.byType(Video)).controller.player.platform
              as NativePlayer;
      players.add(slow);
      await tester.pumpWidget(page('latest'));
      delayedPath.complete(file.path);
      await _pumpUntil(
        tester,
        () =>
            ActiveVideoScope.instance.controller?.progressKey == 'latest' &&
            ActiveVideoScope.instance.controller?.snapshot.phase ==
                VideoEnginePhase.ready,
        '只应打开最新目标',
      );
      expect(slow.disposed, isTrue);
      final latest =
          tester.widget<Video>(find.byType(Video)).controller.player.platform
              as NativePlayer;
      players.add(latest);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntil(
        tester,
        () => players.every((p) => p.disposed),
        '所有播放器应释放',
      );
      expect(ActiveVideoScope.instance.controller, isNull);
      expect(tester.takeException(), isNull);
    } finally {
      if (!delayedPath.isCompleted) delayedPath.complete(file.path);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntil(tester, () => players.every((p) => p.disposed), '清理播放器');
      await directory.delete(recursive: true);
    }
  });

  testWidgets('取消固定、恢复播放和关菜单后自动隐藏，暂停和开菜单时保留控制条', (tester) async {
    final directory = await Directory.systemTemp.createTemp('video-controls-');
    final file = await File(
      '${directory.path}/sample.mp4',
    ).writeAsBytes(base64Decode(videoPageSampleBase64));
    NativePlayer? player;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          ),
          home: VideoPageSurface(
            target: VideoPageTarget(
              sourcePath: file.path,
              entryName: 'sample.mp4',
              pageIndex: 0,
              progressKey: 'visibility',
              resolveDirectPath: () async => file.path,
              readBytes: () async => null,
            ),
            labels: videoLabels(),
            settings: const VideoPageSettings(
              controlsPinned: true,
              volumePercent: 0,
              autoHideMilliseconds: 400,
            ),
            progressStore: _MemoryProgressStore(),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            ActiveVideoScope.instance.controller?.snapshot.phase ==
            VideoEnginePhase.ready,
        '视频应起播',
      );
      final controller = ActiveVideoScope.instance.controller!;
      player =
          tester.widget<Video>(find.byType(Video)).controller.player.platform
              as NativePlayer;
      bool visible() =>
          tester
              .widget<AnimatedOpacity>(
                find.byKey(const ValueKey('video-controls-visibility')),
              )
              .opacity ==
          1;
      Future<void> idle() async {
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump(const Duration(milliseconds: 250));
      }

      await mouse.addPointer();
      Future<void> reveal() async {
        await mouse.moveTo(const Offset(80, 70));
        await mouse.moveTo(const Offset(90, 70));
        await tester.pump();
      }

      await idle();
      expect(visible(), isTrue, reason: '固定时必须常显');
      await tester.tap(find.byKey(const ValueKey('video-pin-controls')));
      await tester.pump();
      await idle();
      expect(visible(), isFalse, reason: '取消固定后无需移动鼠标就应收起');
      await reveal();
      expect(visible(), isTrue);
      await tester.tap(find.byTooltip(videoLabels().pause));
      await _pumpUntil(tester, () => !controller.snapshot.playing, '暂停');
      await idle();
      expect(visible(), isTrue, reason: '暂停时保留操作入口');
      await tester.tap(find.byTooltip(videoLabels().play));
      await _pumpUntil(tester, () => controller.snapshot.playing, '恢复播放');
      await idle();
      expect(visible(), isFalse, reason: '恢复播放后重新计时');
      await reveal();
      await tester.tap(find.byTooltip(videoLabels().filters));
      await tester.pump();
      await idle();
      expect(visible(), isTrue, reason: '调滤镜时不能隐藏');
      await tester.tapAt(const Offset(30, 30));
      await tester.pump();
      expect(controller.snapshot.playing, isTrue, reason: '关闭弹层不能同时触发画面点击');
      await idle();
      expect(visible(), isFalse, reason: '关闭弹层后重新计时');
      await reveal();
      await tester.tap(find.byTooltip(videoLabels().subtitles));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await idle();
      expect(visible(), isFalse, reason: 'Esc 关闭弹层也恢复自动隐藏');
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      if (player != null) {
        await _pumpUntil(tester, () => player!.disposed, '退出释放播放器');
      }
      await directory.delete(recursive: true);
    }
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
  String reason,
) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < const Duration(seconds: 20)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue, reason: reason);
  // 播放器事件更新状态后，控制条要等下一帧才切换播放/暂停按钮。
  await tester.pump();
}

class _MemoryProgressStore implements VideoProgressStore {
  final _entries = <String, VideoProgressEntry>{};

  @override
  Future<VideoProgressEntry?> load(String key) async => _entries[key];

  @override
  Future<void> save(VideoProgressEntry entry, {required String key}) async {
    _entries[key] = entry;
  }

  @override
  Future<void> remove(String key) async => _entries.remove(key);
}
