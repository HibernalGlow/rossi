part of '../file_manager_card_test.dart';

// 快照与条目的构造替身

FileManagerTreeSnapshot _treeSnapshot() => const FileManagerTreeSnapshot(
  rows: [
    FileManagerTreeRow(
      path: '/',
      name: '/',
      entry: null,
      depth: 0,
      expanded: true,
      loading: false,
      mayHaveChildren: true,
      isActive: false,
    ),
    FileManagerTreeRow(
      path: '/books',
      name: 'books',
      entry: null,
      depth: 1,
      expanded: true,
      loading: false,
      mayHaveChildren: true,
      isActive: true,
    ),
    FileManagerTreeRow(
      path: '/books/series',
      name: 'series',
      entry: null,
      depth: 2,
      expanded: false,
      loading: false,
      mayHaveChildren: true,
      isActive: false,
    ),
    FileManagerTreeRow(
      path: '/books/loose',
      name: 'loose',
      entry: null,
      depth: 2,
      expanded: false,
      loading: false,
      mayHaveChildren: false,
      isActive: false,
    ),
  ],
  hasPending: false,
);

/// 一条 13 行的目录链，当前目录在最深处，它下面还挂着三行子目录。
///
/// 摆这一份是为了复现「树展开了却没定位」：树的视口只有 200px 高，而
/// `ListView.builder` 只建看得见的行 —— 最深处那一行在滚之前根本不存在于树上，
/// 所以「它出现了」就是定位生效的证据（`hasPending` 同样固定为 false，
/// 否则懒扫描的轮询会让 `pumpAndSettle` 转不完）。
///
/// 当前目录**不是**最后一行：定位要做的是「把它搬到视口中间」，而不是
/// 「滚到头让它贴着底」，下面留几行才分得出这两种。
FileManagerTreeSnapshot _deepTreeSnapshot({int depth = 12}) {
  final rows = [
    for (var level = 0; level <= depth; level++)
      FileManagerTreeRow(
        path: level == 0 ? '/' : '/n$level',
        name: level == 0 ? '/' : 'n$level',
        entry: null,
        depth: level,
        expanded: true,
        loading: false,
        mayHaveChildren: true,
        isActive: level == depth,
      ),
    for (var leaf = 1; leaf <= 3; leaf++)
      FileManagerTreeRow(
        path: '/n$depth/c$leaf',
        name: 'c$leaf',
        entry: null,
        depth: depth + 1,
        expanded: false,
        loading: false,
        mayHaveChildren: false,
        isActive: false,
      ),
  ];
  return FileManagerTreeSnapshot(rows: rows, hasPending: false);
}

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
  bool penetratable = false,
  String? path,
}) => FileManagerEntry(
  path: path ?? '/books/$name',
  name: name,
  isDir: directory,
  isArchive: !directory,
  isImage: false,
  isVideo: false,
  isAudio: false,
  size: BigInt.from(1024),
  modifiedSecs: 1700000000,
  hasChildren: directory,
  // 核心对「这一行的单击会不会被穿透劫走」的判决（见 `penetratable` 字段）。
  // 替身默认给假：那正是「文件夹行不挂双击、单击立刻生效」的那一档，
  // 已有用例（例如多选那组点文件夹）都建立在它之上。
  penetratable: penetratable,
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
  FileManagerLayoutMode layoutMode = FileManagerLayoutMode.content,
  FileManagerViewMode viewMode = FileManagerViewMode.coverList,
  String query = '',
  bool canCreate = true,
  bool canClose = true,
  bool canGoBack = false,
  bool canGoForward = false,
  bool columnsEnabled = false,
  List<FileManagerDirectoryColumn>? columns,
  String? homePath,
  bool isHome = false,
  bool canSetHome = true,
  bool sortTemporary = false,
  bool canSortPreference = true,
  bool rememberViewState = true,
  bool subfolders = false,
  bool folderPenetratable = false,
  bool searchActive = false,
  bool depthLimited = false,
  bool noEntries = false,
  int tabCount = 2,
  int activeTabId = 1,
  List<FileManagerEntry>? entries,
}) => FileManagerSnapshot(
  sessionId: BigInt.one,
  maxTabs: 8,
  canCreateTab: canCreate,
  generation: BigInt.one,
  activeTabId: BigInt.from(activeTabId),
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
  directoryColumns:
      columns ??
      (columnsEnabled
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
          : const []),
  tabs: [
    _tab(
      1,
      'books',
      canClose: canClose,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
    ),
    if (tabCount > 1) _tab(2, 'pictures'),
    if (activeTabId > 2) _tab(activeTabId, 'search'),
  ],
  recentlyClosed: [_tab(3, 'closed')],
  // 「零命中」要能单独造出来：往下找的那条出口只在真的没命中时才该出现。
  entries:
      entries ??
      (noEntries
          ? const []
          : searchActive
          ? [
              // 搜索结果页签：同名条目只有靠相对目录才分得开。
              _entry('001.jpg', searchDirectory: '春组/本子'),
              _entry('cover.cbz', searchDirectory: '春组'),
            ]
          : [
              _entry('book.cbz'),
              _entry(
                'series with a long name',
                directory: true,
                children: 8,
                penetratable: folderPenetratable,
              ),
            ]),
  roots: const [LocalRootLocation(label: '主目录', path: '/home')],
  penetrationEnabled: true,
  showChildNames: true,
  internalItemsMode: FileManagerInternalItemsMode.all,
  maxDepth: 3,
  viewMode: viewMode,
  layoutMode: layoutMode,
  searchColumnPath: null,
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
  searchDepthLimited: depthLimited,
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
