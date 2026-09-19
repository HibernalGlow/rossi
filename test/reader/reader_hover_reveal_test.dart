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
    test(
      'showTopAppBar and showBottomBar derive correctly from menu and hover state',
      () {
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
      },
    );

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

    testWidgets('Re-entering top bar cancels scheduled hide timer', (
      tester,
    ) async {
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

    testWidgets('Bottom trigger activates bottom hover and respects delay', (
      tester,
    ) async {
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

    testWidgets(
      'Manual menu or slider roll locks bars open and prevents hide',
      (tester) async {
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
      },
    );
  });

  // ── 这一组盯的是用户报的那个 bug ──────────────────────────────────────────
  //
  // 「点一下 read 中间换出顶栏和底栏之后，再点一下就只有顶栏会消失，底栏不消失」
  //
  // 不是两条栏各写了一半，而是**悬停标记被永久留在 true 上**：
  // `showTopAppBar = isMenuVisible || isTopHovered`、
  // `showBottomBar = isMenuVisible || isBottomHovered`，被 OR 住的那一条收不起来。
  //
  // 标记残留的来路：`_checkScheduleHide*` 在锁（`isMenuVisible` / `isSliderRolling`）
  // 期间**故意**不排收起定时器，而 `setTopHovered(false)` 只有那条定时器会调 ——
  // 于是「指针在锁着的时候离开唤出区」这一下就被整个丢掉了。
  //
  // 判据必须包含**反向**那一条（指针还在栏上时不许收），否则修法很容易退化成
  // 「解锁就把两条栏一起清掉」，那样滑块拖到一半松手、鼠标还停在底栏上的用户会
  // 眼睁睁看着栏从手底下被抽走。
  group('悬停标记与锁（点击收紧 chrome 这件事的判据）', () {
    test('锁解除的判据只看「刚变」，不看当前值', () {
      const locked = ReaderState(isMenuVisible: true);
      const unlocked = ReaderState(isMenuVisible: false);

      expect(
        isHoverRevealLockReleased(locked, unlocked),
        isTrue,
        reason: '菜单刚收起 ⇒ 需要对账',
      );
      expect(
        isHoverRevealLockReleased(unlocked, unlocked),
        isFalse,
        reason: '一直没锁 ⇒ 每次状态变化都对账会把用户正悬停着的那条栏收走',
      );
      expect(
        isHoverRevealLockReleased(unlocked, locked),
        isFalse,
        reason: '刚锁上 ⇒ 锁着的时候本来就不收栏，没账可对',
      );
      expect(
        isHoverRevealLockReleased(
          const ReaderState(isSliderRolling: true),
          const ReaderState(isSliderRolling: false),
        ),
        isTrue,
        reason: '滑块松手同样是解锁',
      );
    });

    testWidgets('菜单展开期间指针离开唤出区 ⇒ 收起菜单时底栏必须跟着收（原来会卡住）', (tester) async {
      final readerCubit = ReaderCubit();
      readerCubit.updateMenuVisible(visible: false);

      final settingCubit = _TestGlobalSettingCubit(
        readSetting: const ReadSettingState(
          hoverRevealEnabled: true,
          hoverRevealBottom: true,
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

      // 1. 指针进底部唤出区 ⇒ 底栏滑出来
      controller.onEnterBottomTrigger();
      expect(readerCubit.state.showBottomBar, isTrue);

      // 2. 指针离开唤出区，而**这一刻菜单正展开着**（用户刚在中间点了一下）
      readerCubit.updateMenuVisible(visible: true);
      controller.onExitBottomTrigger();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        readerCubit.state.isBottomHovered,
        isTrue,
        reason: '锁着的时候不排收起定时器是对的：菜单展开时上下栏本就该在',
      );

      // 3. 再点一下中间收起菜单（锁解除）⇒ 悬停标记必须与指针实际位置对账
      readerCubit.updateMenuVisible(visible: false);
      controller.syncHoveredWithPointer();

      expect(readerCubit.state.isBottomHovered, isFalse);
      expect(
        readerCubit.state.showBottomBar,
        isFalse,
        reason:
            '底栏不跟着顶栏一起滑走，就是用户报的那个 bug：'
            'showBottomBar 被残留的 isBottomHovered 永久 OR 住。'
            '接线点在 ComicReadSuccessWidget 的 BlocListener.listenWhen',
      );

      controller.dispose();
    });

    testWidgets('指针仍停在底栏上时解锁 ⇒ 只收走指针已经离开的那一条', (tester) async {
      final readerCubit = ReaderCubit();
      readerCubit.updateMenuVisible(visible: false);

      final settingCubit = _TestGlobalSettingCubit(
        readSetting: const ReadSettingState(
          hoverRevealEnabled: true,
          hoverRevealTop: true,
          hoverRevealBottom: true,
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

      // 指针停在底栏本体上（拖滑块/点按钮的那种姿态），顶栏只是路过过
      controller.onEnterBottomBar();
      readerCubit.updateMenuVisible(visible: true); // 锁上
      controller.onEnterTopTrigger();
      controller.onExitTopTrigger(); // 顶着锁离开 ⇒ 顶栏的标记同样会残留

      readerCubit.updateMenuVisible(visible: false); // 解锁
      controller.syncHoveredWithPointer();

      expect(readerCubit.state.isTopHovered, isFalse);
      expect(readerCubit.state.showTopAppBar, isFalse, reason: '顶栏指针已经走了');
      expect(
        readerCubit.state.showBottomBar,
        isTrue,
        reason: '指针还压在底栏上 ⇒ 不许把栏从手底下抽走',
      );

      controller.dispose();
    });
  });

  group('ReaderHoverRevealOverlay Widget', () {
    testWidgets(
      'Renders top and bottom trigger areas with configured heights',
      (tester) async {
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
                  children: [ReaderHoverRevealOverlay(controller: controller)],
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

        expect(
          positionedWidgets.any((p) => p.height == 45 && p.top == 0),
          isTrue,
        );
        expect(
          positionedWidgets.any((p) => p.height == 50 && p.bottom == 0),
          isTrue,
        );

        controller.dispose();
      },
    );

    testWidgets(
      'Does not render trigger areas when hoverRevealEnabled is false',
      (tester) async {
        final readerCubit = ReaderCubit();
        final settingCubit = _TestGlobalSettingCubit(
          readSetting: const ReadSettingState(hoverRevealEnabled: false),
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
                  children: [ReaderHoverRevealOverlay(controller: controller)],
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
      },
    );

    testWidgets(
      'Pointer hover over overlay triggers onEnterTopTrigger and onExitTopTrigger',
      (tester) async {
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
                          child: ReaderHoverRevealOverlay(
                            controller: controller,
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

        expect(readerCubit.state.isTopHovered, isFalse);

        // Move mouse into center first
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
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
      },
    );
  });
}
