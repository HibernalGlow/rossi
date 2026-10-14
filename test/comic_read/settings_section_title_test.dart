import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';

/// `SettingsSection.showTitle` 的回归锁。
///
/// 这个参数是给控制面板那几张卡加 `showTitle: false` 用的 —— 它们的卡片标题行
/// 已经写了节名，节内再画一遍就是同一句话写两遍（出图看到的）。
/// 但 `SettingsSection` 是阅读设置面板也在用的共享件，所以两侧都要钉住：
/// 默认必须**一字不动**，显式关掉才不画。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('默认画标题行（阅读设置面板那一侧不许变）', (tester) async {
    await pump(
      tester,
      const SettingsSection(
        title: '画面调节',
        icon: AppGlyphs.wand,
        children: [SizedBox(height: 20)],
      ),
    );
    expect(find.text('画面调节'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showTitle: false 时不画标题，但正文照旧', (tester) async {
    await pump(
      tester,
      const SettingsSection(
        title: '画面调节',
        icon: AppGlyphs.wand,
        showTitle: false,
        children: [SizedBox(height: 20, key: ValueKey('body'))],
      ),
    );
    expect(find.text('画面调节'), findsNothing);
    expect(find.byKey(const ValueKey('body')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关掉标题行之后，标题再长也不会撑出一行空白', (tester) async {
    const longTitle = 'AI 超分辨率（这一段标题故意写得很长很长很长很长很长很长）';
    await pump(
      tester,
      const SettingsSection(
        title: longTitle,
        showTitle: false,
        children: [SizedBox(height: 100)],
      ),
    );
    // 正文 100 就是全部高度：标题那一行的 14+8 内边距不该留下。
    expect(tester.getSize(find.byType(SizedBox).first).height, 100);
    expect(find.text(longTitle), findsNothing);
  });
}
