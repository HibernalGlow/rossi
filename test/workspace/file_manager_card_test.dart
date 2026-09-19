import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/src/rust/api/file_manager.dart';
import 'package:zephyr/src/rust/api/local.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_card.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_thumbnail.dart';

// Fake only the FRB boundary. Render the real card with the same Material
// library as main.dart and no Scaffold/Material supplied by its host.
class _FileManagerApi implements RustLibApi {
  FileManagerSnapshot snapshot = _snapshot();
  final calls = <Invocation>[];
  Object? snapshotError;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    switch (invocation.memberName) {
      case #crateApiFileManagerFileManagerCreate:
        return Future.value(BigInt.one);
      case #crateApiFileManagerFileManagerClose:
        return true;
      case #crateApiFileManagerFileManagerOpenEntry:
      case #crateApiFileManagerFileManagerOpenArchive:
        return Future.value(FileManagerActionResult(snapshot: snapshot));
      case #crateApiLocalThumbnailGetFileManagerEntryThumbnail:
        return Future.value(null);
      default:
        return snapshotError == null
            ? Future.value(snapshot)
            : Future<FileManagerSnapshot>.error(snapshotError!);
    }
  }

  Iterable<Invocation> callsTo(Symbol name) =>
      calls.where((call) => call.memberName == name);
}

FileManagerTab _tab(int id, String title, {bool canClose = true}) =>
    FileManagerTab(
      id: BigInt.from(id),
      title: title,
      path: '/books/$title',
      canGoBack: false,
      canGoForward: false,
      pinned: false,
      canClose: canClose,
      canCloseOthers: false,
      canCloseLeft: false,
      canCloseRight: canClose,
    );

FileManagerEntry _entry(
  String name, {
  bool directory = false,
  int children = 0,
}) => FileManagerEntry(
  path: '/books/$name',
  name: name,
  isDir: directory,
  isArchive: !directory,
  isImage: false,
  isVideo: false,
  isAudio: false,
  size: BigInt.from(1024),
  modifiedSecs: 1700000000,
  hasChildren: directory,
  childNames: List.generate(
    children,
    (i) => FileManagerChild(
      path: '/books/$name/$i.cbz',
      name: '$i.cbz',
      isDir: false,
      isArchive: true,
      isImage: false,
      isVideo: false,
      isAudio: false,
    ),
  ),
);

FileManagerSnapshot _snapshot({
  FileManagerViewMode viewMode = FileManagerViewMode.coverList,
  String query = '',
  bool canCreate = true,
  bool canClose = true,
  bool columnsEnabled = false,
  String? homePath,
  bool isHome = false,
  bool canSetHome = true,
  bool sortTemporary = false,
  bool canSortPreference = true,
}) => FileManagerSnapshot(
  sessionId: BigInt.one,
  maxTabs: 8,
  canCreateTab: canCreate,
  generation: BigInt.one,
  activeTabId: BigInt.one,
  activePath: '/books',
  canGoUp: true,
  breadcrumbs: const [
    FileManagerBreadcrumb(path: '/', name: '/', isRoot: true, isCurrent: false),
    FileManagerBreadcrumb(
      path: '/books',
      name: 'books',
      isRoot: false,
      isCurrent: true,
    ),
  ],
  directoryColumnsEnabled: columnsEnabled,
  directoryColumns: columnsEnabled
      ? const [
          FileManagerDirectoryColumn(
            path: '/books',
            name: 'books',
            entries: [
              FileManagerDirectoryChoice(
                path: '/books/series',
                name: 'series',
                selected: false,
              ),
            ],
          ),
        ]
      : const [],
  tabs: [
    _tab(1, 'books', canClose: canClose),
    _tab(2, 'pictures'),
  ],
  recentlyClosed: [_tab(3, 'closed')],
  entries: [
    _entry('book.cbz'),
    _entry('series with a long name', directory: true, children: 8),
  ],
  roots: const [LocalRootLocation(label: '主目录', path: '/home')],
  penetrationEnabled: true,
  showChildNames: true,
  internalItemsMode: FileManagerInternalItemsMode.all,
  maxDepth: 3,
  viewMode: viewMode,
  showHiddenFiles: false,
  searchQuery: query,
  entryFilter: FileManagerEntryFilter.all,
  sortField: FileManagerSortField.name,
  sortOrder: FileManagerSortOrder.ascending,
  directoriesFirst: true,
  homePath: homePath,
  isHome: isHome,
  canSetHome: canSetHome,
  sortTemporary: sortTemporary,
  canSortPreference: canSortPreference,
);

Future<void> _pumpCard(WidgetTester tester, {double width = 340}) async {
  tester.view.physicalSize = const Size(1000, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: FileManagerCard(isExpanded: true, onToggle: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _FileManagerApi api;
  setUp(() {
    api = _FileManagerApi();
    RustLib.initMock(api: api);
  });
  tearDown(RustLib.dispose);

  for (final width in [260.0, 340.0, 700.0]) {
    for (final mode in FileManagerViewMode.values) {
      testWidgets('Material 祖先与 $width 宽度 $mode 含多条子文件名不报错', (tester) async {
        api.snapshot = _snapshot(viewMode: mode, columnsEnabled: true);
        await _pumpCard(tester, width: width);
        expect(tester.takeException(), isNull);
        expect(find.byType(InputChip), findsWidgets);
        expect(find.byType(ActionChip), findsOneWidget);
        expect(find.text('book.cbz'), findsOneWidget);
        // The popup also needs matching MaterialLocalizations, not SDK ones.
        await tester.tap(find.byTooltip('页签操作：books'));
        await tester.pumpAndSettle();
        expect(find.text('固定页签'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('搜索框默认折叠，展开后提交到 Rust，切换页签后输入框采用 Rust 快照', (tester) async {
    await _pumpCard(tester);
    // 默认折叠：没有搜索输入框。
    expect(find.byType(TextField), findsNothing);

    final searchToggle = find.byTooltip('搜索当前目录');
    await tester.ensureVisible(searchToggle);
    await tester.tap(searchToggle);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'book');
    api.snapshot = _snapshot(query: 'book');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetSearchQuery)
          .single
          .namedArguments[#query],
      'book',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'book',
    );
    api.snapshot = _snapshot(query: 'from other tab');
    await tester.tap(find.byTooltip('新建页签'));
    await tester.pumpAndSettle();
    expect(api.callsTo(#crateApiFileManagerFileManagerNewTab), hasLength(1));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'from other tab',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('主页键按 Rust 能力禁用，长按把当前目录设为主页，再点跳主页', (tester) async {
    api.snapshot = _snapshot(); // homePath = null
    await _pumpCard(tester);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.home_outlined),
          )
          .onPressed,
      isNull,
    );

    final home = find.byIcon(Icons.home_outlined);
    await tester.ensureVisible(home);
    await tester.longPress(home);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetHomePath)
          .single
          .namedArguments[#path],
      '/books',
    );

    // 卡片内部快照只随 _apply 的返回更新：先换 mock 快照，再刷新拉取。
    api.snapshot = _snapshot(homePath: '/books');
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    final homeFilled = find.byIcon(Icons.home_outlined);
    await tester.ensureVisible(homeFilled);
    await tester.tap(homeFilled);
    await tester.pumpAndSettle();
    expect(api.callsTo(#crateApiFileManagerFileManagerGoHome), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('排序菜单提供日期与随机字段并可开临时排序', (tester) async {
    await _pumpCard(tester);
    final sortButton = find.byTooltip('排序：名称');
    await tester.ensureVisible(sortButton);
    await tester.tap(sortButton);
    await tester.pumpAndSettle();

    expect(find.text('修改日期'), findsOneWidget);
    expect(find.text('随机'), findsOneWidget);
    expect(find.text('临时排序（不记住本目录）'), findsOneWidget);

    await tester.tap(find.text('随机'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetSort)
          .single
          .namedArguments[#field],
      FileManagerSortField.random,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('临时排序按当前快照取反后提交', (tester) async {
    api.snapshot = _snapshot(sortTemporary: true);
    await _pumpCard(tester);
    final sortButton = find.byTooltip('排序：名称');
    await tester.ensureVisible(sortButton);
    await tester.tap(sortButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('临时排序（不记住本目录）'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetSortTemporary)
          .single
          .namedArguments[#enabled],
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('类型筛选移入更多菜单并提交到 Rust', (tester) async {
    await _pumpCard(tester);
    final more = find.byTooltip('更多');
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(find.text('类型：全部'), findsOneWidget);
    expect(find.text('类型：图片'), findsOneWidget);

    await tester.tap(find.text('类型：图片'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetEntryFilter)
          .single
          .namedArguments[#filter],
      FileManagerEntryFilter.images,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final height in [260.0, 760.0]) {
    testWidgets('独立面板在 $height 高度自带 Material 且不溢出', (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      api.snapshot = _snapshot(columnsEnabled: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 340,
              height: height,
              child: FileManagerCard(
                isExpanded: true,
                onToggle: () {},
                isStandalone: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('book.cbz'), findsOneWidget);
      final root = find.byType(ActionChip);
      await tester.ensureVisible(root);
      await tester.pumpAndSettle();
      await tester.tap(root);
      await tester.pumpAndSettle();
      expect(
        api
            .callsTo(#crateApiFileManagerFileManagerNavigate)
            .single
            .namedArguments[#path],
        '/home',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('归档双击只发一次打开归档，普通单击仍使用 Neo 打开动作', (tester) async {
    await _pumpCard(tester);
    await tester.tap(find.text('book.cbz'));
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tap(find.text('book.cbz'));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerFileManagerOpenArchive),
      hasLength(1),
    );
    expect(api.callsTo(#crateApiFileManagerFileManagerOpenEntry), isEmpty);
    await tester.tap(find.text('book.cbz'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(api.callsTo(#crateApiFileManagerFileManagerOpenEntry), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('页签操作与恢复把目标 ID 交给 Rust', (tester) async {
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('页签操作：books'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制页签'));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerDuplicateTab)
          .single
          .namedArguments[#tabId],
      BigInt.one,
    );
    await tester.tap(find.byTooltip('恢复已关闭页签'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('closed'));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerReopenClosedTab)
          .single
          .namedArguments[#tabId],
      BigInt.from(3),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('路径分段、列目录均采用 Rust 快照，编辑失败保留输入', (tester) async {
    api.snapshot = _snapshot(columnsEnabled: true);
    await _pumpCard(tester, width: 260);
    final rootCrumb = find.byKey(const ValueKey('file-manager-breadcrumb:/'));
    await tester.ensureVisible(rootCrumb);
    await tester.pumpAndSettle();
    await tester.tap(rootCrumb);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerNavigate)
          .last
          .namedArguments[#path],
      '/',
    );
    await tester.tap(
      find.byKey(const ValueKey('file-manager-column:/books/series')),
    );
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerNavigate)
          .last
          .namedArguments[#path],
      '/books/series',
    );
    await tester.tap(find.byTooltip('编辑目录路径'));
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('file-manager-path-input'));
    await tester.enterText(editor, '  "../书籍"  ');
    api.snapshotError = StateError('无法打开目录');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerNavigateText)
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

  testWidgets('按钮是否可用直接使用 Rust 能力，不在 Dart 重算页签规则', (tester) async {
    api.snapshot = _snapshot(canCreate: false, canClose: false);
    await _pumpCard(tester);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.add_rounded),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<InputChip>(find.byType(InputChip).first).onDeleted,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('初始化快照失败后重试复用同一 Rust 会话', (tester) async {
    api.snapshotError = StateError('cannot read directory');
    await _pumpCard(tester);
    expect(find.text('重试'), findsOneWidget);
    api.snapshotError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(api.callsTo(#crateApiFileManagerFileManagerCreate), hasLength(1));
    expect(find.text('book.cbz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(api.callsTo(#crateApiFileManagerFileManagerClose), hasLength(1));
  });

  testWidgets('文件与文件夹缩略图组件存在且平滑回退语义图标', (tester) async {
    await _pumpCard(tester);
    expect(find.byType(FileManagerThumbnailWidget), findsWidgets);
    expect(find.byIcon(Icons.auto_stories_rounded), findsOneWidget);
    expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('工具栏包含 NeoView 风格视图模式菜单并支持切换', (tester) async {
    await _pumpCard(tester);
    final menuButton = find.byTooltip('视图模式：封面列表');
    expect(menuButton, findsOneWidget);

    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    expect(find.text('紧凑列表'), findsOneWidget);
    expect(find.text('封面列表'), findsOneWidget);
    expect(find.text('横幅'), findsOneWidget);
    expect(find.text('详细信息'), findsOneWidget);
    expect(find.text('封面网格'), findsOneWidget);
    expect(find.text('自由缩略图'), findsOneWidget);

    await tester.tap(find.text('详细信息'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetViewMode)
          .single
          .namedArguments[#mode],
      FileManagerViewMode.details,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('详细信息视图渲染表头并支持点击表头字段排序', (tester) async {
    api.snapshot = _snapshot(viewMode: FileManagerViewMode.details);
    await _pumpCard(tester, width: 700);

    expect(find.text('名称'), findsWidgets);
    expect(find.text('类型'), findsWidgets);
    expect(find.text('大小'), findsWidgets);
    expect(find.text('修改时间'), findsWidgets);

    // 点击“大小”表头列切换排序
    await tester.tap(find.text('大小').first);
    await tester.pumpAndSettle();

    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetSort)
          .last
          .namedArguments[#field],
      FileManagerSortField.size,
    );

    // 点击“修改时间”表头列切换排序
    await tester.tap(find.text('修改时间').first);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetSort)
          .last
          .namedArguments[#field],
      FileManagerSortField.date,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
