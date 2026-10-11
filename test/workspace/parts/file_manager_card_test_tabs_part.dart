part of '../file_manager_card_test.dart';

void _tabMenuTests(_FileManagerApi Function() getApi) {
  testWidgets('页签操作与恢复把目标 ID 交给 Rust', (tester) async {
    await _pumpCard(tester);
    await _openTabMenu(tester, 'books');
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制页签'));
    await tester.pumpAndSettle();
    expect(
      getApi()
          .callsTo(#crateApiFileManagerBrowseFileManagerDuplicateTab)
          .single
          .namedArguments[#tabId],
      BigInt.one,
    );
    await tester.tap(find.byTooltip('恢复已关闭页签'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('closed'));
    await tester.pumpAndSettle();
    expect(
      getApi()
          .callsTo(#crateApiFileManagerBrowseFileManagerReopenClosedTab)
          .single
          .namedArguments[#tabId],
      BigInt.from(3),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final longPress in [false, true]) {
    testWidgets('文件页签${longPress ? "长按" : "右键"}打开菜单，不切换页签', (tester) async {
      final api = getApi();
      await _pumpCard(tester);
      expect(find.byTooltip('页签操作：books'), findsNothing);
      await _openTabMenu(tester, 'pictures', longPress: longPress);
      expect(find.text('复制页签'), findsOneWidget);
      expect(find.text('关闭左侧页签'), findsOneWidget);
      expect(
        api.callsTo(#crateApiFileManagerBrowseFileManagerActivateTab),
        isEmpty,
      );
      await tester.tap(find.text('复制页签'));
      await tester.pumpAndSettle();
      expect(
        api
            .callsTo(#crateApiFileManagerBrowseFileManagerDuplicateTab)
            .single
            .namedArguments[#tabId],
        BigInt.from(2),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('文件页签单击切换，关闭按钮直接关闭而不弹菜单', (tester) async {
    final api = getApi();
    await _pumpCard(tester);
    await tester.tap(find.widgetWithText(InputChip, 'pictures'));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerActivateTab)
          .single
          .namedArguments[#tabId],
      BigInt.from(2),
    );
    expect(find.text('复制页签'), findsNothing);
    final close = find.descendant(
      of: find.widgetWithText(InputChip, 'books'),
      matching: find.byTooltip('Delete'),
    );
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerCloseTab)
          .single
          .namedArguments[#tabId],
      BigInt.one,
    );
    expect(find.text('复制页签'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
