import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/method/jump_chapter.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/bottom.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/bottom_thumbnail_strip.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_hover_reveal_layer.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/video/controller/reader_video_controller.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/view/active_video_scope.dart';
import 'package:zephyr/video/view/reader_video_controls_scope.dart';
import 'package:zephyr/video/view/video_control_overlay.dart';

void main() {
  setUpAll(() async {
    if (const String.fromEnvironment(
      'VIDEO_BOTTOM_BAR_PREVIEW_DIR',
    ).isNotEmpty) {
      await (FontLoader(
            'VideoPreview',
          )..addFont(rootBundle.load('asset/fonts/LXGWWenKaiLite-Regular.ttf')))
          .load();
    }
  });
  setUp(() => VideoSettingsStore.integrateControlsWithBottomBar.value = true);
  tearDown(
    () => VideoSettingsStore.integrateControlsWithBottomBar.value = true,
  );
  for (final size in [
    const Size(900, 600),
    const Size(360, 720),
    const Size(320, 640),
    const Size(700, 400),
  ]) {
    testWidgets('融合底栏 ${size.width}×${size.height} 的进度可拖动', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_Harness(key: key));
      await tester.pumpAndSettle();
      final state = key.currentState!;
      state.reader.updateTotalSlots(4);
      state.settings.showThumbnails();
      await tester.pumpAndSettle();
      final progress = find.byKey(const ValueKey('video-progress-bar'));
      expect(
        find.byKey(const ValueKey('reader-video-bottom-bar')),
        findsOneWidget,
      );
      expect(progress, findsOneWidget);
      final toolbar = find.byKey(const ValueKey('reader-video-toolbar'));
      final thumbnails = find.byType(BottomThumbnailStrip);
      expect(
        tester.getRect(toolbar).bottom,
        lessThan(tester.getRect(progress).top),
      );
      expect(
        tester.getRect(progress).bottom,
        lessThanOrEqualTo(tester.getRect(thumbnails).top),
      );
      final play = find.byTooltip(videoLabels().pause);
      final more = find.byTooltip(t.common.more);
      expect(
        (tester.getCenter(play).dy - tester.getCenter(more).dy).abs(),
        lessThan(1),
      );
      expect(find.byKey(const ValueKey('reader-page-slider')), findsNothing);
      expect(
        tester
            .widget<Material>(
              find.byKey(const ValueKey('video-controls-surface')),
            )
            .color,
        Colors.transparent,
      );

      await tester.drag(progress, const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(state.transport.seeks, isNotEmpty);
      expect(state.panels.value, isFalse);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'fused-${size.width.toInt()}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  for (final video in [false, true]) {
    for (final size in [const Size(360, 720), const Size(700, 400)]) {
      testWidgets('单页 ${video ? "视频" : "图片"} ${size.width} 不占缩略图空行', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final key = GlobalKey<_HarnessState>();
        await tester.pumpWidget(_Harness(key: key, video: video));
        await tester.pumpAndSettle();
        final state = key.currentState!;
        state.reader.updateTotalSlots(1);
        state.settings.showThumbnails();
        await tester.pumpAndSettle();
        expect(find.byType(BottomThumbnailStrip), findsNothing);
        expect(find.byKey(const ValueKey('reader-page-slider')), findsNothing);
        expect(
          find.byKey(const ValueKey('video-progress-bar')),
          video ? findsOneWidget : findsNothing,
        );
        expect(state.settings.state.readSetting.showThumbnailStrip, isTrue);
        await _capture(
          tester,
          'single-${video ? "video" : "image"}-${size.width.toInt()}',
        );
        state.reader.updateTotalSlots(4);
        await tester.pumpAndSettle();
        expect(find.byType(BottomThumbnailStrip), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} 大字号、多音轨及滤镜按钮按内容分组', (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(const Size(360, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: key,
          brightness: brightness,
          scale: 1.5,
          extraControls: true,
        ),
      );
      await tester.pumpAndSettle();
      final state = key.currentState!;
      state.reader.updateTotalSlots(4);
      state.settings.showThumbnails();
      await tester.pumpAndSettle();
      final pinRect = tester.getRect(
        find.byKey(const ValueKey('video-pin-controls')),
      );
      expect(pinRect.width, lessThanOrEqualTo(48));
      final settings = [
        videoLabels().speed,
        videoLabels().volume,
        videoLabels().subtitles,
        videoLabels().audio,
        videoLabels().filters,
        videoLabels().fullscreen,
        videoLabels().pin,
      ];
      final rows = <int, int>{};
      for (final label in settings) {
        final y = tester.getCenter(find.byTooltip(label)).dy.round();
        rows[y] = (rows[y] ?? 0) + 1;
      }
      expect(rows.values.every((count) => count >= 2), isTrue);
      await _capture(tester, 'extended-${brightness.name}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('拖动和菜单展开时底栏保持，松手关菜单后恢复收起', (tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key));
    await tester.pumpAndSettle();
    final state = key.currentState!;
    final progress = find.byKey(const ValueKey('video-progress-bar'));
    final drag = await tester.startGesture(tester.getCenter(progress));
    await drag.moveBy(const Offset(60, 0));
    state.reader.updateMenuVisible(visible: false);
    await tester.pumpAndSettle();
    expect(state.panels.value, isTrue);
    expect(tester.getRect(progress).bottom, lessThan(600));
    await drag.up();
    await tester.pumpAndSettle();
    expect(state.panels.value, isFalse);
    expect(tester.getRect(progress).top, greaterThanOrEqualTo(600));

    state.reader.updateMenuVisible(visible: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(videoLabels().speed));
    await tester.pumpAndSettle();
    state.reader.updateMenuVisible(visible: false);
    await tester.pumpAndSettle();
    expect(state.panels.value, isTrue);
    expect(tester.getRect(progress).bottom, lessThan(600));
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(state.panels.value, isFalse);
    expect(tester.getRect(progress).top, greaterThanOrEqualTo(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭融合即时切换，独立进度位于阅读底栏上方且可拖动', (tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key));
    await tester.pumpAndSettle();
    key.currentState!.reader.updateTotalSlots(4);
    VideoSettingsStore.integrateControlsWithBottomBar.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-video-bottom-bar')), findsNothing);
    final progress = find.byKey(const ValueKey('video-progress-bar'));
    final pageSlider = find.byKey(const ValueKey('reader-page-slider'));
    expect(pageSlider, findsOneWidget);
    expect(
      tester.getRect(progress).bottom,
      lessThan(tester.getRect(pageSlider).top),
    );
    await tester.drag(progress, const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(key.currentState!.transport.seeks, isNotEmpty);
    await _capture(tester, 'separate');

    VideoSettingsStore.integrateControlsWithBottomBar.value = true;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('reader-video-bottom-bar')),
      findsOneWidget,
    );
    expect(progress, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭融合后仅显示视频时，较高呼出区仍允许鼠标预览和定位', (tester) async {
    VideoSettingsStore.integrateControlsWithBottomBar.value = false;
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key));
    await tester.pumpAndSettle();
    final state = key.currentState!;
    state.reader.updateMenuVisible(visible: false);
    await tester.pumpAndSettle();
    final progress = find.byKey(const ValueKey('video-progress-bar'));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(progress));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(progress));
    await tester.pumpAndSettle();
    expect(state.reader.state.isBottomHovered, isTrue);
    await mouse.moveTo(tester.getCenter(progress));
    await tester.pump();
    expect(find.byKey(const ValueKey('video-preview-busy')), findsOneWidget);
    await tester.tap(progress);
    await tester.pump();
    expect(state.transport.seeks, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  test('切页后旧页面释放不会清掉新页面；不同阅读器登记互不影响', () async {
    final first = ReaderVideoControlsSlot();
    final second = ReaderVideoControlsSlot();
    final panels = VideoPanelController();
    final oldOwner = Object();
    final newOwner = Object();
    ReaderVideoControls controls(Object owner) => ReaderVideoControls(
      owner: owner,
      isCurrent: () => true,
      builder: (_, _) => const SizedBox.shrink(),
      pinned: false,
      visible: true,
      panelsOpen: panels,
    );
    first.publish(controls(oldOwner));
    second.publish(controls(oldOwner));
    await Future<void>.value();
    first.publish(controls(newOwner));
    first.release(oldOwner);
    await Future<void>.value();
    expect(first.value?.owner, same(newOwner));
    expect(second.value?.owner, same(oldOwner));
    first.dispose();
    second.dispose();
    panels.dispose();
  });
}

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    this.brightness = Brightness.dark,
    this.scale = 1,
    this.extraControls = false,
    this.video = true,
  });
  final double scale;
  final bool extraControls;
  final bool video;
  final Brightness brightness;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> implements ReaderVideoHost {
  final reader = ReaderCubit()..updateMenuVisible(visible: true);
  final settings = _SettingsCubit();
  final transport = _Transport();
  late final controller = ReaderVideoController(
    host: this,
    progressKey: 'bottom-bar-test',
    transport: transport,
  );
  final panels = VideoPanelController();
  ReaderHoverController? hover;
  final scrubOwner = Object();
  ReaderVideoControlsSlot? slot;
  bool registered = false;

  @override
  void onVideoListEnded() {}
  @override
  void onVideoProgress(VideoPlaybackProgress progress) {}

  @override
  void dispose() {
    slot?.release(this);
    hover?.dispose();
    controller.dispose();
    panels.dispose();
    reader.close();
    settings.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('bottom-bar-preview'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: widget.brightness,
        fontFamily:
            const String.fromEnvironment('VIDEO_BOTTOM_BAR_PREVIEW_DIR').isEmpty
            ? null
            : 'VideoPreview',
      ),
      builder: (context, child) => mui.Theme(
        data: mui.ThemeData(
          useMaterial3: true,
          brightness: widget.brightness,
          fontFamily:
              const String.fromEnvironment(
                'VIDEO_BOTTOM_BAR_PREVIEW_DIR',
              ).isEmpty
              ? null
              : 'VideoPreview',
        ),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(widget.scale)),
          child: child!,
        ),
      ),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ReaderCubit>.value(value: reader),
          BlocProvider<GlobalSettingCubit>.value(value: settings),
        ],
        child: ReaderVideoControlsHost(
          onToggleControls: () => reader.updateMenuVisible(),
          child: Builder(
            builder: (context) {
              transport.extraTracks = widget.extraControls;
              hover ??= ReaderHoverController(context);
              slot = ReaderVideoControlsScope.of(context)!.slot;
              if (widget.video && !registered) {
                registered = true;
                slot!.publish(
                  ReaderVideoControls(
                    owner: this,
                    isCurrent: () => mounted,
                    pinned: false,
                    visible: true,
                    panelsOpen: panels,
                    builder: (embedded, visible) => VideoControlOverlay(
                      snapshot: controller.snapshot.copyWith(
                        playing: true,
                        duration: const Duration(seconds: 115),
                        currentTime: const Duration(seconds: 32),
                      ),
                      controller: controller,
                      filter: widget.extraControls
                          ? VideoFilterState.neutral
                          : null,
                      onFilterChanged: widget.extraControls ? (_) {} : null,
                      labels: videoLabels(),
                      pinned: false,
                      onTogglePin: () {},
                      panelsOpen: panels,
                      embedded: embedded,
                      progressUpdates: visible,
                      onScrubChanged: (value) =>
                          panels.setOpen(scrubOwner, value),
                    ),
                  ),
                );
              }
              return Scaffold(
                body: ReaderHoverScope(
                  controller: hover!,
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: ColoredBox(color: Color(0xff17191c)),
                      ),
                      Positioned.fill(
                        child: ReaderHoverRevealOverlay(controller: hover!),
                      ),
                      BottomWidget(
                        type: ComicEntryType.normal,
                        comicInfo: null,
                        sliderBuilder: (_) => const Expanded(
                          child: SizedBox(
                            key: ValueKey('reader-page-slider'),
                            height: 40,
                          ),
                        ),
                        order: 0,
                        epsNumber: 1,
                        comicId: 'test',
                        from: 'test',
                        jumpChapter: _JumpChapter(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _SettingsCubit extends GlobalSettingCubit {
  void showThumbnails() => emit(
    state.copyWith(
      readSetting: state.readSetting.copyWith(showThumbnailStrip: true),
    ),
  );
  _SettingsCubit() {
    emit(
      state.copyWith(
        readSetting: state.readSetting.copyWith(
          hoverRevealEnabled: true,
          hoverRevealBottom: true,
          hoverTriggerAreaBottom: 150,
          showThumbnailStrip: false,
        ),
      ),
    );
  }
}

class _JumpChapter implements JumpChapter {
  @override
  bool get havePrev => false;
  @override
  bool get haveNext => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transport implements VideoTransport {
  final seeks = <Duration>[];
  bool extraTracks = false;
  @override
  Future<void> seek(Duration to) async => seeks.add(to);
  @override
  List<VideoMediaTrack> get audioTracks => extraTracks
      ? const [
          VideoMediaTrack(id: '1', title: '主音轨'),
          VideoMediaTrack(id: '2', title: '备用音轨'),
        ]
      : const [];
  @override
  List<VideoMediaTrack> get subtitleTracks => const [];
  @override
  VideoMetadata get metadata => VideoMetadata.unknown;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('VIDEO_BOTTOM_BAR_PREVIEW_DIR');
  if (directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('bottom-bar-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
