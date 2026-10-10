part of '../file_manager_card_test.dart';

// 多选模式的手感：模式内点一行是加选，模式外点一行是打开。
//
// 替身句柄以取值函数的形式从 `main` 递进来，而不是搬到库级：part 里的函数看不见
// 宿主函数的局部变量，而 `setUp` 每个用例换一个新的 api —— 直接传实例会传错那一个。

/// 默认快照里的那两行：第一行是压缩包，第二行是**文件夹**。
const _archiveRow = 'book.cbz';
const _folderRow = 'series with a long name';

/// 桥调用计数一律用 `.length` 而不是 `findsOneWidget`：后者只吃 Finder，喂给它一个
/// Iterable 会炸在 `describeMismatch` 里（`Null is not a subtype of FinderBase`），
/// 报出来的全是匹配器的类型问题，看不见真正的差值。
void _selectionTapTests(_FileManagerApi Function() getApi) {
  /// 摁工具栏那颗「多选」开关。它在横向滚动的工具栏里，窄卡片下要先滚进视口。
  Future<void> tapToggle(WidgetTester tester, String tooltip) async {
    final button = find.byTooltip(tooltip);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  /// 鼠标**长按**一行。
  ///
  /// 挑文件夹那行的菜单是**向下**铺开的，于是上面那行不会被菜单盖住。
  Future<void> longPressRow(WidgetTester tester, String label) async {
    await tester.longPress(find.text(label), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  /// 鼠标**右键**一行：只请菜单。
  Future<void> rightClickRow(WidgetTester tester, String label) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(label)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('不在多选模式里时，鼠标单击文件夹仍然直接进去', (tester) async {
    final api = getApi();
    await _pumpCard(tester, width: 700);

    await tester.tap(find.text(_folderRow), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(
      api.callsTo(#crateApiFileManagerEntryOpsFileManagerOpenEntry).length,
      1,
    );
    expect(api.callsTo(#crateApiFileOpsFileOpsSelectToggle).length, 0);
    expect(find.text('已选 1 项'), findsNothing);
  });

  testWidgets('摁下工具栏「多选」后，空着集合点第一行是选上而不是进去', (tester) async {
    final api = getApi();
    await _pumpCard(tester, width: 700);
    await tapToggle(tester, '多选');

    // 集合还是空的，但模式已经在了 —— 这正是那颗开关存在的理由。
    expect(find.text('已选 1 项'), findsNothing);
    api.calls.clear();

    await tester.tap(find.text(_folderRow), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(api.callsTo(#crateApiFileOpsFileOpsSelectToggle).length, 1);
    expect(
      api.callsTo(#crateApiFileManagerEntryOpsFileManagerOpenEntry).length,
      0,
    );
    expect(find.text('已选 1 项'), findsOneWidget);
  });

  testWidgets('长按只请菜单：不把选中立起来、不叫出操作条', (tester) async {
    final api = getApi();
    await _pumpCard(tester, width: 700);

    await longPressRow(tester, _archiveRow);

    // 阳性对照：菜单真的弹了，说明这一行确实被手势命中 —— 下面那几条零断言
    // 才有意义（否则它们只是在测「什么都没发生」）。
    expect(find.text('移到回收站'), findsOneWidget);
    expect(
      api.callsTo(#crateApiFileOpsFileOpsSelectSingle).length,
      0,
      reason: '长按不该替用户把选中集合搬到这一行',
    );
    expect(find.text('已选 1 项'), findsNothing);
  });

  testWidgets('右键没选中的项：回收站只打中那一项，而不是手里正拿着的那批', (tester) async {
    final api = getApi();
    await _pumpCard(tester, width: 700);
    // 先进模式、把**另一行**（文件夹）选上，于是「整批」与「这一个」分得开。
    await tapToggle(tester, '多选');
    await tester.tap(find.text(_folderRow), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    api.calls.clear();

    await rightClickRow(tester, _archiveRow);
    expect(find.text('移到回收站'), findsOneWidget);
    // 右键同样不搬选中集合：那一批仍然只有文件夹一项。
    expect(api.callsTo(#crateApiFileOpsFileOpsSelectSingle).length, 0);
    expect(find.text('已选 2 项'), findsNothing);

    await tester.tap(find.text('移到回收站'));
    await tester.pumpAndSettle();

    // 这条才是本次改动真正的安全闸门。回收站从前在桥那侧只读选中集合，
    // 「右键一个没选中的文件 → 移到回收站」会把**另一批**送进回收站，
    // 而确认框上写的数量是 1。现在目标必须显式跟着这一次调用走。
    final call = api.callsTo(#crateApiFileOpsFileOpsTrashPaths).single;
    expect(call.namedArguments[#paths], ['/books/$_archiveRow']);
  });

  testWidgets('摁「退出多选」清空选中，单击回到打开', (tester) async {
    final api = getApi();
    await _pumpCard(tester, width: 700);
    await tapToggle(tester, '多选');
    await tester.tap(find.text(_folderRow), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);

    api.calls.clear();
    await tapToggle(tester, '退出多选');
    expect(api.callsTo(#crateApiFileOpsFileOpsClearSelection).length, 1);
    expect(find.text('已选 1 项'), findsNothing);

    await tester.tap(find.text(_folderRow), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(
      api.callsTo(#crateApiFileManagerEntryOpsFileManagerOpenEntry).length,
      1,
    );
  });
}
