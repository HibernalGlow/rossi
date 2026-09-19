import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_state.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_hover_reveal_layer.dart';

class _TestGlobalSettingCubit extends GlobalSettingCubit {
  _TestGlobalSettingCubit({ReadSettingState? readSetting}) : super() {
    if (readSetting != null) {
      emit(state.copyWith(readSetting: readSetting));
    }
  }
}

Widget _buildHarness({
  required ReaderCubit readerCubit,
  required GlobalSettingCubit settingCubit,
  required Widget child,
}) {
  return MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ReaderCubit>.value(value: readerCubit),
        BlocProvider<GlobalSettingCubit>.value(value: settingCubit),
      ],
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('ReaderState & ReaderCubit Hover Logic', () {
    test('showTopAppBar and showBottomBar derive correctly from menu and hover state', () {
      const state1 = ReaderState(
        isMenuVisible: false,
        isTopHovered: false,
        isBottomHovered: false,
      );
      expect(state1.showTopAppBar, isFalse);
      expect(state1.showBottomBar, isFalse);

      // Top hovered only
      final stateTop = state1.copyWith(isTopHovered: true);
      expect(stateTop.showTopAppBar, isTrue);
      expect(stateTop.showBottomBar, isFalse);

      // Bottom hovered only
      final stateBottom = state1.copyWith(isBottomHovered: true);
      expect(stateBottom.showTopAppBar, isFalse);
      expect(stateBottom.showBottomBar, isTrue);

      // Menu visible overrides both
      final stateMenu = state1.copyWith(isMenuVisible: true);
      expect(stateMenu.showTopAppBar, isTrue);
      expect(stateMenu.showBottomBar, isTrue);
    });

    test('ReaderCubit hover methods update state and reset properly', () {
      final cubit = ReaderCubit();
      expect(cubit.state.isTopHovered, isFalse);
      expect(cubit.state.isBottomHovered, isFalse);

      cubit.setTopHovered(true);
      expect(cubit.state.isTopHovered, isTrue);

      cubit.setBottomHovered(true);
      expect(cubit.state.isBottomHovered, isTrue);

      cubit.resetHoverState();
      expect(cubit.state.isTopHovered, isFalse);
      expect(cubit.state.isBottomHovered, isFalse);
    });
  });

  group('ReaderHoverController Behavior', () {
    testWidgets('Top trigger and bar hover with delay hide', (tester) async {
      final readerCubit = ReaderCubit();
      // Menu hidden so hover drives visibility
      readerCubit.updateMenuVisible(visible: false);

      final settingCubit = _TestGlobalSettingCubit(
        readSetting: const ReadSettingState(
          hoverRevealEnabled: true,
          hoverRevealTop: true,
          hoverRevealBottom: true,
          hoverHideDelayMs: 200,
        ),
      );

      late ReaderHoverController controller;

      await tester.pumpWidget(
        _buildHarness(
          readerCubit: readerCubit,
          settingCubit: settingCubit,
          child: Builder(
            builder: (context) {
              controller = ReaderHoverController(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(readerCubit.state.isTopHovered, isFalse);
      expect(readerCubit.state.showTopAppBar, isFalse);

      // 1. Mouse enters top trigger
      controller.onEnterTopTrigger();
      expect(readerCubit.state.isTopHovered, isTrue);
      expect(readerCubit.state.showTopAppBar, isTrue);

      // 2. Mouse moves from trigger to top bar
      controller.onEnterTopBar();
      controller.onExitTopTrigger();
      expect(readerCubit.state.isTopHovered, isTrue);

      // 3. Mouse exits top bar -> starts 200ms timer
      controller.onExitTopBar();
      // Before delay expires, it should remain true
      await tester.pump(const Duration(milliseconds: 100));
      expect(readerCubit.state.isTopHovered, isTrue);

      // After delay expires, it should be false
      await tester.pump(const Duration(milliseconds: 150));
      expect(readerCubit.state.isTopHovered, isFalse);
      expect(readerCubit.state.showTopAppBar, isFalse);

      controller.dispose();
    });

    testWidgets('Re-entering top bar cancels scheduled hide timer', (tester) async {
      final readerCubit = ReaderCubit();
      readerCubit.updateMenuVisible(visible: false);

      final settingCubit = _TestGlobalSettingCubit(
        readSetting: const ReadSettingState(
          hoverRevealEnabled: true,
          hoverRevealTop: true,
          hoverHideDelayMs: 300,
        ),
      );

      late ReaderHoverController controller;

      await tester.pumpWidget(
        _buildHarness(
          readerCubit: readerCubit,
          settingCubit: settingCubit,
          child: Builder(
            builder: (context) {
              controller = ReaderHoverController(context);
              return const SizedBox();
            },
          ),
        ),
      );

      controller.onEnterTopTrigger();
      controller.onExitTopTrigger();

      // Wait 150ms of the 300ms delay
      await tester.pump(const Duration(milliseconds: 150));
      expect(readerCubit.state.isTopHovered, isTrue);

      // User moves mouse back into top bar before timer fires
      controller.onEnterTopBar();
      // Wait for original timer duration to pass
      await tester.pump(const Duration(milliseconds: 200));
      // Should still be hovered because re-entering cancelled timer
      expect(readerCubit.state.isTopHovered, isTrue);

      controller.dispose();
    });

    testWidgets('Bottom trigger activates bottom hover and respects delay', (tester) async {
      final readerCubit = ReaderCubit();
      readerCubit.updateMenuVisible(visible: false);

      final settingCubit = _TestGlobalSettingCubit(
        readSetting: const ReadSettingState(
          hoverRevealEnabled: true,
          hoverRevealBottom: true,
          hoverHideDelayMs: 200,
        ),
      );

      late ReaderHoverController controller;

      await tester.pumpWidget(
        _buildHarness(
          readerCubit: readerCubit,
          settingCubit: settingCubit,
          child: Builder(
            builder: (context) {
              controller = ReaderHoverController(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(readerCubit.state.isBottomHovered, isFalse);

      controller.onEnterBottomTrigger();
      expect(readerCubit.state.isBottomHovered, isTrue);
      expect(readerCubit.state.showBottomBar, isTrue);

      controller.onExitBottomTrigger();
      await tester.pump(const Duration(milliseconds: 100));
      expect(readerCubit.state.isBottomHovered, isTrue);

      await tester.pump(const Duration(milliseconds: 150));
      expect(readerCubit.state.isBottomHovered, isFalse);
      expect(readerCubit.state.showBottomBar, isFalse);

      controller.dispose();
    });

    testWidgets('Disabled hover settings prevent activation', (tester) async {
      final readerCubit = ReaderCubit();
      readerCubit.updateMenuVisible(visible: false);

      // Entire hover reveal disabled
      final settingCubit = _TestGlobalSettingCubit(
        readSetting: const ReadSettingState(
          hoverRevealEnabled: false,
          hoverRevealTop: true,
          hoverRevealBottom: true,
        ),
      );

      late ReaderHoverController controller;

      await tester.pumpWidget(
        _buildHarness(
          readerCubit: readerCubit,
          settingCubit: settingCubit,
          child: Builder(
            builder: (context) {
              controller = ReaderHoverController(context);
              return const SizedBox();
            },
          ),
        ),
      );

      controller.onEnterTopTrigger();
      expect(readerCubit.state.isTopHovered, isFalse);

      controller.onEnterBottomTrigger();
      expect(readerCubit.state.isBottomHovered, isFalse);

      controller.dispose();
    });

    testWidgets('Manual menu or slider roll locks bars open and prevents hide', (tester) async {
      final readerCubit = ReaderCubit();
      readerCubit.updateMenuVisible(visible: true); // Menu manually open

      final settingCubit = _TestGlobalSettingCubit(
        readSetting: const ReadSettingState(
          hoverRevealEnabled: true,
          hoverRevealTop: true,
          hoverHideDelayMs: 100,
        ),
      );

      late ReaderHoverController controller;

      await tester.pumpWidget(
        _buildHarness(
          readerCubit: readerCubit,
          settingCubit: settingCubit,
          child: Builder(
            builder: (context) {
              controller = ReaderHoverController(context);
              return const SizedBox();
            },
          ),
        ),
      );

      // Trigger top hover then exit
      controller.onEnterTopTrigger();
      controller.onExitTopTrigger();

      await tester.pump(const Duration(milliseconds: 200));

      // showTopAppBar stays true because isMenuVisible is true
      expect(readerCubit.state.showTopAppBar, isTrue);

      controller.dispose();
    });
  });

  group('ReaderHoverRevealOverlay Widget', () {
    testWidgets('Renders top and bottom trigger areas with configured heights', (tester) async {
      final readerCubit = ReaderCubit();
      final settingCubit = _TestGlobalSettingCubit(
        readSetting: const ReadSettingState(
          hoverRevealEnabled: true,
          hoverRevealTop: true,
          hoverRevealBottom: true,
          hoverTriggerAreaTop: 45,
          hoverTriggerAreaBottom: 50,
          hoverShowVisualIndicator: true,
        ),
      );

      late ReaderHoverController controller;

      await tester.pumpWidget(
        _buildHarness(
          readerCubit: readerCubit,
          settingCubit: settingCubit,
          child: Builder(
            builder: (context) {
              controller = ReaderHoverController(context);
              return Stack(
                children: [
                  ReaderHoverRevealOverlay(controller: controller),
                ],
              );
            },
          ),
        ),
      );

      expect(find.byType(ReaderHoverRevealOverlay), findsOneWidget);

      final overlayMouseRegions = find.descendant(
        of: find.byType(ReaderHoverRevealOverlay),
        matching: find.byType(MouseRegion),
      );
      // Overlay has 2 MouseRegions (one top trigger, one bottom trigger)
      expect(overlayMouseRegions, findsNWidgets(2));

      // Find Positioned widgets corresponding to 45 and 50 px heights
      final positionedWidgets = tester
          .widgetList<Positioned>(
            find.descendant(
              of: find.byType(ReaderHoverRevealOverlay),
              matching: find.byType(Positioned),
            ),
          )
          .toList();

      expect(positionedWidgets.any((p) => p.height == 45 && p.top == 0), isTrue);
      expect(positionedWidgets.any((p) => p.height == 50 && p.bottom == 0), isTrue);

      controller.dispose();
    });

    testWidgets('Does not render trigger areas when hoverRevealEnabled is false', (tester) async {
      final readerCubit = ReaderCubit();
      final settingCubit = _TestGlobalSettingCubit(
        readSetting: const ReadSettingState(
          hoverRevealEnabled: false,
        ),
      );

      late ReaderHoverController controller;

      await tester.pumpWidget(
        _buildHarness(
          readerCubit: readerCubit,
          settingCubit: settingCubit,
          child: Builder(
            builder: (context) {
              controller = ReaderHoverController(context);
              return Stack(
                children: [
                  ReaderHoverRevealOverlay(controller: controller),
                ],
              );
            },
          ),
        ),
      );

      final overlayMouseRegions = find.descendant(
        of: find.byType(ReaderHoverRevealOverlay),
        matching: find.byType(MouseRegion),
      );
      expect(overlayMouseRegions, findsNothing);

      controller.dispose();
    });

    testWidgets('Pointer hover over overlay triggers onEnterTopTrigger and onExitTopTrigger', (tester) async {
      final readerCubit = ReaderCubit();
      readerCubit.updateMenuVisible(visible: false);

      final settingCubit = _TestGlobalSettingCubit(
        readSetting: const ReadSettingState(
          hoverRevealEnabled: true,
          hoverRevealTop: true,
          hoverTriggerAreaTop: 50,
          hoverHideDelayMs: 200,
        ),
      );

      late ReaderHoverController controller;

      await tester.pumpWidget(
        _buildHarness(
          readerCubit: readerCubit,
          settingCubit: settingCubit,
          child: SizedBox(
            width: 800,
            height: 600,
            child: Builder(
              builder: (context) {
                controller = ReaderHoverController(context);
                return ReaderHoverScope(
                  controller: controller,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ReaderHoverRevealOverlay(controller: controller),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(readerCubit.state.isTopHovered, isFalse);

      // Move mouse into center first
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(400, 300));
      await tester.pump();

      expect(readerCubit.state.isTopHovered, isFalse);

      // Move mouse into top trigger zone (400, 20)
      await gesture.moveTo(const Offset(400, 20));
      await tester.pump();

      expect(readerCubit.state.isTopHovered, isTrue);
      expect(readerCubit.state.showTopAppBar, isTrue);

      // Move mouse out to center (400, 200)
      await gesture.moveTo(const Offset(400, 200));
      await tester.pump();

      // Within delay (100ms < 200ms), still hovered
      await tester.pump(const Duration(milliseconds: 100));
      expect(readerCubit.state.isTopHovered, isTrue);

      // After delay (150ms > 200ms total), top hover is removed
      await tester.pump(const Duration(milliseconds: 150));
      expect(readerCubit.state.isTopHovered, isFalse);

      await gesture.removePointer();
      controller.dispose();
    });
  });
}
