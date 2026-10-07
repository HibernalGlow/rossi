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

  /// 长按**文件夹**那一行：菜单宿主先把选中态收敛到它（`onBeforeOpen`），再弹菜单。
  ///
  /// 挑文件夹这行下手有两个理由：它排在最后，菜单是**向下**铺开的，于是上面那行
  /// 不会被菜单盖住（否则第二下点到的会是菜单项）；而且它就是用户说的那种
  /// 「点一下就进去了」的东西。
  Future<void> longPressFolderRow(WidgetTester tester) async {
    await tester.longPress(
      find.text(_folderRow),
      kind: PointerDeviceKind.mouse,
    );
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

  testWidgets('长按把选中立起来之后，点另一行是加进选中而不是进文件夹', (tester) async {
    final api = getApi();
    await _pumpCard(tester, width: 700);
    // 按用户原话的形状来：长按**文件**那一行，然后点**文件夹**那一行。
    await tester.longPress(
      find.text(_archiveRow),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    final names = api.calls.map((call) => call.memberName.toString()).join(', ');
    // 这条就是用户报的那一步：长按之后操作条出现，界面上已经是多选。
    expect(
      api.callsTo(#crateApiFileOpsFileOpsSelectSingle).length,
      1,
      reason: '桥调用清单：$names',
    );
    expect(find.text('已选 1 项'), findsOneWidget);
    // 菜单确实弹出来了 —— 不然这条链和真实操作不是同一回事。
    expect(find.text('移到回收站'), findsOneWidget);

    // 先把菜单收掉再点第二行：菜单是十来项高的一个面，压在行上，
    // 第二下会点到菜单项而不是那一行。
    //
    // 不能用 Esc 收：这条路上焦点根本没进菜单（`SingleActivator(escape)` 挂在菜单
    // 自己的 `Shortcuts` 里）。点**卡片外面**那块空白才是用户真正会做的动作，
    // 而 `TapRegion.onTapOutside` 只观察不吃事件。
    // 视口 1000x1100、卡片宽 700 且左上对齐，(900, 1050) 落在卡片之外。
    await tester.tapAt(const Offset(900, 1050), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('移到回收站'), findsNothing);
    // 收菜单不该顺手把选中清掉 —— 「刚才那一批还拿着」是这个状态的本职。
    expect(find.text('已选 1 项'), findsOneWidget);
    api.calls.clear();

    await tester.tap(find.text(_folderRow), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(api.callsTo(#crateApiFileOpsFileOpsSelectToggle).length, 1);
    expect(
      api.callsTo(#crateApiFileManagerEntryOpsFileManagerOpenEntry).length,
      0,
    );
    expect(find.text('已选 2 项'), findsOneWidget);
  });

  testWidgets('摁「退出多选」清空选中，单击回到打开', (tester) async {
    final api = getApi();
    await _pumpCard(tester, width: 700);
    await longPressFolderRow(tester);
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
