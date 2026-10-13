// 底部缩略图条「并进进度条那一块面板」的判据。
//
// 用户口径：缩略图展开后要和底栏的进度条**融成一块**，不要在控制栏上面
// 再另起一栏。结构上唯一可变的就是「谁提供那层材质」，所以这里钉死：
//
//   独立浮着用（紧凑横屏）→ 自带恰好一层 Material
//   嵌进父级面板（常规布局）→ 一层都不带
//
// 少一层就少一条缝：两者都带材质时会「材质叠材质」，圆角还会互相切。
// 「父级把它们装进同一块材质」由 `chrome/bottom.dart` 负责，这里不重复断言。

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/widgets/library_image_geometry.dart';
import 'package:zephyr/service/reader/reader_thumbnail_service.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/bottom_thumbnail_strip.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 420, height: 120, child: child)),
    ),
  );
}

BottomThumbnailStrip _strip({bool embedded = false}) {
  return BottomThumbnailStrip(
    embedded: embedded,
    totalPages: 3,
    currentSlot: 1,
    comicId: 'comic',
    from: 'test',
    onSelectPage: (_) {},
  );
}

void main() {
  aspectRatioTests();
  group('BottomThumbnailStrip 的材质归属', () {
    testWidgets('独立浮条自带一层材质', (tester) async {
      await tester.pumpWidget(_harness(_strip()));
      expect(find.byType(BottomThumbnailStrip), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reader-thumbnail-surface')),
        findsOneWidget,
      );
    });

    testWidgets('嵌进父级面板后一层材质都不带', (tester) async {
      await tester.pumpWidget(_harness(_strip(embedded: true)));
      expect(find.byType(BottomThumbnailStrip), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reader-thumbnail-surface')),
        findsNothing,
      );
      // 内容还在：嵌入只是脱掉材质，不是把自己藏起来。
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('缩略图开关住在全局设置里', () {
    // 开关一旦放回阅读页的 State，就会「开一本新书就重置」——
    // 这两条是那个回归的最小判据。
    test('默认关（不给老用户改观感）', () {
      const defaults = ReadSettingState();
      expect(defaults.showThumbnailStrip, isFalse);
    });

    test('copyWith 可改，且落在 readSetting 上（随全局设置持久化/同步）', () {
      final toggled = const ReadSettingState().copyWith(
        showThumbnailStrip: true,
      );
      expect(toggled.showThumbnailStrip, isTrue);
      // 与其它阅读设置互不干扰。
      expect(
        toggled.hoverRevealEnabled,
        const ReadSettingState().hoverRevealEnabled,
      );
    });
  });
}

Finder _tile(int index) => find.byKey(ValueKey('reader-thumbnail-tile-$index'));

void _reportRatio(WidgetTester tester, int index, double ratio) {
  final scope = find.descendant(
    of: _tile(index),
    matching: find.byType(LibraryImageGeometryScope),
  );
  tester.widget<LibraryImageGeometryScope>(scope).onRatio(ratio);
}

void aspectRatioTests() {
  testWidgets('默认统一竖屏，切换后按比例变宽且完整显示，再切换恢复', (tester) async {
    var original = false;
    late StateSetter update;
    await tester.pumpWidget(
      _harness(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return BottomThumbnailStrip(
              totalPages: 3,
              currentSlot: 1,
              comicId: 'comic',
              from: 'test',
              onSelectPage: (_) {},
              originalAspectRatio: original,
            );
          },
        ),
      ),
    );
    _reportRatio(tester, 0, 2);
    _reportRatio(tester, 1, .5);
    await tester.pumpAndSettle();
    expect(tester.getSize(_tile(0)).width, 72);
    expect(tester.getSize(_tile(1)).width, 72);
    expect(
      find.byKey(const ValueKey('reader-thumbnail-aspect-toggle')),
      findsNothing,
    );
    expect(tester.getSize(find.byType(ListView)).width, 404);
    update(() => original = true);
    await tester.pumpAndSettle();
    expect(original, isTrue);
    final height = tester.getSize(_tile(0)).height;
    expect(tester.getSize(_tile(0)).width, closeTo(height * 2, .01));
    expect(tester.getSize(_tile(1)).width, closeTo(height * .5, .01));
    for (final thumbnail in tester.widgetList<ReaderThumbnailWidget>(
      find.byType(ReaderThumbnailWidget),
    )) {
      expect(thumbnail.fit, BoxFit.contain);
    }
    update(() => original = false);
    await tester.pumpAndSettle();
    expect(tester.getSize(_tile(0)).width, 72);
    expect(tester.takeException(), isNull);
  });

  for (final rtl in [false, true]) {
    testWidgets('变宽胶卷跳转、窗口变化与当前页居中：RTL=$rtl', (tester) async {
      var slot = 20;
      var width = 420.0;
      late StateSetter update;
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return SizedBox(
                    width: width,
                    height: 120,
                    child: BottomThumbnailStrip(
                      totalPages: 1000,
                      currentSlot: slot,
                      comicId: 'comic',
                      from: 'test',
                      originalAspectRatio: true,
                      rightToLeft: rtl,
                      onSelectPage: (index) => selected = index,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = find.byType(ListView);
      void expectCentered() => expect(
        tester.getCenter(_tile(slot)).dx,
        closeTo(tester.getCenter(viewport).dx, 1),
      );
      expectCentered();
      expect(
        find.byType(ReaderThumbnailWidget).evaluate().length,
        lessThan(20),
      );
      _reportRatio(tester, 20, 1.8);
      _reportRatio(tester, 19, .5);
      await tester.pumpAndSettle();
      expectCentered();
      update(() => slot = 600);
      await tester.pumpAndSettle();
      expectCentered();
      await tester.tap(_tile(slot));
      expect(selected, 600);
      update(() => width = 320);
      await tester.pumpAndSettle();
      expectCentered();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('极端长宽比保留完整图，缩略图尺寸限定在胶卷内', (tester) async {
    await tester.pumpWidget(
      _harness(
        BottomThumbnailStrip(
          totalPages: 3,
          currentSlot: 1,
          comicId: 'comic',
          from: 'test',
          onSelectPage: (_) {},
          originalAspectRatio: true,
        ),
      ),
    );
    _reportRatio(tester, 0, 20);
    _reportRatio(tester, 1, .01);
    await tester.pumpAndSettle();
    expect(tester.getSize(_tile(0)).width, lessThan(352));
    expect(tester.getSize(_tile(1)).width, 40);
    final thumbnail = find.descendant(
      of: _tile(1),
      matching: find.byType(ReaderThumbnailWidget),
    );
    expect(tester.widget<ReaderThumbnailWidget>(thumbnail).fit, BoxFit.contain);
    expect(tester.takeException(), isNull);
  });

  test('比例偏好默认竖屏，旧配置兼容，重启与同步序列化保持', () {
    expect(
      ReadSettingState.fromJson({}).thumbnailStripOriginalAspectRatio,
      isFalse,
    );
    final settings = const ReadSettingState().copyWith(
      thumbnailStripOriginalAspectRatio: true,
    );
    expect(
      ReadSettingState.fromJson(
        settings.toJson(),
      ).thumbnailStripOriginalAspectRatio,
      isTrue,
    );
    expect(settings.showThumbnailStrip, isFalse);
  });
}
