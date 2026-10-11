import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/widgets/expressive/shelf_list_editor.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_chip.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_rail.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_menu_button.dart';

Widget harness(Widget child, {bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(280, 600),
      disableAnimations: reduced,
    ),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('窄窗口内打开菜单，动作执行一次并自动关闭', (tester) async {
    tester.view.physicalSize = const Size(280, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = 0;
    await tester.pumpWidget(
      harness(
        Align(
          alignment: Alignment.bottomRight,
          child: ShelfMenuButton(
            glyph: AppGlyphs.menu,
            tooltip: '操作',
            size: 56,
            menuChildren: [
              ShelfMenuItem(
                label: '新建书签列表',
                glyph: AppGlyphs.listAdd,
                onPressed: () => selected++,
              ),
              const ShelfMenuItem(label: '不可用', onPressed: null),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('操作'));
    await tester.pumpAndSettle();
    expect(find.text('新建书签列表'), findsOneWidget);
    final item = tester.getRect(find.text('新建书签列表'));
    expect(item.left, greaterThanOrEqualTo(0));
    expect(item.right, lessThanOrEqualTo(280));
    await tester.tap(find.text('不可用'));
    await tester.pumpAndSettle();
    expect(selected, 0);
    await tester.tap(find.text('新建书签列表'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('新建书签列表'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空名称和路径分隔符留在表单内，提交时去掉首尾空格', (tester) async {
    String? saved;
    await tester.pumpWidget(
      harness(
        Center(
          child: ShelfListEditor(
            title: '新建书签列表',
            label: '列表名称',
            description: '按主题整理书签。',
            onSave: (name) => saved = name,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('请输入名称'), findsOneWidget);
    expect(saved, isNull);
    await tester.enterText(find.byType(TextFormField), 'a/b');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.enterText(find.byType(TextFormField), '  阅读计划  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(saved, '阅读计划');
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动画下状态立即切换，长列表名称可点击', (tester) async {
    var selected = false;
    await tester.pumpWidget(
      harness(
        StatefulBuilder(
          builder: (context, setState) => Row(
            children: [
              ShelfListChip(
                label: '一个很长很长的自定义书签列表名称',
                selected: selected,
                onTap: () => setState(() => selected = true),
              ),
              ExpressiveIconButton(
                glyph: AppGlyphs.more,
                tooltip: '操作',
                shape: ExpressiveButtonShape.flower,
                active: selected,
                onPressed: () {},
              ),
            ],
          ),
        ),
        reduced: true,
      ),
    );
    await tester.tap(find.byType(ChoiceChip));
    await tester.pump();
    expect(tester.widget<ChoiceChip>(find.byType(ChoiceChip)).selected, isTrue);
    final button = tester.widget<IconButton>(find.byType(IconButton));
    final shape = button.style!.shape!.resolve({}) as ExpressiveMorphBorder;
    expect(shape.progress, 1);
    expect(shape.from, ExpressiveButtonShape.cookie6Sided);
    expect(shape.to, ExpressiveButtonShape.circle);
    expect(tester.takeException(), isNull);
  });
  testWidgets('窄列表轨内管理按钮保持可达，长名称可横向滚动', (tester) async {
    var created = 0;
    var edited = 0;
    await tester.pumpWidget(
      harness(
        Center(
          child: SizedBox(
            width: 220,
            child: ShelfListRail(
              onCreate: () => created++,
              onEdit: () => edited++,
              children: [
                for (var i = 0; i < 6; i++)
                  ShelfListChip(
                    label: '自定义书签列表 $i',
                    selected: i == 0,
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('新建书签列表'));
    await tester.tap(find.byTooltip('重命名 / 删除当前列表'));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(edited, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('窄卡片标题保留辅助信息，普通模式点击标题折叠一次', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(
      harness(
        Center(
          child: SizedBox(
            width: 200,
            child: CollapsibleCard(
              cardId: 'preview',
              title: '一个较长的面板标题',
              icon: AppGlyphs.folderPlus,
              isExpanded: true,
              onToggle: () => toggled++,
              onMoveUp: () {},
              onHide: () {},
              disabledHint: '仅桌面',
              trailing: const Text('辅助状态与额外说明'),
              child: const Text('内容'),
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('折叠一个较长的面板标题'), findsNothing);
    expect(find.byType(ShelfMenuButton), findsNothing);
    await tester.tap(find.text('一个较长的面板标题'));
    await tester.pumpAndSettle();
    expect(toggled, 1);
    expect(find.text('仅桌面'), findsOneWidget);
    expect(find.text('辅助状态与额外说明'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
