// 顶栏主行的排布判据。
//
// 用户报的症状是「功能图标堆在一起」。改造前那一行是三种边长（30 圆钮 /
// 40 方 IconButton / 36 自绘框）并排、彼此只差 2~4px，窄窗还会挤出黄黑斜纹。
// 所以这里钉四件事，每一件都是「analyze 与编译证明不了」的那类：
//
//   1. **宽度分档是纯函数**，边界只写在一处（`reader_top_bar_style.dart`）；
//   2. 十档宽度下主行**零溢出** —— RenderFlex 溢出会让 pump 直接失败，
//      这条以前只能靠实机肉眼抓（上一轮就是这么发现溢出条纹的）；
//   3. 主行上所有图标按钮是**同一个几何**（40×40）；
//   4. 窄档让位的是**整组**（视图三项 + 钉住 + 全屏 + 下载进「更多」），
//      而超分芯片与自动滚屏按用户口径**永不折叠** —— 它们是最常用的那一档。
//
// 只 pump 顶栏本体：`from` 留空 ⇒ 下载那颗不出现，不牵 ObjectBox 与下载队列；
// `LocalReadSession.instance.presenter` 默认为 null ⇒ 超分芯片走 shrink 分支。

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_presentation_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/app_bar.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/auto_scroll_quick_button.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_upscale_status_chip.dart';
import 'package:zephyr/util/reader/reader_top_bar_style.dart';

/// 把顶栏按给定宽度画出来。
///
/// [withFullscreen] = 桌面端那一档（有全屏可切），它会让窗口组多出一颗按钮，
/// 所以宽度预算必须按它算 —— 移动端没这颗是**巧合**，不是判据。
Future<void> _paintBar(
  WidgetTester tester,
  double width, {
  bool withFullscreen = true,
}) async {
  // 把**视口**改成这个宽度：默认测试画布只有 800×600，用 SizedBox 撑到 1280
  // 会被画布夹回 800，宽档与中档就成了同一档 —— 那样这条扫描什么也没验。
  tester.view.physicalSize = Size(width, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final settings = GlobalSettingCubit();
  final presentation = ReaderPresentationCubit(settings: settings);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: settings),
        BlocProvider(create: (_) => ReaderCubit()),
        BlocProvider.value(value: presentation),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ComicReadAppBar(
                title: '第 3 话',
                comicTitle: '这是用来验证省略的一本很长的书名',
                changePageIndex: (_) {},
                onToggleFullscreen: withFullscreen ? () {} : null,
                isDesktopFullscreen: withFullscreen,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 顶栏主行画出来的那几颗图标按钮（菜单没打开时菜单项不在树里）。
Finder _barButtons() => find.byType(ReaderToolbarIconButton);

void main() {
  // 超分总闸存在 SharedPreferences 里：不给 mock，那颗芯片会永远停在「还在读」
  // 的那一帧，测试看到的就是一颗没有内容的空壳。
  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  group('宽度分档是纯函数', () {
    test('三档的边界各只有一条线', () {
      expect(
        resolveReaderToolbarTier(
          ReaderTopBarStyleLimits.labeledToolbarMinWidth,
        ),
        ReaderToolbarTier.wide,
      );
      expect(
        resolveReaderToolbarTier(
          ReaderTopBarStyleLimits.labeledToolbarMinWidth - 1,
        ),
        ReaderToolbarTier.medium,
      );
      // 阈值本身也是判据：改了数就得改这份说明。
      expect(ReaderTopBarStyleLimits.labeledToolbarMinWidth, 1060);
      expect(ReaderTopBarStyleLimits.expandedLayoutMinWidth, 880);
      expect(
        resolveReaderToolbarTier(
          ReaderTopBarStyleLimits.expandedLayoutMinWidth,
        ),
        ReaderToolbarTier.medium,
      );
      expect(
        resolveReaderToolbarTier(
          ReaderTopBarStyleLimits.expandedLayoutMinWidth - 1,
        ),
        ReaderToolbarTier.narrow,
      );
    });

    test('每一档让什么、留什么，只有这一处口径', () {
      expect(ReaderToolbarTier.wide.expandsLayoutGroup, isTrue);
      expect(ReaderToolbarTier.wide.showsChipLabels, isTrue);
      expect(ReaderToolbarTier.wide.keepsViewControlsInline, isTrue);
      expect(ReaderToolbarTier.wide.keepsWindowControlsInline, isTrue);
      // 中档：组还在，但文字收掉，且钉住/全屏先让位。
      expect(ReaderToolbarTier.medium.showsChipLabels, isFalse);
      expect(ReaderToolbarTier.medium.keepsViewControlsInline, isTrue);
      expect(ReaderToolbarTier.medium.keepsWindowControlsInline, isFalse);
      // 窄档：版式组并成一颗循环按钮，视图三项与下载整组进菜单。
      expect(ReaderToolbarTier.narrow.expandsLayoutGroup, isFalse);
      expect(ReaderToolbarTier.narrow.keepsViewControlsInline, isFalse);
    });
  });

  group('主行十档宽度零溢出', () {
    // 扫描点从常量推出来，不写字面量：常量改了这条扫描会跟着挪，
    // 不会出现「阈值动过、扫描还在测旧的那两条线」的假绿。
    const labeled = ReaderTopBarStyleLimits.labeledToolbarMinWidth;
    const expanded = ReaderTopBarStyleLimits.expandedLayoutMinWidth;
    // 每条阈值的两侧各取一个值：越线那一下重建 widget 树，也最容易刚好放不下。
    for (final width in [
      320.0,
      360.0,
      389.0,
      expanded - 240,
      expanded - 1,
      expanded,
      labeled - 1,
      labeled,
      1280.0,
      1920.0,
    ]) {
      testWidgets('$width 不溢出', (tester) async {
        await _paintBar(tester, width);
        // RenderFlex 溢出会作为异常报上来，这条断言就是「没有斜纹」。
        expect(tester.takeException(), isNull);
        expect(_barButtons(), findsWidgets);
      });

      testWidgets('$width 展开缩放面板后仍不溢出', (tester) async {
        await _paintBar(tester, width);
        // 面板入口在主行上就点它，否则走「更多」菜单 —— 两条路是同一个入口。
        final inline = find.byIcon(Icons.dashboard_customize_outlined);
        if (inline.evaluate().isNotEmpty) {
          await tester.tap(inline);
        } else {
          await tester.tap(find.byIcon(Icons.more_vert_rounded));
          await tester.pumpAndSettle();
          await tester.tap(find.text('版式工具'));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('主行是一个 40 的高度带', () {
    // 用户拿截图报的「错位」：图标钮 40、胶囊 44（内边距 2 撑出来的）、芯片 32 ——
    // 三种高度并排，中心线再齐也还是乱。所以这条钉**高度**，不只是宽度。
    testWidgets('宽档：每一颗控件都占满同一档 40 高，中心线一致', (tester) async {
      await _paintBar(tester, 1280);
      final controls = find.byWidgetPredicate(
        (widget) =>
            widget is ReaderToolbarIconButton ||
            widget is ReaderToolbarToggleChip ||
            widget is ReaderToolbarPill,
      );
      final elements = controls.evaluate().toList();
      final count = elements.length;
      expect(count, greaterThan(8), reason: '宽档主行不该只剩几颗');
      double? center;
      for (var i = 0; i < count; i++) {
        final rect = tester.getRect(controls.at(i));
        expect(
          rect.height,
          40,
          reason:
              '第 $i 颗（${elements[i].widget.runtimeType}）不是 40 高，'
              '主行又会出现两种高度',
        );
        expect(rect.width, greaterThanOrEqualTo(40));
        if (center == null) {
          center = rect.center.dy;
        } else {
          expect(
            (rect.center.dy - center).abs(),
            lessThan(0.01),
            reason: '中心线不齐：第 $i 颗偏了',
          );
        }
      }
    });

    testWidgets('在线图源（没有呈现器）也画超分那颗', (tester) async {
      // 用户口径：超分的显示与开关留在第一行。在线那条路没有逐页状态，
      // 但总闸芯片必须在 —— 曾经整块不画，那就是「超分显示没了」。
      await _paintBar(tester, 1280);
      expect(find.byType(ReaderOnlineUpscaleChip), findsOneWidget);
      expect(find.text('超分'), findsOneWidget);
    });

    testWidgets('neo 那五颗占位不再占主行宽度', (tester) async {
      await _paintBar(tester, 1920);
      expect(find.byIcon(Icons.slideshow_rounded), findsNothing);
      expect(find.byIcon(Icons.zoom_in_map_rounded), findsNothing);
      // 但入口仍在：菜单里点得着，且仍然会给一句话。
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('幻灯片'), findsOneWidget);
      await tester.tap(find.text('幻灯片'));
      await tester.pump();
      // SnackBar 的入场动画要推进一帧才画得出来。
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('幻灯片 还没接进本仓的阅读器'),
        findsOneWidget,
        reason: '占位不能静默失效，否则人只会以为是自己点歪了',
      );
    });
  });

  group('让位顺序', () {
    testWidgets('宽档：视图三项在主行，版式芯片带文字', (tester) async {
      await _paintBar(tester, 1280);
      expect(find.byIcon(Icons.dashboard_customize_outlined), findsOneWidget);
      expect(find.byIcon(Icons.rotate_right_rounded), findsOneWidget);
      expect(find.text('单页'), findsOneWidget);
      // 分隔线：视图 / 版式 / 增强 / 窗口 之间三条。
      expect(find.byType(ReaderToolbarSeparator), findsNWidgets(3));
    });

    testWidgets('中档：视图组还在、文字收成图标，钉住与全屏先让位', (tester) async {
      await _paintBar(
        tester,
        ReaderTopBarStyleLimits.expandedLayoutMinWidth + 20,
      );
      expect(find.byIcon(Icons.dashboard_customize_outlined), findsOneWidget);
      expect(find.text('单页'), findsNothing);
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text(t.reader.pinTopBar), findsOneWidget);
    });

    testWidgets('窄档：整组进菜单，超分与滚屏留在第一行', (tester) async {
      await _paintBar(tester, 389);
      // 视图三项与窗口控件让位了。
      expect(find.byIcon(Icons.dashboard_customize_outlined), findsNothing);
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
      expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
      // 用户点名要留的第一行：超分的显示与开关（在线图源也画，见下面那条）。
      expect(find.byType(ReaderOnlineUpscaleChip), findsOneWidget);
      // 滚屏让位了：主行放不下它 + 超分芯片，两者按用户口径分先后。
      expect(find.byType(AutoScrollQuickButton), findsNothing);
      // 让出去的那一组仍然可达，而且就在末尾那颗「更多」里。
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('版式工具'), findsOneWidget);
      expect(find.text('旋转设置'), findsOneWidget);
      expect(find.text(t.reader.pinTopBar), findsOneWidget);
      expect(find.text('开启自动滚屏'), findsOneWidget);
    });
    testWidgets('触摸屏（没有全屏那颗）时窄档同样不溢出', (tester) async {
      await _paintBar(tester, 360, withFullscreen: false);
      expect(tester.takeException(), isNull);
    });
  });

  group('窗口拖动跨档', () {
    // 分档改变的是 widget 树的**形状**（芯片带不带字、哪一组在不在主行）。
    // 同一条树越线时 AnimatedContainer 要对旧新两份约束做插值：写 `width:
    // hasLabel ? null : 40` 的那一版在这里直接抛
    // 「Cannot interpolate between finite and unbounded constraints」，
    // 顶栏整条停止布局 —— 桌面端拖窗口就会撞上，编译与单档 pump 都抓不到。
    Future<void> resize(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 400);
      await tester.pumpAndSettle();
    }

    testWidgets('从窄拖到宽不抛异常，芯片重新带字', (tester) async {
      await _paintBar(tester, 700);
      expect(find.text('单页'), findsNothing);
      await resize(tester, ReaderTopBarStyleLimits.labeledToolbarMinWidth + 40);
      expect(tester.takeException(), isNull);
      expect(find.text('单页'), findsOneWidget);
    });

    testWidgets('从宽拖回窄不抛异常，控件整组让进菜单', (tester) async {
      await _paintBar(tester, 1280);
      await resize(tester, 600);
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.dashboard_customize_outlined), findsNothing);
    });
  });

  group('书名不被挤没（阈值的真实依据）', () {
    // 「不溢出」只保证没有斜纹，不保证书名还看得见：阈值 720 那一版里
    // 全体控件摊开，书名只剩 97px，症状从「溢出」变成了「看不见在读什么」。
    // 标题那一列是主行唯一的弹性项：它的宽度就是「让位让掉了多少」。
    final titleColumn = find.byWidgetPredicate(
      (widget) =>
          widget is Column &&
          widget.mainAxisAlignment == MainAxisAlignment.center,
    );

    Future<double> titleWidthAt(WidgetTester tester, double width) async {
      await _paintBar(tester, width);
      return tester.getSize(titleColumn.first).width;
    }

    testWidgets('每一档书名都还剩得下几个字', (tester) async {
      // 宽 / 中：这两档是桌面端的常见宽度，书名要能读。
      const labeled = ReaderTopBarStyleLimits.labeledToolbarMinWidth;
      const expanded = ReaderTopBarStyleLimits.expandedLayoutMinWidth;
      expect(await titleWidthAt(tester, labeled), greaterThan(240));
      expect(await titleWidthAt(tester, expanded), greaterThan(240));
      // 窄：手机那一档第一行要保住超分（用户口径排在书名之前），
      // 所以书名只要求还剩一个词的量 —— 再往下掉就是阈值给错了。
      expect(await titleWidthAt(tester, 389), greaterThan(100));
    });
  });
}
