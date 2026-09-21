import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/src/rust/api/file_manager.dart';
import 'package:zephyr/src/rust/api/file_ops.dart';
import 'package:zephyr/src/rust/api/local.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_card.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_navigation_pad.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_thumbnail.dart';

/// 卡片现在要读写「文件管理器」全局设置（主页开关与路径）。
///
/// 真实的 [GlobalSettingCubit.updateState] 会落 ObjectBox，而本机的
/// `flutter test` 加载不了 `libobjectbox.dylib`（见 `test_helper.dart` 的说明）。
/// 所以这里只绕开**持久化**这一层：把写入直接 `emit` 到内存 state，
/// 于是「卡片确实把主页写进了全局设置」仍然可断言。
class _TestGlobalSettingCubit extends GlobalSettingCubit {
  _TestGlobalSettingCubit({FileManagerSettingState? fileManagerSetting})
    : super() {
    if (fileManagerSetting != null) {
      emit(state.copyWith(fileManagerSetting: fileManagerSetting));
    }
  }

  @override
  void updateFileManagerSetting(
    FileManagerSettingState Function(FileManagerSettingState current) updates,
  ) {
    emit(state.copyWith(fileManagerSetting: updates(state.fileManagerSetting)));
  }
}

// Fake only the FRB boundary. Render the real card with the same Material
// library as main.dart and no Scaffold/Material supplied by its host.
class _FileManagerApi implements RustLibApi {
  FileManagerSnapshot snapshot = _snapshot();

  /// 文件操作那一份会话快照（选中集合 / 剪贴板 / 撤销栈，见 ADR-0017）。
  ///
  /// 它与 [snapshot] 是**两张不同的表**：管理器快照管列表与页签，这一份管
  /// 「选了谁、剪贴板里是什么、能不能撤销」。所以下面必须给 file_ops 那一族
  /// 桥函数单开分支 —— 它们落进 default 的话会拿一个 `FileManagerSnapshot`
  /// 去顶 `FileOpsSnapshot` / `FileOpsReport` / `bool`，炸出来的是一句
  /// 很难看懂的 `type 'Future<FileManagerSnapshot>' is not a subtype of ...`。
  FileOpsSnapshot ops = _opsSnapshot();

  /// 文件树的投影。`hasPending` 固定为 false：真实的懒扫描靠 UI 隔一会儿再问一次，
  /// 测试里若让它一直「有待收」会让 `pumpAndSettle` 转不完。
  FileManagerTreeSnapshot tree = _treeSnapshot();
  final calls = <Invocation>[];
  Object? snapshotError;

  /// 搜索历史的替身。记一次就把那个词挪到最前 —— 与 SQLite 那侧「按最近使用」
  /// 的口径一致，这样卡片只负责显示，不必自己模拟去重。
  final List<String> history = [];

  /// 非空时，`setSearchQuery` 的回复挂在这个 Completer 上。用来造一个「请求还在
  /// 飞行中」的时刻 —— 增量搜索的关键判据（输入框不能因此禁打）只能在那一刻测。
  Completer<FileManagerSnapshot>? searchReply;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    switch (invocation.memberName) {
      case #crateApiFileManagerFileManagerCreate:
        return Future.value(BigInt.one);
      case #crateApiFileManagerFileManagerSetSearchQuery:
        final gate = searchReply;
        return gate == null ? Future.value(snapshot) : gate.future;
      case #crateApiFileManagerFileManagerClose:
        return true;
      case #crateApiFileManagerFileManagerTreeSnapshot:
      case #crateApiFileManagerFileManagerTreeToggle:
        return Future.value(tree);
      case #crateApiFileManagerFileManagerSearchHistory:
        return Future.value(List<String>.from(history));
      case #crateApiFileManagerFileManagerRecordSearchHistory:
        final query = invocation.namedArguments[#query] as String;
        history.remove(query);
        history.insert(0, query);
        return Future.value(List<String>.from(history));
      case #crateApiFileManagerFileManagerClearSearchHistory:
        history.clear();
        return Future.value(0);
      case #crateApiFileManagerFileManagerOpenEntry:
      case #crateApiFileManagerFileManagerOpenArchive:
        return Future.value(FileManagerActionResult(snapshot: snapshot));
      case #crateApiLocalThumbnailGetFileManagerEntryThumbnail:
        return Future.value(null);

      // ── 文件操作（ADR-0017）──────────────────────────────────────────────
      // 只改选中集合 / 剪贴板的那几个，回的都是同一份 `ops`。
      case #crateApiFileOpsFileOpsSnapshot:
      case #crateApiFileOpsFileOpsSelectSingle:
      case #crateApiFileOpsFileOpsSelectToggle:
      case #crateApiFileOpsFileOpsSelectChain:
      case #crateApiFileOpsFileOpsSelectAll:
      case #crateApiFileOpsFileOpsInvertSelection:
      case #crateApiFileOpsFileOpsClearSelection:
      case #crateApiFileOpsFileOpsCopyToClipboard:
      case #crateApiFileOpsFileOpsClearClipboard:
        return Future.value(ops);
      // 真的落盘的那几个，回一份回执（回执里带着刷新后的快照）。
      case #crateApiFileOpsFileOpsPaste:
      case #crateApiFileOpsFileOpsTrashSelection:
      case #crateApiFileOpsFileOpsDeleteSelection:
      case #crateApiFileOpsFileOpsRenameEntry:
      case #crateApiFileOpsFileOpsCreateDirectory:
      case #crateApiFileOpsFileOpsUndo:
        return Future.value(_opsReport(ops));
      // 返回 bool 的三个：回收站能不能撤销、打断当前批、以及关会话。
      case #crateApiFileOpsFileOpsTrashRestoreSupported:
        return Future.value(ops.trashRestoreSupported);
      case #crateApiFileOpsFileOpsCancel:
      case #crateApiFileOpsFileOpsClose:
        return Future.value(true);

      default:
        // 兜底：没列出来的 file_ops 桥调用直接炸在明处。
        //
        // 不这么做的话它会掉进下面那句 `Future.value(snapshot)`，变成一个
        // 「类型不符」的怪错误 —— 报错点指向、错的却是别的东西（`fileOpsClose`
        // 曾在 `dispose` 里报出 `Future<FileManagerSnapshot>` 不是 `Future<bool>`）。
        // 新增文件操作时想要的是「判据告诉我桩没跟上」，不是考古。
        final name = invocation.memberName.toString();
        if (name.contains('crateApiFileOps')) {
          throw UnimplementedError('测试桩还没有覆盖这个文件操作桥调用：$name');
        }
        return snapshotError == null
            ? Future.value(snapshot)
            : Future<FileManagerSnapshot>.error(snapshotError!);
    }
  }

  Iterable<Invocation> callsTo(Symbol name) =>
      calls.where((call) => call.memberName == name);
}

FileManagerTreeSnapshot _treeSnapshot() => const FileManagerTreeSnapshot(
  rows: [
    FileManagerTreeRow(
      path: '/',
      name: '/',
      depth: 0,
      expanded: true,
      loading: false,
      mayHaveChildren: true,
      isActive: false,
    ),
    FileManagerTreeRow(
      path: '/books',
      name: 'books',
      depth: 1,
      expanded: true,
      loading: false,
      mayHaveChildren: true,
      isActive: true,
    ),
    FileManagerTreeRow(
      path: '/books/series',
      name: 'series',
      depth: 2,
      expanded: false,
      loading: true,
      mayHaveChildren: true,
      isActive: false,
    ),
    FileManagerTreeRow(
      path: '/books/loose',
      name: 'loose',
      depth: 2,
      expanded: false,
      loading: false,
      mayHaveChildren: false,
      isActive: false,
    ),
  ],
  hasPending: false,
);

FileManagerTab _tab(
  int id,
  String title, {
  bool canClose = true,
  bool canGoBack = false,
  bool canGoForward = false,
}) => FileManagerTab(
  id: BigInt.from(id),
  title: title,
  path: '/books/$title',
  canGoBack: canGoBack,
  canGoForward: canGoForward,
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
  String? searchDirectory,
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
  searchDirectory: searchDirectory,
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
  bool canGoBack = false,
  bool canGoForward = false,
  bool columnsEnabled = false,
  String? homePath,
  bool isHome = false,
  bool canSetHome = true,
  bool sortTemporary = false,
  bool canSortPreference = true,
  bool rememberViewState = true,
  bool subfolders = false,
  bool searchActive = false,
  int tabCount = 2,
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
    _tab(
      1,
      'books',
      canClose: canClose,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
    ),
    if (tabCount > 1) _tab(2, 'pictures'),
  ],
  recentlyClosed: [_tab(3, 'closed')],
  entries: searchActive
      ? [
          // 搜索结果页签：同名条目只有靠相对目录才分得开。
          _entry('001.jpg', searchDirectory: '春组/本子'),
          _entry('cover.cbz', searchDirectory: '春组'),
        ]
      : [
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
  searchInPath: true,
  searchOrMode: false,
  searchIncludeSubfolders: subfolders,
  searchMaxDepth: 6,
  searchActive: searchActive,
  searchResultQuery: searchActive ? query : '',
  searchScanned: searchActive ? 120 : 0,
  searchMatched: searchActive ? 2 : 0,
  searchTruncated: false,
  searchCancelled: false,
  canSaveSearchTab: searchActive,
  entryFilter: FileManagerEntryFilter.all,
  sortField: FileManagerSortField.name,
  sortOrder: FileManagerSortOrder.ascending,
  directoriesFirst: true,
  homePath: homePath,
  isHome: isHome,
  canSetHome: canSetHome,
  sortTemporary: sortTemporary,
  canSortPreference: canSortPreference,
  rememberViewState: rememberViewState,
);

/// 文件操作那一份会话快照的替身（选中集合 / 剪贴板 / 撤销栈）。
///
/// `generation` 与 [_snapshot] 取同一个值不是随手写的：卡片只在「管理器快照的
/// 版本号变了」时才回头问这一份（见 `_acceptSnapshot`），两个数一样时它只在建
/// 会话那一次问，测试里不会凭空多出一串待收的问询。
FileOpsSnapshot _opsSnapshot({
  int total = 2,
  int selectedCount = 0,
  List<String> selectedPaths = const [],
  bool selectionHasDirectory = false,
  bool canPaste = false,
  FileOpsClipboardMode? clipboardMode,
  int clipboardCount = 0,
  bool canUndo = false,
  int undoCount = 0,
  bool trashRestoreSupported = true,
}) => FileOpsSnapshot(
  sessionId: BigInt.one,
  generation: BigInt.one,
  total: total,
  selectedCount: selectedCount,
  allSelected: selectedCount > 0 && selectedCount == total,
  selectedPaths: selectedPaths,
  selectionHasDirectory: selectionHasDirectory,
  canPaste: canPaste,
  clipboardMode: clipboardMode,
  clipboardCount: clipboardCount,
  canUndo: canUndo,
  undoCount: undoCount,
  trashRestoreSupported: trashRestoreSupported,
);

/// 一次文件操作的回执替身。默认「什么都没做」：判据要的是卡片**收到回执之后**
/// 怎么刷新，而不是替身自己编一份结果。
FileOpsReport _opsReport(
  FileOpsSnapshot snapshot, {
  String kind = 'copy',
  int succeeded = 0,
  int failed = 0,
  int undoable = 0,
  String summary = '',
  List<FileOpsItemResult> items = const [],
}) => FileOpsReport(
  kind: kind,
  succeeded: succeeded,
  failed: failed,
  cancelled: 0,
  undoable: undoable,
  summary: summary,
  items: items,
  snapshot: snapshot,
);

/// 主页不再是独立的 IconButton，而是导航掌里的一片多边形热区。
///
/// 它没有自己的图标（可见的只是底部一道横杠），所以按 Tooltip 文案找；
/// 而它的**矩形是整只掌**，中心被刷新圆键占着 —— 想点到「下区」必须
/// 自己算一个落在梯形里的点，直接 `tester.tap(finder)` 会点到刷新。
Finder _homeRegion() => find.byWidgetPredicate(
  (widget) => widget is Tooltip && (widget.message ?? '').startsWith('主页'),
);

/// 主页热区（掌形下部的梯形）里的一个点：宽度的中间、高度的 85%。
Offset _homeRegionPoint(WidgetTester tester) {
  final rect = tester.getRect(_homeRegion());
  return Offset(rect.center.dx, rect.top + rect.height * 0.85);
}

Future<void> _tapHomeRegion(WidgetTester tester) async {
  final target = _homeRegion();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tapAt(_homeRegionPoint(tester));
  await tester.pumpAndSettle();
}

Future<void> _longPressHomeRegion(WidgetTester tester) async {
  final target = _homeRegion();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.longPressAt(_homeRegionPoint(tester));
  await tester.pumpAndSettle();
}

/// 掌形里某个方向的落点：把归一化坐标映射到掌的矩形上。
Offset _padPoint(WidgetTester tester, Offset normalized) {
  final rect = tester.getRect(find.byType(FileManagerNavigationPad));
  return Offset(
    rect.left + rect.width * normalized.dx,
    rect.top + rect.height * normalized.dy,
  );
}

Future<GlobalSettingCubit> _pumpCard(
  WidgetTester tester, {
  double width = 340,
  GlobalSettingCubit? settings,
}) async {
  tester.view.physicalSize = const Size(1000, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = settings ?? _TestGlobalSettingCubit();
  await tester.pumpWidget(
    BlocProvider<GlobalSettingCubit>.value(
      value: cubit,
      child: MaterialApp(
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
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

/// 工具栏横向滚动，窄卡片下「文件树」那颗按钮先要滚进视口才点得到。
Future<void> _openTree(WidgetTester tester) async {
  final toggle = find.byTooltip('文件树');
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

void main() {
  late _FileManagerApi api;
  late _TestGlobalSettingCubit settings;
  setUp(() {
    api = _FileManagerApi();
    settings = _TestGlobalSettingCubit();
    RustLib.initMock(api: api);
    // 启动期才解析的路径，测试里默认按「还没解析出来」起跑；需要它的用例自己注入。
    preparedSettingsDbPathForTests = null;
  });
  // FRB 2.12 的 `RustLib.dispose()` 只关端口管理器，**不**清 `_EntrypointState`，
  // 所以下一个用例的 `initMock` 会撞「Should not initialize flutter_rust_bridge twice」，
  // 整个文件只有第一个用例能跑。`resetState()` 是它留给测试的出口。
  tearDown(() {
    RustLib.dispose();
    // ignore: invalid_use_of_internal_member
    RustLib.instance.resetState();
  });

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

    final searchToggle = find.byTooltip('搜索（空格分词，-排除）');
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

  testWidgets('输入即搜：不等回车，跨过防抖窗口就提交，提交期间输入框仍可打字', (tester) async {
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '春 日 -草稿');
    // 防抖窗口内还没发出去 —— 连续敲字不会每个字符打一次桥。
    await tester.pump(const Duration(milliseconds: 60));
    expect(api.callsTo(#crateApiFileManagerFileManagerSetSearchQuery), isEmpty);

    // 让这一次提交挂在飞行中，才测得到「请求期间输入框不能失效」。
    final gate = Completer<FileManagerSnapshot>();
    api.searchReply = gate;
    await tester.pump(const Duration(milliseconds: 200));
    final calls = api.callsTo(#crateApiFileManagerFileManagerSetSearchQuery);
    expect(calls, hasLength(1));
    expect(calls.single.namedArguments[#query], '春 日 -草稿');
    expect(
      tester.widget<TextField>(find.byType(TextField)).enabled,
      isNot(isFalse),
    );

    // 飞行中继续改词：防抖会再发一次，后发的那一次说话。
    await tester.enterText(find.byType(TextField), '春 日 -草稿 修');
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      api.callsTo(#crateApiFileManagerFileManagerSetSearchQuery).length,
      2,
    );
    api.searchReply = null;
    gate.complete(_snapshot(query: '春 日 -草稿 修'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '春 日 -草稿 修',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('搜索时敲进去的空格不会被核心回显吃掉', (tester) async {
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();

    // 核心会把查询 trim 掉，快照里回来的是「春日」；框里必须还是用户打的那一份。
    api.snapshot = _snapshot(query: '春日');
    await tester.enterText(find.byType(TextField), '春日 ');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '春日 ',
    );

    // 但核心自己改了查询（切页签、导航会清空）时必须盖回来，
    // 否则框里留着一个已经不再生效的词。
    api.snapshot = _snapshot();
    await tester.tap(find.byTooltip('新建页签'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('含子目录开关提交条件并触发一次递归搜索', (tester) async {
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();

    api.snapshot = _snapshot(query: '春', subfolders: true);
    await tester.tap(find.text('含子目录'));
    await tester.pumpAndSettle();

    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetSearchIncludeSubfolders)
          .single
          .namedArguments[#enabled],
      isTrue,
    );
    // 条件一变就跑一次遍历；结果由 Rust 写进页签，卡片不再有第二份列表。
    expect(api.callsTo(#crateApiFileManagerFileManagerSearch), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('搜索结果页签：命中带相对目录，提供回到目录与存为页签', (tester) async {
    // 查询非空时搜索行本来就在（不必先展开），这一条测的是结果态的画法和出口。
    // 选项行是横向滚动的，宽一点才不用为每个芯片单独滚动。
    api.snapshot = _snapshot(query: '春', subfolders: true, searchActive: true);
    await _pumpCard(tester, width: 700);
    await tester.pumpAndSettle();

    // 副标题最前面带上「哪本子目录」，同名条目才分得开。
    expect(find.textContaining('春组/本子'), findsOneWidget);
    expect(find.text('命中 2 · 已看 120'), findsOneWidget);

    for (final label in ['存为页签', '回到目录']) {
      final chip = find.text(label);
      expect(chip, findsOneWidget);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }
    expect(
      api.callsTo(#crateApiFileManagerFileManagerSaveSearchAsTab),
      hasLength(1),
    );
    expect(
      api.callsTo(#crateApiFileManagerFileManagerClearSearch),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('还没下查询时搜索行显示历史，点一下就再搜一次', (tester) async {
    api.history.addAll(['旧词', '更旧的词']);
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();
    expect(find.text('旧词'), findsOneWidget);
    expect(find.text('更旧的词'), findsOneWidget);

    await tester.tap(find.text('旧词'));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetSearchQuery)
          .single
          .namedArguments[#query],
      '旧词',
    );
    // 点历史词是「主动定下的搜索」，所以要进历史；防抖那一路不进。
    expect(
      api.callsTo(#crateApiFileManagerFileManagerRecordSearchHistory),
      hasLength(1),
    );

    await tester.tap(find.text('清空历史'));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerFileManagerClearSearchHistory),
      hasLength(1),
    );
    await tester.pumpAndSettle();
    expect(find.text('旧词'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('防抖那一路不写搜索历史', (tester) async {
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '随手打词');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerFileManagerSetSearchQuery),
      hasLength(1),
    );
    expect(
      api.callsTo(#crateApiFileManagerFileManagerRecordSearchHistory),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('导航掌五个方向各自派发对应动作，互不抢事件', (tester) async {
    api.snapshot = _snapshot(
      canGoBack: true,
      canGoForward: true,
      homePath: '/home',
    );
    await _pumpCard(tester);

    // 每片热区都是被 ClipPath 裁过的多边形：点在轮廓里才算命中。
    // 取点还要避开中心的刷新圆（它占中间 0.28~0.72 那一块并且压在四片之上），
    // 否则点「左」会点成「刷新」—— 这正是这个用例要守住的行为。
    await tester.tapAt(_padPoint(tester, const Offset(0.15, 0.5)));
    await tester.pumpAndSettle();
    expect(api.callsTo(#crateApiFileManagerFileManagerGoBack), hasLength(1));

    await tester.tapAt(_padPoint(tester, const Offset(0.85, 0.5)));
    await tester.pumpAndSettle();
    expect(api.callsTo(#crateApiFileManagerFileManagerGoForward), hasLength(1));

    await tester.tapAt(_padPoint(tester, const Offset(0.5, 0.2)));
    await tester.pumpAndSettle();
    expect(api.callsTo(#crateApiFileManagerFileManagerGoUp), hasLength(1));

    // 中心圆：刷新。它压在四片热区之上，这一块必须归它。
    await tester.tapAt(_padPoint(tester, const Offset(0.5, 0.5)));
    await tester.pumpAndSettle();
    expect(api.callsTo(#crateApiFileManagerFileManagerRefresh), hasLength(1));
    // 上一步不能顺带把「主页」也触发了。
    expect(api.callsTo(#crateApiFileManagerFileManagerGoHome), isEmpty);

    await _tapHomeRegion(tester);
    expect(api.callsTo(#crateApiFileManagerFileManagerGoHome), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('卡片够宽时导航摊开成五颗标准键，掌形不画', (tester) async {
    api.snapshot = _snapshot(
      canGoBack: true,
      canGoForward: true,
      homePath: '/home',
    );
    await _pumpCard(tester, width: 700);

    expect(find.byType(FileManagerNavigationPad), findsNothing);
    // 动作与掌形一一对应，tooltip 文案也是同一份 —— 换画法不换语义。
    for (final tip in ['后退', '前进', '上一级', '刷新']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(_homeRegion(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('摊开形态各自派发对应动作，主页那颗右键也弹菜单', (tester) async {
    api.snapshot = _snapshot(
      canGoBack: true,
      canGoForward: true,
      homePath: '/home',
    );
    await _pumpCard(tester, width: 700);

    await tester.tap(find.byTooltip('后退'));
    await tester.pumpAndSettle();
    expect(api.callsTo(#crateApiFileManagerFileManagerGoBack), hasLength(1));

    await tester.tap(find.byTooltip('前进'));
    await tester.pumpAndSettle();
    expect(api.callsTo(#crateApiFileManagerFileManagerGoForward), hasLength(1));

    await tester.tap(find.byTooltip('上一级'));
    await tester.pumpAndSettle();
    expect(api.callsTo(#crateApiFileManagerFileManagerGoUp), hasLength(1));

    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(api.callsTo(#crateApiFileManagerFileManagerRefresh), hasLength(1));
    expect(api.callsTo(#crateApiFileManagerFileManagerGoHome), isEmpty);

    await _tapHomeRegion(tester);
    expect(api.callsTo(#crateApiFileManagerFileManagerGoHome), hasLength(1));

    // 右键入口挂在按钮外层：桌面端不必先长按。
    await tester.tapAt(_homeRegionPoint(tester), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('回到主页'), findsOneWidget);
    expect(find.text('把当前目录设为主页'), findsOneWidget);
    expect(find.text('清除主页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('工具栏整行只有一个几何档：图标钮 40 见方', (tester) async {
    api.snapshot = _snapshot(
      canGoBack: true,
      canGoForward: true,
      homePath: '/home',
    );
    await _pumpCard(tester, width: 700);

    // 40 是 MD3 图标按钮的规范边长；写死数字而不是引常量，否则改坏常量测不出来。
    const md3Button = Size(40, 40);
    for (final tip in [
      '后退',
      '刷新',
      '视图模式：封面列表',
      '排序：名称',
      '搜索（空格分词，-排除）',
      '文件树',
      '关闭穿透模式',
      '更多',
    ]) {
      expect(tester.getRect(find.byTooltip(tip)).size, md3Button, reason: tip);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('收起形态的掌与摊开时同高，整行只有一个高度带', (tester) async {
    api.snapshot = _snapshot(
      canGoBack: true,
      canGoForward: true,
      homePath: '/home',
    );
    await _pumpCard(tester, width: 340);

    expect(find.byType(FileManagerNavigationPad), findsOneWidget);
    expect(
      tester.getRect(find.byType(FileManagerNavigationPad)).size,
      const Size(40, 40),
    );
    expect(tester.getRect(find.byTooltip('更多')).size, const Size(40, 40));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('未设主页时单击即设主页，并写回全局设置', (tester) async {
    // 未设主页时不再禁用：第一次用的人不必先猜「要长按/右键」。
    settings = _TestGlobalSettingCubit();
    await _pumpCard(tester, settings: settings);

    // 卡片内部快照只随动作的**返回值**更新，所以先把 mock 换成「已接受该主页」，
    // 再点 —— 用来断言卡片落盘的确实是核心接受后的那个路径。
    api.snapshot = _snapshot(homePath: '/books');
    await _tapHomeRegion(tester);

    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetHomePath)
          .single
          .namedArguments[#path],
      '/books',
    );
    expect(settings.state.fileManagerSetting.homePath, '/books');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('已设主页时单击回主页，长按菜单里可改设与清除', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(homePath: '/home'),
    );
    api.snapshot = _snapshot(homePath: '/home');
    await _pumpCard(tester, settings: settings);

    await _tapHomeRegion(tester);
    expect(api.callsTo(#crateApiFileManagerFileManagerGoHome), hasLength(1));

    // 长按打开主页菜单：三个动作按当前能力置灰。
    await _longPressHomeRegion(tester);
    expect(find.text('回到主页'), findsOneWidget);
    expect(find.text('把当前目录设为主页'), findsOneWidget);
    expect(find.text('清除主页'), findsOneWidget);

    await tester.tap(find.text('把当前目录设为主页'));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetHomePath)
          .single
          .namedArguments[#path],
      '/books',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('主页键可被全局设置关掉', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(homeEnabled: false),
    );
    await _pumpCard(tester, settings: settings);
    expect(_homeRegion(), findsNothing);
    // 其余导航方向不受影响：掌还在，四个方向加中心刷新都还在。
    expect(find.byType(FileManagerNavigationPad), findsOneWidget);
    expect(find.byTooltip('刷新'), findsOneWidget);
    expect(find.byTooltip('后退'), findsOneWidget);
    expect(find.byTooltip('上一级'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('会话创建时带上落盘的主页', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(homePath: '/home'),
    );
    await _pumpCard(tester, settings: settings);
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerCreate)
          .single
          .namedArguments[#homePath],
      '/home',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('没设过主页时不传参数，会话保持未设主页', (tester) async {
    settings = _TestGlobalSettingCubit();
    await _pumpCard(tester, settings: settings);
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerCreate)
          .single
          .namedArguments[#homePath],
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('开了「启动时默认打开主页」后会话直接落在主页目录', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(
        homePath: '/home',
        openHomeOnStart: true,
      ),
    );
    await _pumpCard(tester, settings: settings);
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerCreate)
          .single
          .namedArguments[#initialPath],
      '/home',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('开关默认关着：不传 initialPath，由核心选默认目录', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(homePath: '/home'),
    );
    await _pumpCard(tester, settings: settings);
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerCreate)
          .single
          .namedArguments[#initialPath],
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('主页键关掉后启动落点跟着失效，不出现「主页没了却还往里跳」', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(
        homeEnabled: false,
        homePath: '/home',
        openHomeOnStart: true,
      ),
    );
    await _pumpCard(tester, settings: settings);
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerCreate)
          .single
          .namedArguments[#initialPath],
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('开着开关但还没设主页时不传 initialPath', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(openHomeOnStart: true),
    );
    await _pumpCard(tester, settings: settings);
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerCreate)
          .single
          .namedArguments[#initialPath],
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('会话创建时带上设置库路径与记忆开关', (tester) async {
    preparedSettingsDbPathForTests = '/tmp/rossi/settings.db';
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(
        rememberViewState: false,
      ),
    );
    await _pumpCard(tester, settings: settings);

    final args = api
        .callsTo(#crateApiFileManagerFileManagerCreate)
        .single
        .namedArguments;
    expect(args[#settingsDbPath], '/tmp/rossi/settings.db');
    expect(args[#rememberViewState], isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('路径还没解析出来时按不记忆建会话，而不是卡在加载态', (tester) async {
    preparedSettingsDbPathForTests = null;
    await _pumpCard(tester);

    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerCreate)
          .single
          .namedArguments[#settingsDbPath],
      isNull,
    );
    expect(find.text('book.cbz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('全局关掉记忆后同步给活着的会话，且不重复打桥', (tester) async {
    await _pumpCard(tester, settings: settings);
    expect(
      api.callsTo(#crateApiFileManagerFileManagerSetRememberViewState),
      isEmpty,
    );

    settings.updateFileManagerSetting(
      (current) => current.copyWith(rememberViewState: false),
    );
    await tester.pumpAndSettle();

    final calls = api.callsTo(
      #crateApiFileManagerFileManagerSetRememberViewState,
    );
    expect(calls, hasLength(1));
    expect(calls.single.namedArguments[#enabled], isFalse);

    // 假 API 不会像 Rust 那样把新值写回快照，所以这里正好验「每次用户改动最多补发一次」：
    // 没有守卫的话每帧都会再发一次。
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerFileManagerSetRememberViewState),
      hasLength(1),
    );
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
        BlocProvider<GlobalSettingCubit>.value(
          value: _TestGlobalSettingCubit(),
          child: MaterialApp(
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

  // ── 文件树 ────────────────────────────────────────────────────────────────

  testWidgets('文件树默认关闭，打开后按 Rust 投影渲染缩进与箭头', (tester) async {
    await _pumpCard(tester);
    expect(
      find.byKey(const ValueKey('file-manager-tree:/books')),
      findsNothing,
    );

    await _openTree(tester);

    expect(
      api.callsTo(#crateApiFileManagerFileManagerTreeSnapshot),
      hasLength(1),
    );
    // 深度来自核心的 `visible_rows`，Dart 不自己数层。
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('file-manager-tree:/books/series')),
          )
          .contentPadding,
      const EdgeInsets.only(left: 32, right: 8),
    );
    // 确认是空目录的行不给箭头，否则点开只会是空的。
    expect(
      find.byKey(const ValueKey('file-manager-tree-toggle:/books/loose')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('file-manager-tree-toggle:/books/series')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('树里点箭头只展开节点，点行才提交跳转目录', (tester) async {
    await _pumpCard(tester);
    await _openTree(tester);

    await tester.tap(
      find.byKey(const ValueKey('file-manager-tree-toggle:/books/series')),
    );
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerTreeToggle)
          .single
          .namedArguments[#path],
      '/books/series',
    );
    expect(api.callsTo(#crateApiFileManagerFileManagerNavigate), isEmpty);

    await tester.tap(find.byKey(const ValueKey('file-manager-tree:/')));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerNavigate)
          .single
          .namedArguments[#path],
      '/',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('打开文件树时顺手关掉目录列，两者不同时占位', (tester) async {
    api.snapshot = _snapshot(columnsEnabled: true);
    await _pumpCard(tester);
    // 目录列里那一项，此时还没有树。
    expect(
      find.byKey(const ValueKey('file-manager-column:/books/series')),
      findsOneWidget,
    );

    await _openTree(tester);

    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetDirectoryColumns)
          .single
          .namedArguments[#enabled],
      isFalse,
    );
    expect(
      find.byKey(const ValueKey('file-manager-tree:/books')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('目录列只有一颗开关，藏在面包屑的路径操作菜单里', (tester) async {
    await _pumpCard(tester);
    // 工具栏上那颗（view_week）与行尾的编辑键都并进了这一颗菜单。
    expect(find.byIcon(Icons.view_week_rounded), findsNothing);
    expect(find.byTooltip('编辑目录路径'), findsNothing);

    await tester.tap(find.byTooltip('路径操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('展开目录列'));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerFileManagerSetDirectoryColumns)
          .single
          .namedArguments[#enabled],
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('单页签时收起整行页签，新建与恢复搬到路径操作菜单', (tester) async {
    api.snapshot = _snapshot(tabCount: 1);
    await _pumpCard(tester);
    expect(find.byType(InputChip), findsNothing);
    expect(find.byTooltip('新建页签'), findsNothing);
    expect(find.byTooltip('恢复已关闭页签'), findsNothing);

    await tester.tap(find.byTooltip('路径操作'));
    await tester.pumpAndSettle();
    expect(find.text('新建页签'), findsOneWidget);
    await tester.tap(find.text('恢复页签：closed'));
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

  testWidgets('面包屑左对齐：放得下的路径不顶到行尾', (tester) async {
    await _pumpCard(tester, width: 260);
    final scroll = find.byKey(const ValueKey('file-manager-breadcrumb-scroll'));
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('file-manager-breadcrumb:/')))
          .dx,
      closeTo(tester.getTopLeft(scroll).dx, 1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
