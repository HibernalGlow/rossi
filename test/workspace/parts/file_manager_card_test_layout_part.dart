part of '../file_manager_card_test.dart';

void _layoutTests(_FileManagerApi Function() currentApi) {
  testWidgets('路径分段、列目录均采用 Rust 快照，编辑失败保留输入', (tester) async {
    final api = currentApi();
    api.snapshot = _snapshot(
      columnsEnabled: true,
      layoutMode: FileManagerLayoutMode.columns,
    );
    await _pumpCard(tester, width: 260);
    final rootCrumb = find.byKey(const ValueKey('file-manager-breadcrumb:/'));
    await tester.ensureVisible(rootCrumb);
    await tester.pumpAndSettle();
    await tester.tap(rootCrumb);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerNavigate)
          .last
          .namedArguments[#path],
      '/',
    );
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('file-manager-column:/books/series with a long name'),
      ),
    );
    await tester.tap(find.text('series with a long name'));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerNavigate)
          .last
          .namedArguments[#path],
      '/books/series with a long name',
    );
    await tester.tap(find.byTooltip('路径操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑路径'));
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('file-manager-path-input'));
    await tester.enterText(editor, '  "../书籍"  ');
    api.snapshotError = StateError('无法打开目录');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerNavigateText)
          .single
          .namedArguments[#text],
      '  "../书籍"  ',
    );
    expect(tester.widget<TextField>(editor).controller!.text, '  "../书籍"  ');
    expect(find.textContaining('无法打开目录'), findsOneWidget);
    api.snapshotError = null;
    await tester.tap(find.byTooltip('转到目录'));
    await tester.pumpAndSettle();
    expect(editor, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('布局与条目样式菜单独立，树形占用完整内容区', (tester) async {
    final api = currentApi();
    await _pumpCard(tester);
    expect(
      find.byKey(const ValueKey('file-manager-tree:/books')),
      findsNothing,
    );
    await _openTree(tester);
    expect(
      api
          .callsTo(#crateApiFileManagerSettingsFileManagerSetLayoutMode)
          .single
          .namedArguments[#mode],
      FileManagerLayoutMode.tree,
    );
    expect(
      api.callsTo(#crateApiFileManagerSettingsFileManagerSetViewMode),
      isEmpty,
    );
    expect(find.byTooltip('条目样式：封面列表'), findsOneWidget);
    final hierarchy = find.byKey(const ValueKey('file-manager-tree-list'));
    expect(tester.getSize(hierarchy).height, 440);
    final root = tester.getTopLeft(
      find.byKey(const ValueKey('file-manager-tree:/')),
    );
    final child = tester.getTopLeft(
      find.byKey(const ValueKey('file-manager-tree:/books/series')),
    );
    expect(child.dx - root.dx, 36);
    expect(
      find.byKey(const ValueKey('file-manager-tree-toggle:/books/loose')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('file-manager-tree-toggle:/books/series')),
    );
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerTreeFileManagerTreeToggle)
          .single
          .namedArguments[#path],
      '/books/series',
    );
    expect(api.callsTo(#crateApiFileManagerBrowseFileManagerNavigate), isEmpty);
    await tester.tap(find.text('/').last);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('/').last);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerEntryOpsFileManagerOpenEntry)
          .single
          .namedArguments[#path],
      '/',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('完整树布局仍会把深层当前目录搬进视口', (tester) async {
    final api = currentApi();
    api.tree = _deepTreeSnapshot(depth: 24);
    await _pumpCard(tester);
    await _openTree(tester);
    final viewport = tester.getRect(
      find.byKey(const ValueKey('file-manager-tree-list')),
    );
    final row = tester.getRect(
      find.byKey(const ValueKey('file-manager-tree:/n24')),
    );
    expect(row.top, greaterThanOrEqualTo(viewport.top));
    expect(row.bottom, lessThanOrEqualTo(viewport.bottom));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [260.0, 700.0]) {
    for (final mode in FileManagerViewMode.values) {
      testWidgets('搜索树保留同名命中：$mode，宽 $width', (tester) async {
        final api = currentApi();
        api.snapshot = _snapshot(
          query: 'match',
          searchActive: true,
          layoutMode: FileManagerLayoutMode.tree,
          viewMode: mode,
        );
        api.tree = FileManagerTreeSnapshot(
          hasPending: false,
          rows: [
            for (final path in [
              '/books',
              '/books/a',
              '/books/a/match.png',
              '/books/b',
              '/books/b/match.png',
            ])
              FileManagerTreeRow(
                path: path,
                name: path.split('/').last,
                depth: path == '/books'
                    ? 0
                    : path.endsWith('.png')
                    ? 2
                    : 1,
                expanded: !path.endsWith('.png'),
                loading: false,
                mayHaveChildren: !path.endsWith('.png'),
                isActive: false,
                entry: path.endsWith('.png')
                    ? _entry('match.png', path: path)
                    : null,
              ),
          ],
        );
        await _pumpCard(tester, width: width);
        // 网格档的祖先也用卡片，第二个分支可能在视口之外；逐分支滚动验证真实路径。
        for (final branch in ['a', 'b']) {
          final card = find.byKey(
            ValueKey('file-manager-tree:/books/$branch/match.png'),
          );
          await tester.scrollUntilVisible(
            card,
            120,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('file-manager-tree-list')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: card, matching: find.text('match.png')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
      testWidgets('分栏保留条目样式并可在窄窗口横向浏览：$mode，宽 $width', (tester) async {
        final api = currentApi();
        api.snapshot = _snapshot(
          layoutMode: FileManagerLayoutMode.columns,
          columnsEnabled: true,
          viewMode: mode,
        );
        await _pumpCard(tester, width: width);
        expect(
          find.byKey(
            const ValueKey(
              'file-manager-column:/books/series with a long name',
            ),
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('book.cbz'));
        await tester.pumpAndSettle();
        expect(find.text('book.cbz'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final width in [260.0, 700.0]) {
    for (final mode in FileManagerViewMode.values) {
      testWidgets('普通树把文件夹和文件融合为卡片：$mode，宽 $width', (tester) async {
        final api = currentApi();
        api.snapshot = _snapshot(
          layoutMode: FileManagerLayoutMode.tree,
          viewMode: mode,
        );
        api.tree = FileManagerTreeSnapshot(
          hasPending: false,
          rows: [
            FileManagerTreeRow(
              path: '/books',
              name: 'books',
              depth: 0,
              expanded: true,
              loading: false,
              mayHaveChildren: true,
              isActive: false,
              entry: _entry('books', directory: true, path: '/books'),
            ),
            FileManagerTreeRow(
              path: '/books/series',
              name: 'series',
              depth: 1,
              expanded: true,
              loading: false,
              mayHaveChildren: true,
              isActive: false,
              entry: _entry('series', directory: true, path: '/books/series'),
            ),
            for (final name in ['page1.cbz', 'page2.cbz'])
              FileManagerTreeRow(
                path: '/books/series/$name',
                name: name,
                depth: 2,
                expanded: false,
                loading: false,
                mayHaveChildren: false,
                isActive: false,
                entry: _entry(name, path: '/books/series/$name'),
              ),
          ],
        );
        await _pumpCard(tester, width: width);
        expect(find.byType(FileManagerSplitContent), findsNothing);
        expect(find.byType(ListTile), findsNothing);
        for (final name in ['series', 'page1.cbz', 'page2.cbz']) {
          final card = find.byKey(
            ValueKey(
              'file-manager-tree:/books/${name == 'series' ? name : 'series/$name'}',
            ),
          );
          await tester.ensureVisible(card);
          await tester.pumpAndSettle();
          final surface = tester.widget<LibraryEntrySurface>(
            find.descendant(
              of: card,
              matching: find.byType(LibraryEntrySurface),
            ),
          );
          expect(surface.mode, fileManagerLibraryMode(mode));
        }
        final first = find.byKey(
          const ValueKey('file-manager-tree:/books/series/page1.cbz'),
        );
        final second = find.byKey(
          const ValueKey('file-manager-tree:/books/series/page2.cbz'),
        );
        if ((mode == FileManagerViewMode.coverGrid ||
                mode == FileManagerViewMode.mosaicGrid) &&
            width == 700) {
          expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
          expect(tester.getSize(first).width, lessThan(180));
        }
        final toggle = find.byKey(
          const ValueKey('file-manager-tree-toggle:/books/series'),
        );
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(
          api
              .callsTo(#crateApiFileManagerTreeFileManagerTreeToggle)
              .single
              .namedArguments[#path],
          '/books/series',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
      testWidgets('父级分栏也使用六档样式和真实条目：$mode，宽 $width', (tester) async {
        final api = currentApi();
        api.snapshot = _snapshot(
          layoutMode: FileManagerLayoutMode.columns,
          viewMode: mode,
          columns: [
            FileManagerDirectoryColumn(
              path: '/parent',
              name: 'parent',
              entries: [
                FileManagerDirectoryChoice(
                  path: '/parent/next',
                  name: 'next',
                  selected: true,
                  entry: _entry('next', directory: true, path: '/parent/next'),
                ),
                FileManagerDirectoryChoice(
                  path: '/parent/parent.cbz',
                  name: 'parent.cbz',
                  selected: false,
                  entry: _entry('parent.cbz', path: '/parent/parent.cbz'),
                ),
              ],
            ),
          ],
        );
        await _pumpCard(tester, width: width);
        final pane = find.byKey(
          const ValueKey('file-manager-column-pane:/parent'),
        );
        await tester.ensureVisible(pane);
        await tester.pumpAndSettle();
        final list = tester.widget<LibraryEntryList>(
          find.descendant(of: pane, matching: find.byType(LibraryEntryList)),
        );
        expect(list.mode, fileManagerLibraryMode(mode));
        expect(list.entries.map((entry) => entry.title), [
          'next',
          'parent.cbz',
        ]);
        expect(
          find.descendant(of: pane, matching: find.byType(ListTile)),
          findsNothing,
        );
        final folder = find.byKey(
          const ValueKey('file-manager-column:/parent/next'),
        );
        await tester.ensureVisible(folder);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: folder, matching: find.text('next')),
        );
        await tester.pumpAndSettle();
        expect(
          api
              .callsTo(#crateApiFileManagerBrowseFileManagerNavigate)
              .single
              .namedArguments[#path],
          '/parent/next',
        );
        expect(
          api.callsTo(#crateApiFileManagerSettingsFileManagerSetViewMode),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  test('新页签设置兼容旧 JSON 并能保存三种策略', () {
    expect(
      FileManagerSettingState.fromJson({}).newTabPolicy,
      FileManagerTabStartupPolicy.triggering,
    );
    for (final policy in FileManagerTabStartupPolicy.values) {
      final setting = FileManagerSettingState(
        newTabPolicy: policy,
        newTabLayoutMode: 'tree',
        newTabViewMode: 'details',
        newTabPenetration: true,
        newTabShowHidden: true,
      );
      expect(FileManagerSettingState.fromJson(setting.toJson()), setting);
    }
    expect(
      FileManagerSettingState.fromJson({'newTabPolicy': 'future'}).newTabPolicy,
      FileManagerTabStartupPolicy.triggering,
    );
  });

  testWidgets('新页签预设交给 Rust，修改预设不覆盖现有页签', (tester) async {
    final api = currentApi();
    final settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(
        newTabPolicy: FileManagerTabStartupPolicy.defaults,
        newTabLayoutMode: 'columns',
        newTabViewMode: 'details',
        newTabPenetration: true,
        newTabShowHidden: true,
      ),
    );
    await _pumpCard(tester, settings: settings);
    final configure = api.callsTo(
      #crateApiFileManagerSettingsFileManagerConfigureNewTabs,
    );
    final options =
        api
                .callsTo(#crateApiFileManagerBrowseFileManagerCreate)
                .single
                .namedArguments[#newTabOptions]
            as FileManagerNewTabOptions;
    expect(options.policy, FileManagerNewTabPolicy.defaults);
    expect(options.layoutMode, FileManagerLayoutMode.columns);
    expect(options.viewMode, FileManagerViewMode.details);
    expect(options.showHiddenFiles, isTrue);
    expect(find.byTooltip('内容布局：内容视图'), findsOneWidget);
    settings.updateFileManagerSetting(
      (s) => s.copyWith(newTabPolicy: FileManagerTabStartupPolicy.recent),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建页签'));
    await tester.pumpAndSettle();
    expect(
      (configure.last.namedArguments[#options] as FileManagerNewTabOptions)
          .policy,
      FileManagerNewTabPolicy.recent,
    );
    expect(configure, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await settings.close();
  });

  testWidgets('从未激活页签新建会传递触发页签身份', (tester) async {
    final api = currentApi();
    await _pumpCard(tester);
    await _openTabMenu(tester, 'pictures');
    await tester.tap(find.text('从此页签新建'));
    await tester.pumpAndSettle();
    final call = api
        .callsTo(#crateApiFileManagerBrowseFileManagerNewTab)
        .single;
    expect(call.namedArguments[#sourceTabId], BigInt.from(2));
    expect(call.namedArguments[#path], '/books/pictures');
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerActivateTab),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('回车先取消旧搜索，连续回车只创建一个新页签', (tester) async {
    final api = currentApi();
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();
    api.cancelSearchReply = Completer<bool>();
    await tester.enterText(find.byType(TextField), 'match');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSearchInNewTab),
      isEmpty,
    );
    api.cancelSearchReply!.complete(true);
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSearchInNewTab),
      hasLength(1),
    );
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSetSearchQuery),
      isEmpty,
    );
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerRecordSearchHistory),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
