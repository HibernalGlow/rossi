// macOS 原生全屏时「顶边归谁」的判据。
//
// 用户报的症状：全屏阅读里推到屏幕顶唤出阅读器顶栏，会**同时**唤出系统的
// 菜单栏与红绿灯，红绿灯压在顶栏左上角那颗返回/退出上，等于出不来全屏。
// 根因是一条物理边有两个主人 —— 感应带与顶栏本体都写死 `top: 0`
// （`reader_hover_reveal_layer.dart` 的顶部带 / `app_bar.dart` 的 `Positioned`）。
//
// 修法是「让开那一条」，所以这里钉四件事：
//   1. 让多少是**纯函数**，且只有 macOS + 窗口全屏这一档非 0（其余平台逐字不变）；
//   2. 感应带与顶栏本体**读的是同一个值**（一处让了、一处没让就是原来的病）；
//   3. 往返：窗口退出全屏要收回 0，不然非全屏也永远矮一截；
//   4. `padding.top` 非 0 时不许**加两次**（系统栏露出那一瞬间会跳），
//      同时非全屏那一档的 `SafeArea` 内缩必须照旧（移动端靠它）。
//
// 判「让没让」一律看矩形，不 `findsNothing` 式地糊过去。
//
// `isMacOS` 由测试注入，不读宿主机：跑这条的机器是 Linux 时
// `Platform.isMacOS` 为 `false`，不注入就会假绿。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/desktop/reader_macos_top_chrome_inset_test.dart

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_presentation_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/app_bar.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_hover_reveal_layer.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_top_chrome_inset.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/service/reader/reader_desktop_fullscreen_service.dart';

const _reserve = kMacOsFullscreenChromeHeight;

/// 顶栏主行第一颗图标钮的中心 y —— 顶栏整体下移多少，它就跟着下移多少。
double _barTop(WidgetTester tester) =>
    tester.getRect(find.byType(ReaderToolbarIconButton).first).top;

/// 顶部唤出感应带的矩形（Stack 子节点顺序：带顶的 `MouseRegion` 在前）。
Rect _bandRect(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(ReaderHoverRevealOverlay),
        matching: find.byType(MouseRegion),
      )
      .first,
);

Future<void> _pump(
  WidgetTester tester, {
  required bool isMacOS,
  bool withScope = true,
  double paddingTop = 0,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  if (paddingTop > 0) tester.view.padding = FakeViewPadding(top: paddingTop);
  addTearDown(tester.view.reset);

  final settings = GlobalSettingCubit();
  final presentation = ReaderPresentationCubit(settings: settings);
  late final ReaderHoverController controller;
  final readerCubit = ReaderCubit();

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: settings),
        BlocProvider(create: (_) => readerCubit),
        BlocProvider.value(value: presentation),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              controller = ReaderHoverController(context);
              final layer = Stack(
                children: [
                  ReaderHoverRevealOverlay(controller: controller),
                  ComicReadAppBar(
                    title: '第 3 话',
                    comicTitle: '书名',
                    changePageIndex: (_) {},
                    onToggleFullscreen: () {},
                    isDesktopFullscreen: true,
                  ),
                ],
              );
              return withScope
                  ? ReaderHoverScope(
                      controller: controller,
                      isMacOS: isMacOS,
                      child: layer,
                    )
                  : layer;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // 服务单例的构造函数会登记 `windowManager` 监听，那需要 binding 先就位。
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ReaderDesktopFullscreenService.instance;

  setUp(() {
    service.syncFullscreen(false);
    expect(service.fullscreenNotifier.value, isFalse, reason: '前置：非全屏');
  });
  tearDown(() => service.syncFullscreen(false));

  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  group('让多少是纯函数', () {
    test('只有 macOS + 窗口全屏这一档非 0', () {
      expect(
        resolveReaderTopChromeReserve(isMacOS: false, isOsFullscreen: false),
        0,
      );
      // 移动端 / Windows / Linux 全屏：逐字保持改造前的 0。
      expect(
        resolveReaderTopChromeReserve(isMacOS: false, isOsFullscreen: true),
        0,
      );
      // macOS 窗口内（自制标题栏占自己那一行）也不该让。
      expect(
        resolveReaderTopChromeReserve(isMacOS: true, isOsFullscreen: false),
        0,
      );
      expect(
        resolveReaderTopChromeReserve(isMacOS: true, isOsFullscreen: true),
        _reserve,
      );
    });

    test('让出量至少盖得住红绿灯那一截', () {
      // 40 这个数与 `custom_title_bar.dart` 的栏高同源；改成 24 就只够菜单栏、
      // 红绿灯仍然压在顶栏第一行上 —— 那条 bug 会原地复活。
      expect(_reserve, greaterThanOrEqualTo(37));
    });
  });

  group('感应带与顶栏本体让的是同一个值', () {
    testWidgets('macOS 全屏：两者都下移，且都正好一个让出量', (tester) async {
      await _pump(tester, isMacOS: true);
      final bandBefore = _bandRect(tester).top;
      final barBefore = _barTop(tester);

      service.onWindowEnterFullScreen();
      await tester.pumpAndSettle();

      expect(_bandRect(tester).top, bandBefore + _reserve, reason: '顶边让给系统');
      expect(_barTop(tester), barBefore + _reserve, reason: '顶栏不许留在原地');
    });

    testWidgets('往返：退出全屏收回 0，不会永远矮一截', (tester) async {
      await _pump(tester, isMacOS: true);
      final barBefore = _barTop(tester);

      service.onWindowEnterFullScreen();
      await tester.pumpAndSettle();
      expect(_barTop(tester), isNot(barBefore));

      service.onWindowLeaveFullScreen();
      await tester.pumpAndSettle();
      expect(_barTop(tester), barBefore, reason: '窗口事件是双向的，让位也得是');
      expect(_bandRect(tester).top, 0);
    });

    testWidgets('不是 macOS 就一动不动', (tester) async {
      await _pump(tester, isMacOS: false);
      final barBefore = _barTop(tester);
      final bandBefore = _bandRect(tester).top;

      service.onWindowEnterFullScreen();
      await tester.pumpAndSettle();

      expect(_barTop(tester), barBefore);
      expect(_bandRect(tester).top, bandBefore);
    });

    testWidgets('作用域不在场时按 0 走（单独 pump 顶栏的宿主）', (tester) async {
      await _pump(tester, isMacOS: true, withScope: false);
      final barBefore = _barTop(tester);

      service.onWindowEnterFullScreen();
      await tester.pumpAndSettle();

      expect(_barTop(tester), barBefore);
      expect(_bandRect(tester).top, 0);
    });
  });

  group('顶部内缩不许加两次', () {
    testWidgets('全屏时 padding.top 非 0 也不叠加', (tester) async {
      await _pump(tester, isMacOS: true);
      service.onWindowEnterFullScreen();
      await tester.pumpAndSettle();
      final fullscreenTop = _barTop(tester);

      await _pump(tester, isMacOS: true, paddingTop: 25);
      service.onWindowEnterFullScreen();
      await tester.pumpAndSettle();

      // 系统栏露出的那一瞬间 `padding.top` 会从 0 跳到 ~25：让出量已经 ≥ 它，
      // 所以顶栏必须停在同一个位置，而不是当场再往下跳 25。
      expect(_barTop(tester), fullscreenTop, reason: '两处一起加就是顶栏跳一下');
    });

    testWidgets('非全屏时 SafeArea 的内缩照旧（移动端靠这条）', (tester) async {
      await _pump(tester, isMacOS: true);
      final noPaddingTop = _barTop(tester);

      await _pump(tester, isMacOS: true, paddingTop: 25);
      expect(
        _barTop(tester),
        greaterThan(noPaddingTop + 20),
        reason: '不全屏时仍要让出状态栏那一截，别把手机也一起改了',
      );
    });
  });
}
