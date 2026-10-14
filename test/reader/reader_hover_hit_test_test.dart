import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_state.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_chrome_transition.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_hover_reveal_layer.dart';
import 'package:zephyr/page/comic_read/widgets/overlay/page_count.dart';

class _Settings extends GlobalSettingCubit {
  _Settings(ReadSettingState setting) : super() {
    emit(state.copyWith(readSetting: setting));
  }
}

class _Preferences extends ComicReadPreferenceCubit {
  _Preferences({bool enableHover = false}) {
    if (enableHover) {
      emit(
        const ComicReadPreferenceState(
          override: (
            setting: ReadSettingState(hoverRevealEnabled: true),
            keys: {'hoverRevealEnabled'},
          ),
        ),
      );
    }
  }
}

/// 用生产 Stack 验证命中顺序；图片与状态浮层替身无需解码或启动模型。
Future<ReaderCubit> _pumpReader(
  WidgetTester tester, {
  bool indicator = false,
  bool animate = false,
  bool topInfo = false,
  bool perComicHover = false,
  VoidCallback? onTap,
  VoidCallback? onScroll,
}) async {
  final reader = ReaderCubit()..updateMenuVisible(visible: false);
  final settings = _Settings(
    ReadSettingState(
      hoverHideDelayMs: 100,
      hoverShowVisualIndicator: indicator,
      hoverRevealEnabled: !perComicHover,
      pageInfoShowNetwork: false,
      pageInfoShowTime: false,
      pageInfoVerticalPosition: topInfo
          ? ReaderInfoVerticalPosition.top
          : ReaderInfoVerticalPosition.bottom,
    ),
  );
  final preferences = _Preferences(enableHover: perComicHover);
  addTearDown(reader.close);
  addTearDown(settings.close);
  addTearDown(preferences.close);

  Widget bar(BuildContext context, bool top) {
    return Positioned(
      top: top ? 8 : null,
      bottom: top ? null : 8,
      left: 8,
      right: 8,
      child: BlocBuilder<ReaderCubit, ReaderState>(
        builder: (context, state) {
          final controller = ReaderHoverScope.of(context)!;
          return ReaderChromeTransition(
            visible: top
                ? state.showTopAppBar(pinned: false)
                : state.showBottomBar(pinned: false),
            top: top,
            animate: animate,
            child: MouseRegion(
              onEnter: (_) => top
                  ? controller.onEnterTopBar()
                  : controller.onEnterBottomBar(),
              onExit: (_) => top
                  ? controller.onExitTopBar()
                  : controller.onExitBottomBar(),
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  key: ValueKey(top ? 'top-bar' : 'bottom-bar'),
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(blurRadius: 24, color: Colors.black)],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ReaderCubit>.value(value: reader),
          BlocProvider<GlobalSettingCubit>.value(value: settings),
          BlocProvider<ComicReadPreferenceCubit>.value(value: preferences),
        ],
        child: Builder(
          builder: (context) {
            final effective = context.watchEffectiveReadSetting();
            final controller = ReaderHoverController(context)
              ..updateContext(context, readSetting: effective);
            addTearDown(controller.dispose);
            return ReaderHoverScope(
              controller: controller,
              child: ReaderHoverStack(
                controller: controller,
                readSetting: effective,
                children: [
                  Positioned.fill(
                    child: Listener(
                      onPointerSignal: (_) => onScroll?.call(),
                      child: GestureDetector(
                        onTap: onTap,
                        child: const ColoredBox(color: Colors.grey),
                      ),
                    ),
                  ),
                  const PageCountWidget(epPages: '10'),
                  bar(context, true),
                  bar(context, false),
                  const Positioned.fill(
                    child: MouseRegion(
                      opaque: false,
                      hitTestBehavior: HitTestBehavior.translucent,
                      child: IgnorePointer(child: SizedBox.expand()),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return reader;
}

Future<void> _disposeReader(WidgetTester tester) async {
  tester
      .widget<ReaderHoverStack>(find.byType(ReaderHoverStack))
      .controller
      .dispose();
  await tester.pumpWidget(const SizedBox());
}

void main() {
  for (final top in [false, true]) {
    testWidgets('实际页码底板上悬停也能唤出对应栏（top=$top）', (tester) async {
      final reader = await _pumpReader(tester, topInfo: top);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(400, 300));
      await mouse.moveTo(tester.getCenter(find.text('1/10')));
      await tester.pump();
      expect(
        top ? reader.state.isTopHovered : reader.state.isBottomHovered,
        isTrue,
      );
      await mouse.removePointer();
      await _disposeReader(tester);
    });
  }

  testWidgets('本漫开启悬停时不被全局关闭值阻止', (tester) async {
    final reader = await _pumpReader(tester, perComicHover: true);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 300));
    await mouse.moveTo(const Offset(400, 20));
    await tester.pump();
    expect(reader.state.isTopHovered, isTrue);
    await mouse.moveTo(const Offset(400, 580));
    await tester.pump();
    expect(reader.state.isBottomHovered, isTrue);
    await mouse.removePointer();
    await _disposeReader(tester);
  });

  testWidgets('感应带内移动可以恢复丢失的唤出状态', (tester) async {
    final reader = await _pumpReader(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 300));
    // x=2 避开栏体，只依赖感应带。
    await mouse.moveTo(const Offset(2, 20));
    await tester.pump();
    reader.resetHoverState();
    await tester.pump();
    expect(reader.state.isTopHovered, isFalse);
    await mouse.moveTo(const Offset(3, 20));
    await tester.pump();
    expect(reader.state.isTopHovered, isTrue);
    await mouse.moveTo(const Offset(2, 580));
    await tester.pump();
    reader.resetHoverState();
    await tester.pump();
    await mouse.moveTo(const Offset(3, 580));
    await tester.pump();
    expect(reader.state.isBottomHovered, isTrue);
    await mouse.removePointer();
    await _disposeReader(tester);
  });

  for (final animate in [false, true]) {
    testWidgets('阴影、栏内按钮与连续唤出收起（animate=$animate）', (tester) async {
      var taps = 0;
      final reader = await _pumpReader(
        tester,
        animate: animate,
        onTap: () => taps++,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(400, 300));
      for (var i = 0; i < 12; i++) {
        for (final top in [true, false]) {
          final edge = Offset(400, top ? 20 : 580);
          await mouse.moveTo(edge);
          await tester.pumpAndSettle();
          expect(
            top ? reader.state.isTopHovered : reader.state.isBottomHovered,
            isTrue,
          );
          // 离开触发带但留在栏本体内，不能被延时隐藏。
          await mouse.moveTo(Offset(400, top ? 60 : 540));
          await tester.pump(const Duration(seconds: 1));
          expect(
            top ? reader.state.isTopHovered : reader.state.isBottomHovered,
            isTrue,
          );
          await mouse.moveTo(edge);
          await mouse.down(edge);
          await mouse.up();
          await tester.pump();
          expect(taps, i * 2 + (top ? 1 : 2));
          await mouse.moveTo(const Offset(400, 300));
          await tester.pumpAndSettle();
          expect(reader.state.isTopHovered, isFalse);
          expect(reader.state.isBottomHovered, isFalse);
        }
        reader.updateCurrentSlot(i);
        await tester.pump(const Duration(minutes: 1));
      }
      await mouse.removePointer();
      await _disposeReader(tester);
    });
  }

  testWidgets('提示线不拦截页面点击与滚动', (tester) async {
    var taps = 0;
    var scrolls = 0;
    await _pumpReader(
      tester,
      indicator: true,
      onTap: () => taps++,
      onScroll: () => scrolls++,
    );
    // 提示线在 x=24..776、y=30..32；触屏不能把装饰当作点击目标。
    await tester.tapAt(const Offset(400, 31));
    await tester.pump();
    expect(taps, 1);
    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(400, 31),
        scrollDelta: Offset(0, 40),
      ),
    );
    await tester.pump();
    expect(scrolls, 1);
    await _disposeReader(tester);
  });
}
