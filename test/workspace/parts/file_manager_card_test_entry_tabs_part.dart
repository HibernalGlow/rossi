part of '../file_manager_card_test.dart';

void _entryTabTests(
  _FileManagerApi Function() getApi,
  _TestGlobalSettingCubit Function() getSettings,
) {
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

  testWidgets('开启「默认在新页签打开文件夹」后点击普通文件夹直接新开页签', (tester) async {
    final api = getApi();
    final settings = getSettings();
    settings.updateFileManagerSetting(
      (s) => s.copyWith(openFolderInNewTab: true),
    );
    await _pumpCard(tester, settings: settings);
    await tester.tap(find.text('series with a long name'));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerNewTab)
          .single
          .namedArguments[#path],
      '/books/series with a long name',
    );
    expect(
      api.callsTo(#crateApiFileManagerEntryOpsFileManagerOpenEntry),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('开启「默认在新页签打开文件夹」时，可穿透文件夹单击仍穿透打开，双击在新页签打开', (tester) async {
    final api = getApi();
    final settings = getSettings();
    settings.updateFileManagerSetting(
      (s) => s.copyWith(openFolderInNewTab: true),
    );
    api.snapshot = _snapshot(folderPenetratable: true);
    await _pumpCard(tester, settings: settings);
    final folder = find.text('series with a long name');

    // 单击：穿透打开（走 fileManagerOpenEntry(forceEnter: false)）
    await tester.tap(folder);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    final openCalls = api
        .callsTo(#crateApiFileManagerEntryOpsFileManagerOpenEntry)
        .toList();
    expect(openCalls, hasLength(1));
    expect(openCalls.single.namedArguments[#forceEnter], isFalse);
    expect(api.callsTo(#crateApiFileManagerBrowseFileManagerNewTab), isEmpty);

    // 双击：强制进入该文件夹 -> 新开页签
    await tester.tap(folder);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tap(folder);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerNewTab)
          .single
          .namedArguments[#path],
      '/books/series with a long name',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('「更多」菜单可切换「默认在新页签打开文件夹」并立即生效', (tester) async {
    final api = getApi();
    final settings = getSettings();
    await _pumpCard(tester, settings: settings);
    expect(settings.state.fileManagerSetting.openFolderInNewTab, isFalse);

    final more = find.byTooltip('更多');
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(t.workspace.openFolderInNewTab),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(settings.state.fileManagerSetting.openFolderInNewTab, isTrue);

    await tester.tap(find.text('series with a long name'));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerNewTab)
          .single
          .namedArguments[#path],
      '/books/series with a long name',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
