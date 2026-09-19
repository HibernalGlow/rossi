import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';

/// 共享菜单面板的**条目语义**：选中怎么画、分隔线算不算一项、长菜单放不下的时候
/// 怎么办。文件管理卡片（视图模式 / 排序 / 更多）整片复用这套，所以行为要钉在这里，
/// 而不是散在每个调用点上各画一遍。
void main() {
  Future<void> pumpMenu(
    WidgetTester tester, {
    required List<FluentPopupMenuItem<String>> items,
    ValueChanged<String>? onSelected,
    VisualDensity? visualDensity,
  }) async {
    // 默认测试视口只有 266x200 逻辑像素，长菜单的「装不下 → 滚动」那条用例
    // 需要一个正常尺寸的窗口。
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(),
          body: Align(
            alignment: Alignment.topLeft,
            child: FluentPopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              visualDensity: visualDensity,
              onSelected: onSelected,
              itemBuilder: (_) => items,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
  }

  List<FluentPopupMenuItem<String>> toggles() => [
    const FluentPopupMenuItem(
      value: 'on',
      selected: true,
      title: Text('显示隐藏文件'),
    ),
    const FluentPopupMenuItem(value: 'off', title: Text('文件夹优先')),
    const FluentPopupMenuItem.divider(),
    const FluentPopupMenuItem(
      value: 'icon',
      leading: Icon(Icons.grid_view),
      selected: true,
      title: Text('封面网格'),
    ),
  ];

  testWidgets('选中项打勾：没有图标时勾占住开头那一格', (tester) async {
    await pumpMenu(tester, items: toggles());

    final checkedRow = find.ancestor(
      of: find.text('显示隐藏文件'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: checkedRow, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    final plainRow = find.ancestor(
      of: find.text('文件夹优先'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: plainRow, matching: find.byIcon(Icons.check)),
      findsNothing,
    );
  });

  testWidgets('选中项带图标时，勾挪到末尾而不是把图标顶掉', (tester) async {
    await pumpMenu(tester, items: toggles());

    final row = find.ancestor(
      of: find.text('封面网格'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.grid_view)),
      findsOneWidget,
    );
    final checks = find.descendant(of: row, matching: find.byIcon(Icons.check));
    expect(checks, findsOneWidget);
    // 勾在文字的右边 —— 开头那一格让给图标。
    expect(
      tester.getRect(checks).left,
      greaterThan(tester.getRect(find.text('封面网格')).right),
    );
  });

  testWidgets('分隔线只分组：点它不算选中任何一项', (tester) async {
    var selected = <String>[];
    await pumpMenu(tester, items: toggles(), onSelected: selected.add);

    expect(find.byType(Divider), findsOneWidget);
    await tester.tap(find.byType(Divider), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
    expect(find.text('显示隐藏文件'), findsNothing);
  });

  testWidgets('禁用项不响应点击', (tester) async {
    var selected = <String>[];
    await pumpMenu(
      tester,
      items: [
        const FluentPopupMenuItem(
          value: 'nope',
          enabled: false,
          title: Text('复制页签'),
        ),
      ],
      onSelected: selected.add,
    );

    await tester.tap(find.text('复制页签'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
  });

  testWidgets('长菜单被夹在可视区里，剩下的滚动可达', (tester) async {
    await pumpMenu(
      tester,
      items: [
        for (var i = 0; i < 15; i++)
          FluentPopupMenuItem(value: '$i', title: Text('第 $i 项')),
        const FluentPopupMenuItem.divider(),
        const FluentPopupMenuItem(value: 'tail', title: Text('最后一项')),
      ],
    );

    final screen =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    final list = find.byType(ListView);
    final menuRect = tester.getRect(list);
    expect(screen.contains(menuRect.topLeft), isTrue);
    expect(menuRect.bottom, lessThanOrEqualTo(screen.bottom));

    // 装不下的那几项不是被裁掉，而是滚动可达。
    expect(find.text('最后一项'), findsNothing);
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('最后一项'), findsOneWidget);
  });

  testWidgets('触发键可以跟紧凑工具栏对齐', (tester) async {
    await pumpMenu(
      tester,
      items: toggles(),
      visualDensity: VisualDensity.compact,
    );
    final compact = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton && widget.visualDensity == VisualDensity.compact,
    );
    expect(compact, findsOneWidget);
  });
}
