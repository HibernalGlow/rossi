import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/controller/reader_video_controller.dart';
import 'package:zephyr/video/view/active_video_scope.dart';
import 'package:zephyr/video/view/video_control_overlay.dart';

void main() {
  setUpAll(() async {
    const fontPath = String.fromEnvironment('VIDEO_CONTROLS_PREVIEW_FONT');
    if (fontPath.isNotEmpty) {
      final font = FontLoader('VideoPreview')
        ..addFont(
          File(
            fontPath,
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  testWidgets('泳道没有 Material 祖先时控制条仍能渲染并响应按钮', (tester) async {
    final controller = ReaderVideoController(
      host: _Host(),
      progressKey: 'overlay-test',
    );
    final panelsOpen = VideoPanelController();
    final labels = videoLabels();
    var pinned = false;
    try {
      // 阅读器泳道直接承载视频，不能用 Scaffold 掩盖控制条缺少 Material 的问题。
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.bottomCenter,
            child: VideoControlOverlay(
              snapshot: controller.snapshot,
              controller: controller,
              labels: labels,
              onTogglePin: () => pinned = !pinned,
              pinned: pinned,
              panelsOpen: panelsOpen,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byTooltip(labels.play), findsOneWidget);
      await tester.tap(find.byTooltip(labels.pin));
      await tester.pump();
      expect(pinned, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      panelsOpen.dispose();
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}：MD3 颜色、滤镜交互和菜单关闭', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey<_ControlsHarnessState>();
      await tester.pumpWidget(
        _ControlsHarness(key: key, brightness: brightness),
      );
      await tester.pumpAndSettle();
      final state = key.currentState!;
      final colors = state.colors;
      final toolbar = tester.widget<Material>(
        find.byKey(const ValueKey('video-controls-surface')),
      );
      expect(toolbar.color, colors.surfaceContainerHigh);
      await tester.tap(find.byTooltip(videoLabels().filters));
      await tester.pumpAndSettle();
      expect(state.panels.value, isTrue);
      final brightnessText = find.text(t.video.brightness);
      expect(brightnessText, findsOneWidget);
      final text = tester.renderObject<RenderParagraph>(
        find.descendant(of: brightnessText, matching: find.byType(RichText)),
      );
      expect(text.text.style?.color, colors.onSurface);
      final panelMaterial = tester.widget<Material>(
        find
            .ancestor(of: brightnessText, matching: find.byType(Material))
            .first,
      );
      expect(panelMaterial.color, colors.surfaceContainer);

      final slider = find.byType(Slider).at(1); // 进度条之后是亮度。
      await tester.tapAt(tester.getCenter(slider) + const Offset(50, 0));
      await tester.pumpAndSettle();
      expect(state.filter.brightness, greaterThan(100));
      expect(
        tester.widget<Slider>(slider).value,
        state.filter.brightness.toDouble(),
      );
      await _capturePreview(tester, 'video-controls-${brightness.name}');
      await tester.tap(find.text(videoLabels().resetFilters));
      await tester.pumpAndSettle();
      expect(state.filter.isDefault, isTrue);

      // 弹层开着时切换主题，背景与前景必须同步更新。
      state.changeBrightness();
      await tester.pumpAndSettle();
      final switched = tester.renderObject<RenderParagraph>(
        find.descendant(of: brightnessText, matching: find.byType(RichText)),
      );
      expect(switched.text.style?.color, state.colors.onSurface);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text(t.video.brightness), findsNothing);
      expect(state.panels.value, isFalse);
      await tester.tap(find.byTooltip(videoLabels().filters));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(30, 30));
      await tester.pumpAndSettle();
      expect(state.panels.value, isFalse);
      expect(find.text(t.video.brightness), findsNothing);

      await tester.tap(find.byKey(const ValueKey('video-pin-controls')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('video-pin-controls')),
            )
            .isSelected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('video-pin-controls')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('video-pin-controls')),
            )
            .isSelected,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('悬停只出预览不改位置，点击才跳，拖动时预览跟手', (tester) async {
    // 这三条是同一条手感口径的三面：预览是「先看看要跳到哪儿」，
    // 落点是用户按下那一刻的事 —— 鼠标划过进度条不该把播放位置拖走。
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<_ControlsHarnessState>();
    await tester.pumpWidget(
      _ControlsHarness(key: key, brightness: Brightness.dark),
    );
    await tester.pumpAndSettle();
    final transport = key.currentState!.controller.transport! as _UiTransport;
    final bar = find.byKey(const ValueKey('video-progress-bar'));
    final center = tester.getCenter(bar);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: center);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(center);
    await tester.pump();
    expect(transport.seeks, isEmpty, reason: '悬停不是 seek');
    final chip = find.byKey(const ValueKey('video-preview-busy'));
    expect(chip, findsOneWidget, reason: '还没有帧时给占位和「定位中」');
    final hoveringAt = tester.getCenter(chip);

    await mouse.moveTo(center + const Offset(120, 0));
    await tester.pump();
    expect(transport.seeks, isEmpty, reason: '悬停划过整条轴也不许动位置');
    expect(
      tester.getCenter(chip).dx,
      greaterThan(hoveringAt.dx),
      reason: '预览要跟着指针走',
    );

    await tester.tapAt(center);
    await tester.pump();
    expect(transport.seeks, hasLength(1), reason: '点击才是落点');

    // 按下期间只有 move 事件（`MouseRegion.onHover` 收不到），预览靠 Listener 跟手。
    final draggingFrom = tester.getCenter(chip).dx;
    final drag = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(140, 0));
    await tester.pump();
    expect(
      tester.getCenter(chip).dx,
      greaterThan(draggingFrom),
      reason: '拖动时预览也要跟手',
    );
    await drag.up();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄泳道菜单不会越界，音量和倍速即时刷新，开着菜单也能安全退出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<_ControlsHarnessState>();
    await tester.pumpWidget(
      _ControlsHarness(key: key, brightness: Brightness.dark),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(videoLabels().speed));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.0x'));
    await tester.pumpAndSettle();
    expect(key.currentState!.controller.snapshot.playbackRate, 2);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '2.0x'))
          .selected,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(videoLabels().volume));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(videoLabels().subtitles));
    await tester.pumpAndSettle();
    final subtitleRect = tester.getRect(find.text(videoLabels().subtitleOff));
    expect(subtitleRect.left, greaterThanOrEqualTo(0));
    expect(subtitleRect.right, lessThanOrEqualTo(360));
    await _capturePreview(tester, 'video-controls-narrow');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _Host implements ReaderVideoHost {
  @override
  void onVideoListEnded() {}

  @override
  void onVideoProgress(VideoPlaybackProgress progress) {}
}

class _ControlsHarness extends StatefulWidget {
  const _ControlsHarness({super.key, required this.brightness});
  final Brightness brightness;
  @override
  State<_ControlsHarness> createState() => _ControlsHarnessState();
}

class _ControlsHarnessState extends State<_ControlsHarness> {
  final controller = ReaderVideoController(
    host: _Host(),
    progressKey: 'test',
    transport: _UiTransport(),
  );
  final panels = VideoPanelController();
  VideoFilterState filter = VideoFilterState.neutral;
  VideoSubtitleStyle subtitleStyle = const VideoSubtitleStyle();
  late Brightness brightness = widget.brightness;
  bool pinned = false;
  ColorScheme get colors =>
      ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: brightness);
  void changeBrightness() => setState(
    () => brightness = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark,
  );

  @override
  void dispose() {
    controller.dispose();
    panels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('video-preview-root'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        fontFamily:
            const String.fromEnvironment('VIDEO_CONTROLS_PREVIEW_FONT').isEmpty
            ? null
            : 'VideoPreview',
      ),
      home: ColoredBox(
        color: const Color(0xff17191c),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => VideoControlOverlay(
                snapshot: controller.snapshot.copyWith(
                  playing: true,
                  duration: const Duration(seconds: 115),
                  currentTime: const Duration(seconds: 32),
                ),
                controller: controller,
                labels: videoLabels(),
                pinned: pinned,
                onTogglePin: () => setState(() => pinned = !pinned),
                panelsOpen: panels,
                filter: filter,
                onFilterChanged: (value) => setState(() => filter = value),
                subtitleStyle: subtitleStyle,
                onSubtitleStyleChanged: (value) =>
                    setState(() => subtitleStyle = value),
                onFullscreen: () {},
                onScreenshot: () async {},
                onOpenInfo: () {},
                onTogglePip: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _capturePreview(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('VIDEO_CONTROLS_PREVIEW_DIR');
  if (directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('video-preview-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _UiTransport implements VideoTransport {
  /// 悬停与点击的差别就落在这张表上：悬停一次都不该往里加东西。
  final List<Duration> seeks = <Duration>[];

  @override
  Future<void> seek(Duration to) async => seeks.add(to);
  @override
  List<VideoMediaTrack> get audioTracks => const [];
  @override
  List<VideoMediaTrack> get subtitleTracks => const [];
  @override
  VideoMetadata get metadata => VideoMetadata.unknown;
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
