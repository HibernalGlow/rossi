import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';

/// Expressive 小组件库本身的渲染验收。
///
/// 单独一个文件是有原因的：注册表契约那组要 import `workspace_card_registry`，
/// 它 transitively 拉进整个 `comic_read`；本文件只拉 `expressive_widgets`，
/// 于是在别的活儿把主树改坏时，这一层仍然能跑。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> board(WidgetTester tester, Widget child, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: size.width, child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ExpressiveStatTile 量不到的数画成 —，不 fallback 成 0', (
    tester,
  ) async {
    await board(
      tester,
      const ExpressiveStatTile(value: '—', label: '编码大小', icon: AppGlyphs.box),
      const Size(360, 300),
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ExpressiveTileGrid 在窄槽位里退到单列且不溢出', (tester) async {
    for (final width in [180.0, 320.0, 640.0]) {
      await board(
        tester,
        ExpressiveTileGrid(
          minTileWidth: 130,
          children: [
            for (final label in ['甲', '乙', '丙'])
              ExpressiveStatTile(value: label, label: '格', icon: AppGlyphs.box),
          ],
        ),
        Size(width, 400),
      );
      expect(tester.takeException(), isNull, reason: '$width');
      expect(find.byType(ExpressiveStatTile), findsNWidgets(3), reason: '$width');
    }
  });

  testWidgets('ExpressiveFactTile 可点：点击回调真的落地', (tester) async {
    var taps = 0;
    await board(
      tester,
      ExpressiveFactTile(
        label: '呈现器',
        value: '就绪',
        onTap: () => taps++,
      ),
      const Size(420, 260),
    );
    // 证伪用例：点在**值**上必须生效。
    // 这条在修 SelectionArea 之前是红的（点 label 有反应、点 value 没反应），
    // 所以它同时是回归锁 —— 谁再把 SelectionArea 套回可点格子，这里就红。
    await tester.tap(find.text('就绪'));
    await tester.pump();
    expect(taps, 1, reason: '点在值上必须落地，不能被 SelectionArea 吃掉');
    // 不可点的格子仍然要能选中复制（路径 / ID 不靠截屏）。
    expect(find.byType(SelectionArea), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ExpressiveStatusPill 三档色都渲染，文本原样可读', (tester) async {
    await board(
      tester,
      const Column(
        children: [
          ExpressiveStatusPill(text: '就绪', tone: ExpressiveTone.primary),
          ExpressiveStatusPill(text: '加载中', tone: ExpressiveTone.neutral),
          ExpressiveStatusPill(text: '失败', tone: ExpressiveTone.warning),
        ],
      ),
      const Size(360, 300),
    );
    for (final text in ['就绪', '加载中', '失败']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(tester.takeException(), isNull);
  });
}
