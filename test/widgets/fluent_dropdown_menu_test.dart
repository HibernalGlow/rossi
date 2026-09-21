import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';

/// 工作台的每条泳道自己裁（`Clip.antiAlias`），而整页面板里还嵌了一条局部
/// `Navigator`（`EmbeddedUpstreamPage`）—— 于是「最近的 Overlay」是那条被裁在
/// 面板里的局部栈。菜单插进去就会被切成只剩图标、文字全没（书架 ⋮ 菜单实测踩过）。
///
/// 这里盯住：菜单必须落在**根** Overlay，并且摆位留在可视区内。
void main() {
  Future<void> pumpLaneWithMenuButton(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 120,
                child: ClipRRect(
                  child: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          actions: [
                            FluentPopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              itemBuilder: (_) => [
                                FluentPopupMenuItem(
                                  value: 'new_folder',
                                  leading: const Icon(Icons.create_new_folder),
                                  title: const Text('新建一个文件夹'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Expanded(child: ColoredBox(color: Colors.blue)),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
  }

  testWidgets('菜单不被泳道的裁剪吃掉：它落在根 Overlay 里', (tester) async {
    await pumpLaneWithMenuButton(tester);

    final item = tester.element(find.text('新建一个文件夹'));
    // 整棵树里 Overlay 只有两条：根的那条，和泳道里那条局部栈。
    // 从菜单往上数：数到 1 条说明它就在根上；数到 2 条说明它被塞进了局部栈，
    // 上面还压着一条裁剪过的面板边界。
    var overlaysAboveMenu = 0;
    item.visitAncestorElements((ancestor) {
      if (ancestor.widget is Overlay) overlaysAboveMenu++;
      return true;
    });

    expect(overlaysAboveMenu, 1, reason: '菜单被插进了泳道的局部 Overlay，会被裁在面板里');
  });

  testWidgets('菜单摆位留在可视区内', (tester) async {
    await pumpLaneWithMenuButton(tester);

    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
    final screen = Offset.zero & viewport;
    final itemRect = tester.getRect(find.text('新建一个文件夹'));

    expect(screen.contains(itemRect.topLeft), isTrue, reason: '$itemRect 越出左上');
    expect(
      screen.contains(itemRect.bottomRight),
      isTrue,
      reason: '$itemRect 越出右下（泳道外应该还有整屏可用）',
    );
  });
}
