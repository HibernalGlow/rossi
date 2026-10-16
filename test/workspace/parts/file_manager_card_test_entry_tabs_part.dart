part of '../file_manager_card_test.dart';

void _entryTabTests(_FileManagerApi Function() getApi) {
  for (final layout in FileManagerLayoutMode.values) {
    for (final directory in [false, true]) {
      testWidgets('搜索 $layout 右键${directory ? "目录" : "文件"}在新页签打开', (
        tester,
      ) async {
        final api = getApi();
        final entry = _entry('target.cbz', directory: directory);
        api.snapshot = _snapshot(
          query: 'target',
          searchActive: true,
          layoutMode: layout,
          entries: [entry],
        );
        api.tree = FileManagerTreeSnapshot(
          hasPending: false,
          rows: [
            FileManagerTreeRow(
              path: entry.path,
              name: entry.name,
              entry: entry,
              depth: 0,
              expanded: false,
              loading: false,
              mayHaveChildren: directory,
              isActive: false,
            ),
          ],
        );
        await _pumpCard(tester, width: 700);
        await tester.tap(
          find.text(entry.name).first,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        // 新页签回到普通目录，文件定位必须使用新目录的下标。
        api.snapshot = _snapshot(activeTabId: 2, entries: [entry]);
        await tester.tap(find.text(t.workspace.openInNewTab));
        await tester.pumpAndSettle();
        expect(
          api
              .callsTo(#crateApiFileManagerBrowseFileManagerNewTab)
              .single
              .namedArguments[#path],
          directory ? entry.path : '/books',
        );
        expect(
          api.callsTo(#crateApiFileManagerEntryOpsFileManagerOpenEntry),
          isEmpty,
        );
        expect(
          api.callsTo(#crateApiFileOpsFileOpsSelectSingle),
          directory ? isEmpty : hasLength(1),
        );
        if (!directory) {
          expect(api.selectedPaths, [entry.path]);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('书签和历史共用通道识别真实文件并定位到新目录', (tester) async {
    final api = getApi();
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('rossi-tab-target-'),
    );
    final path = '${root!.path}/README';
    await tester.runAsync(() => File(path).writeAsString('fixture'));
    try {
      await _pumpCard(tester);
      api.snapshot = _snapshot(
        activeTabId: 2,
        entries: [_entry('README', path: path)],
      );
      final outcome = await tester.runAsync(
        () => FileManagerTabBridge.instance.openInNewTab(path),
      );
      await tester.pumpAndSettle();
      expect(outcome, FileManagerTabOpenOutcome.opened);
      expect(
        api
            .callsTo(#crateApiFileManagerBrowseFileManagerNewTab)
            .single
            .namedArguments[#path],
        root.path,
      );
      expect(api.selectedPaths, [path]);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      await tester.runAsync(() => root.delete(recursive: true));
    }
  });
}
