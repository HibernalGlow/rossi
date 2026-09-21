// 底部缩略图条「并进进度条那一块面板」的判据。
//
// 用户口径：缩略图展开后要和底栏的进度条**融成一块**，不要在控制栏上面
// 再另起一栏。结构上唯一可变的就是「谁提供那层玻璃」，所以这里钉死：
//
//   独立浮着用（紧凑横屏）→ 自带恰好一层 LiquidGlassSurface
//   嵌进父级面板（常规布局）→ 一层都不带
//
// 少一层就少一条缝：两者都带玻璃时会「玻璃叠玻璃」，圆角还会互相切。
// 「父级把它们装进同一块玻璃」由 `chrome/bottom.dart` 负责，这里不重复断言。

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/bottom_thumbnail_strip.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';

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
  group('BottomThumbnailStrip 的玻璃归属', () {
    testWidgets('独立浮条自带一层玻璃', (tester) async {
      await tester.pumpWidget(_harness(_strip()));
      expect(find.byType(BottomThumbnailStrip), findsOneWidget);
      expect(find.byType(LiquidGlassSurface), findsOneWidget);
    });

    testWidgets('嵌进父级面板后一层玻璃都不带', (tester) async {
      await tester.pumpWidget(_harness(_strip(embedded: true)));
      expect(find.byType(BottomThumbnailStrip), findsOneWidget);
      expect(find.byType(LiquidGlassSurface), findsNothing);
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
