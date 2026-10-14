// 顶栏末尾那一段图标带的**间距**判据。
//
// 用户报的是「钉住那颗和别几颗间距不一样，它左边那一条空得比其他宽」，口径是
// 「图标保持等宽」。原因是两处：
//
//   1. 增强（下载/超分/译文）与窗口（全屏/钉住/更多/设置）原本是**两个组**，
//      组间 12、组内 4 —— 钉住作为窗口组的第一颗，左边永远比邻居宽；
//   2. 增强那三颗芯片各自按当前图源/呈现器决定画不画，隐藏的芯片仍然把组内
//      那 4 占着，于是 12 还要再加 4、再加 4。
//
// 现在这两处并成一条 4 的图标带，隐藏的控件用 [ReaderToolbarOptionalSlot]
// 连间距一起归零。这里的判据全部来自**画出来的矩形**，不是常数：
// 每条都配了阳性对照（同一把尺必须能量出组间的 12），否则「全都等于 4」
// 可以靠尺本身看不见任何东西而假绿。
//
// 只 pump 顶栏本体：`from` 留空 ⇒ 下载那颗不出现；
// `LocalReadSession.instance.presenter` 为 null ⇒ 本地译文芯片走 shrink 分支
// （正好就是要量的那一类隐藏件）。

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_presentation_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/app_bar.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_online_translated_page_chip.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_feature_button.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_translated_page_chip.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';

Future<void> _paintBar(
  WidgetTester tester,
  double width, {
  bool withFullscreen = true,
  double height = 400,
}) async {
  // 改**视口**而不是塞 SizedBox：默认画布 800×600 会把 1280 夹回 800，
  // 宽档与中档就成了同一档。
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final settings = GlobalSettingCubit();
  final presentation = ReaderPresentationCubit(settings: settings);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ComicReadPreferenceCubit>(
          create: (_) => ComicReadPreferenceCubit(),
        ),
        BlocProvider.value(value: settings),
        BlocProvider(create: (_) => ReaderCubit()),
        BlocProvider.value(value: presentation),
      ],
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff98616f)),
        ),
        home: Scaffold(
          body: Stack(
            children: [
              ComicReadAppBar(
                title: '第 3 话',
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

Finder _glyphButton(Glyph glyph) => find.byWidgetPredicate(
  (widget) => widget is ReaderToolbarIconButton && widget.icon == glyph,
);

/// 图标带里**画出来的**那几颗控件的矩形，按从左到右排好。
List<Rect> _runRects(WidgetTester tester, Finder group) {
  final icons = find.descendant(
    of: group,
    matching: find.byType(ReaderToolbarIconButton),
  );
  final chips = find.descendant(
    of: group,
    matching: find.byType(ReaderToolbarFeatureButton),
  );
  final rects = <Rect>[
    for (final finder in [icons, chips])
      for (var i = 0; i < finder.evaluate().length; i++)
        tester.getRect(finder.at(i)),
  ].where((r) => r.width > 0).toList();
  rects.sort((a, b) => a.left.compareTo(b.left));
  return rects;
}

/// 钉住所在的那一条图标带（一个 [ReaderToolbarGroup]）。
Finder _runGroup(Finder pin) {
  final group = find.ancestor(
    of: pin,
    matching: find.byType(ReaderToolbarGroup),
  );
  expect(group, findsOneWidget, reason: '钉住不该同时住在两条带里');
  return group;
}

/// 让位行里画出来的图标钮，按从左到右排好。
List<Rect> _rowRects(WidgetTester tester, Finder row) {
  final icons = find.descendant(
    of: row,
    matching: find.byType(ReaderToolbarIconButton),
  );
  final rects = <Rect>[
    for (var i = 0; i < icons.evaluate().length; i++)
      tester.getRect(icons.at(i)),
  ].where((r) => r.width > 0).toList()
    ..sort((a, b) => a.left.compareTo(b.left));
  return rects;
}

/// 相邻两颗之间的横向空档。
List<double> _gapsBetween(List<Rect> rects) => [
  for (var i = 1; i < rects.length; i++) rects[i].left - rects[i - 1].right,
];

void main() {
  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  group('宽档主行末尾的图标带', () {
    final pin = _glyphButton(AppGlyphs.pin);

    testWidgets('每两颗都只差组内的 4', (tester) async {
      await _paintBar(tester, 1280);
      final group = _runGroup(pin);
      final rects = _runRects(tester, group);
      // 阳性对照之一：这一带必须真的画出了控件，否则空列表也能「全都等于 4」。
      // 这五颗是夹具这个配置下唯一可能出现的：超分（`from` 留空 ⇒ 没有呈现器，
      // 走在线简版那颗）+ 全屏 + 钉住 + 更多 + 设置；本地译文与在线译文两颗
      // 在这个配置下**不画**，它们占的位正是下面几条要钉的东西。
      expect(
        rects.length,
        5,
        reason: '图标带画出的件数变了，先弄清是不是隐藏件又开始占位了',
      );
      // 阳性对照之二：这一档**确实有隐藏件**。本地译文与在线译文两颗都不画 ——
      // 要是它们其实画出来了，「全都差 4」对改造前的写法也成立，这条就是假绿。
      for (final chipType in [
        ReaderTranslatedPageChip,
        ReaderOnlineTranslatedPageChip,
      ]) {
        final slot = find.ancestor(
          of: find.byType(chipType),
          matching: find.byType(ReaderToolbarOptionalSlot),
        );
        expect(slot, findsOneWidget, reason: '$chipType 没被槽包住');
        expect(
          tester.getSize(slot),
          Size.zero,
          reason: '$chipType 这个配置下本该不画，尺就量不到「隐藏件不占位」',
        );
      }
      for (final gap in _gapsBetween(rects)) {
        expect(gap, closeTo(ReaderToolbarMetrics.gapWithinGroup, 0.01));
      }
    });

    testWidgets('钉住左边那条只差 4，不再是组间的 12', (tester) async {
      await _paintBar(tester, 1280);
      final group = _runGroup(pin);
      final rects = _runRects(tester, group);
      final pinRect = tester.getRect(pin);
      final left = rects.lastWhere((r) => r.right <= pinRect.left + 0.01);
      expect(
        pinRect.left - left.right,
        closeTo(ReaderToolbarMetrics.gapWithinGroup, 0.01),
        reason: '钉住与左边那颗之间又出现了组间距/隐藏件的占位',
      );
    });

    testWidgets('没有全屏那颗时，钉住紧跟在芯片后面（仍差 4）', (tester) async {
      await _paintBar(tester, 1280, withFullscreen: false);
      final group = _runGroup(pin);
      final rects = _runRects(tester, group);
      expect(pin, findsOneWidget);
      for (final gap in _gapsBetween(rects)) {
        expect(gap, closeTo(ReaderToolbarMetrics.gapWithinGroup, 0.01));
      }
    });

    testWidgets('同一把尺量得出组间的 12（阳性对照）', (tester) async {
      await _paintBar(tester, 1280);
      final group = _runGroup(pin);
      // 版式组与图标带之间是**组间**的 12：尺只会读 4 的话，这条应该红。
      final layoutGroup = find
          .ancestor(
            of: find.text('单页'),
            matching: find.byType(ReaderToolbarGroup),
          )
          .first;
      final gap = tester.getRect(group).left - tester.getRect(layoutGroup).right;
      expect(
        gap,
        closeTo(ReaderToolbarMetrics.gapBetweenGroups, 0.01),
        reason: '量错了对象，或组间那一条被一起吃掉了',
      );
    });
  });

  group('让位行（中/窄档第二行）', () {
    // 用户第二轮报的就是这一行：视图三项与「全屏 + 钉住」之间那条 20
    // （批次分隔的 12 再被 Wrap 自己各加 4），而相邻颗是 4。
    testWidgets('整行是一条等宽带：视图三项 → 全屏 → 钉住 全差 4', (tester) async {
      await _paintBar(tester, 389, height: 800);
      final row = find.byType(ReaderToolbarPanelRow);
      expect(row, findsOneWidget);
      final rects = _rowRects(tester, row);
      // 阳性对照：这一档真的搬来了 视图三项 + 全屏 + 钉住 = 5 颗。
      expect(rects.length, 5, reason: '让位行搬的东西变了，先看是不是漏了入口');
      for (final gap in _gapsBetween(rects)) {
        expect(
          gap,
          closeTo(ReaderToolbarMetrics.gapWithinGroup, 0.01),
          reason: '这一行又混进了批次间距',
        );
      }
    });
  });
}
